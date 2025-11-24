#!/bin/bash
# Simple HTTP server for boot ISOs with /redfish path support

cd ~/metal3-images/boot-isos

# Create a simple Python server that handles /redfish paths
python3 << 'EOF'
import http.server
import socketserver
import os

PORT = 8081
DIR = os.path.expanduser("~/metal3-images/boot-isos")

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIR, **kwargs)
    
    def do_GET(self):
        # Map /redfish/boot-*.iso to boot-*.iso
        if self.path.startswith('/redfish/boot-') and self.path.endswith('.iso'):
            filename = os.path.basename(self.path)
            filepath = os.path.join(DIR, filename)
            if os.path.exists(filepath):
                self.path = f'/{filename}'
        return super().do_GET()

with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"🚀 Boot ISO Server on http://0.0.0.0:{PORT}")
    print(f"   Serving: {DIR}")
    httpd.serve_forever()
EOF

