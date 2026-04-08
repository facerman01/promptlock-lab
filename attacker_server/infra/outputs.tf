output "cdn_domain" {
  description = "The main domain for both downloads and exfiltration"
  value       = aws_cloudfront_distribution.unified_cdn.domain_name
}

output "binary_download_url" {
  description = "URL to download your binary (make sure it's in the /updates/ folder in S3)"
  value       = "https://${aws_cloudfront_distribution.unified_cdn.domain_name}/updates/your-binary-name"
}

output "exfiltration_endpoint" {
  description = "The URL your script should POST data to"
  value       = "https://${aws_cloudfront_distribution.unified_cdn.domain_name}/api/v1/telemetry"
}

output "attacker_ec2_public_ip" {
  description = "Public IP of your receiver server"
  value       = aws_instance.attacker_server.public_ip
}