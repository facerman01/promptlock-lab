#!/usr/bin/env python3
"""
Dockerized HTTP POST receiver - saves to ./received_files/
"""

import http.server
import socketserver
import os
from datetime import datetime

# Create received_files dir
os.makedirs('received_files', exist_ok=True)

class POSTHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        
        # Dual save: binary + text
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:-3]
        bin_file = f'received_files/recv_{timestamp}_{content_length}b.bin'
        txt_file = f'received_files/recv_{timestamp}_{content_length}b.txt'
        
        # Save binary
        with open(bin_file, 'wb') as f:
            f.write(post_data)
        
        # Save as UTF-8 text (if possible)
        try:
            text_data = post_data.decode('utf-8')
            with open(txt_file, 'w', encoding='utf-8') as f:
                f.write(text_data)
        except UnicodeDecodeError:
            # Binary → note in text file
            with open(txt_file, 'w', encoding='utf-8') as f:
                f.write(f"BINARY DATA ({content_length} bytes) - use .bin file\n")
                f.write(f"Hex preview: {post_data[:64].hex()}\n")
        
        print(f"\n[OK] [{timestamp}] {content_length} bytes -> {bin_file}")
        print(f"Text: {txt_file}")
        print(f"Preview: {repr(post_data[:80])}")
        print("-" * 60)
        
        # 200 OK (ASCII-safe bytes)
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"File received and saved\n")

if __name__ == "__main__":
    print("Docker POST receiver on :9001")
    print("Files saved to ./received_files/")
    print("Test: curl -X POST --data-binary @secret.txt http://host.docker.internal:9001")
    
    with socketserver.TCPServer(("0.0.0.0", 9001), POSTHandler) as httpd:
        print("Ready - Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped")