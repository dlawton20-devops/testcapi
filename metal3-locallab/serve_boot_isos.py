#!/usr/bin/env python3
"""
Simple HTTP server to serve Ironic boot ISOs.
This server watches Ironic's shared directory and serves boot ISOs directly.
"""

import http.server
import socketserver
import os
import sys
from pathlib import Path

# Directory to serve boot ISOs from
BOOT_ISO_DIR = os.path.expanduser("~/metal3-images/boot-isos")
PORT = 8080
BIND_ADDRESS = "192.168.1.242"

class BootISOServer(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BOOT_ISO_DIR, **kwargs)
    
    def end_headers(self):
        # Add CORS headers if needed
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        super().end_headers()
    
    def do_GET(self):
        """Serve files from the boot ISO directory"""
        # Map /redfish/boot-*.iso to boot-*.iso in the directory
        if self.path.startswith('/redfish/boot-') and self.path.endswith('.iso'):
            # Extract filename
            filename = os.path.basename(self.path)
            filepath = os.path.join(BOOT_ISO_DIR, filename)
            
            if os.path.exists(filepath):
                # Serve the file directly with proper chunking for large files
                try:
                    file_size = os.path.getsize(filepath)
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/octet-stream')
                    self.send_header('Content-Length', str(file_size))
                    self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
                    self.send_header('Accept-Ranges', 'bytes')
                    self.end_headers()
                    
                    # Stream the file in chunks
                    with open(filepath, 'rb') as f:
                        chunk_size = 8192
                        while True:
                            chunk = f.read(chunk_size)
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                            self.wfile.flush()
                    
                    self.log_message(f"Served: {filename} ({file_size} bytes)")
                    return
                except Exception as e:
                    self.log_message(f"Error serving {filename}: {e}")
                    self.send_error(500, str(e))
                    return
            else:
                self.log_message(f"Boot ISO not found: {filename}")
                self.send_error(404, f"Boot ISO not found: {filename}")
                return
        
        # For other paths, try to serve normally
        return super().do_GET()
    
    def log_message(self, format, *args):
        """Custom log format"""
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")

def sync_boot_isos():
    """Sync boot ISOs from Ironic to local directory"""
    print("📥 Syncing boot ISOs from Ironic...")
    
    # Get Ironic pod
    import subprocess
    try:
        result = subprocess.run(
            ['kubectl', 'get', 'pods', '-n', 'metal3-system', 
             '-l', 'app.kubernetes.io/component=ironic', 
             '-o', 'jsonpath={.items[0].metadata.name}'],
            capture_output=True, text=True, check=True
        )
        ironic_pod = result.stdout.strip()
        
        if not ironic_pod:
            print("⚠️  No Ironic pod found")
            return
        
        # Copy boot ISOs from Ironic
        print(f"   Copying from pod: {ironic_pod}")
        # Try without container first (shared volume should be accessible)
        result = subprocess.run(
            ['kubectl', 'cp', 
             f'metal3-system/{ironic_pod}:/shared/html/redfish', 
             BOOT_ISO_DIR],
            capture_output=True, text=True
        )
        
        if result.returncode == 0:
            print("✅ Boot ISOs synced")
        else:
            print(f"⚠️  Sync failed: {result.stderr}")
    except Exception as e:
        print(f"⚠️  Error syncing: {e}")

def run_server(port=8080, bind_address='0.0.0.0'):
    """Run the HTTP server"""
    # Ensure directory exists
    os.makedirs(BOOT_ISO_DIR, exist_ok=True)
    
    # Initial sync
    sync_boot_isos()
    
    handler = BootISOServer
    httpd = socketserver.TCPServer((bind_address, port), handler)
    
    print(f"🚀 Boot ISO HTTP Server")
    print(f"   Listening on: http://{bind_address}:{port}")
    print(f"   Serving from: {BOOT_ISO_DIR}")
    print(f"   Press Ctrl+C to stop")
    print()
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down server...")
        httpd.shutdown()

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Boot ISO HTTP Server')
    parser.add_argument('--port', type=int, default=8080, help='Port to listen on (default: 8080)')
    parser.add_argument('--bind', default='0.0.0.0', help='Address to bind to (default: 0.0.0.0)')
    parser.add_argument('--dir', default=BOOT_ISO_DIR, help='Directory to serve from')
    args = parser.parse_args()
    
    BOOT_ISO_DIR = args.dir
    run_server(port=args.port, bind_address=args.bind)

