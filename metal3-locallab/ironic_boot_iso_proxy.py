#!/usr/bin/env python3
"""
HTTP proxy server for Ironic boot ISOs.
This server proxies requests to Ironic's boot ISO endpoint,
providing a more reliable connection for sushy-tools.
"""

import http.server
import socketserver
import urllib.request
import urllib.error
import ssl
import sys
from urllib.parse import urlparse, urlunparse

# Ironic backend URL (via kubectl port-forward on localhost)
IRONIC_BACKEND = "https://localhost:6385"

class IronicProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        """Proxy GET requests to Ironic"""
        try:
            # Build backend URL
            backend_url = f"{IRONIC_BACKEND}{self.path}"
            
            # Create SSL context to ignore certificate verification
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            
            # Make request to Ironic
            req = urllib.request.Request(backend_url)
            req.add_header('User-Agent', 'Ironic-Boot-ISO-Proxy/1.0')
            
            with urllib.request.urlopen(req, context=ssl_context, timeout=30) as response:
                # Get response data
                data = response.read()
                
                # Send response headers
                self.send_response(response.getcode())
                
                # Copy relevant headers
                content_type = response.headers.get('Content-Type', 'application/octet-stream')
                content_length = response.headers.get('Content-Length', str(len(data)))
                
                self.send_header('Content-Type', content_type)
                self.send_header('Content-Length', content_length)
                
                # Copy other useful headers
                for header in ['Content-Disposition', 'Accept-Ranges']:
                    if header in response.headers:
                        self.send_header(header, response.headers[header])
                
                self.end_headers()
                
                # Send response body
                self.wfile.write(data)
                
                self.log_message(f"Proxied {self.path} -> {backend_url} ({len(data)} bytes)")
                
        except urllib.error.HTTPError as e:
            self.send_error(e.code, e.reason)
            self.log_message(f"Error proxying {self.path}: {e.code} {e.reason}")
        except Exception as e:
            self.send_error(500, str(e))
            self.log_message(f"Error proxying {self.path}: {e}")
    
    def do_HEAD(self):
        """Handle HEAD requests"""
        try:
            backend_url = f"{IRONIC_BACKEND}{self.path}"
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            
            req = urllib.request.Request(backend_url, method='HEAD')
            with urllib.request.urlopen(req, context=ssl_context, timeout=30) as response:
                self.send_response(response.getcode())
                for header in ['Content-Type', 'Content-Length', 'Content-Disposition']:
                    if header in response.headers:
                        self.send_header(header, response.headers[header])
                self.end_headers()
        except Exception as e:
            self.send_error(500, str(e))
    
    def log_message(self, format, *args):
        """Custom log format"""
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")

def run_server(port=8080, bind_address='0.0.0.0'):
    """Run the proxy server"""
    handler = IronicProxyHandler
    httpd = socketserver.TCPServer((bind_address, port), handler)
    
    print(f"🚀 Ironic Boot ISO Proxy Server")
    print(f"   Listening on: http://{bind_address}:{port}")
    print(f"   Backend: {IRONIC_BACKEND}")
    print(f"   Press Ctrl+C to stop")
    print()
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down server...")
        httpd.shutdown()

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Ironic Boot ISO Proxy Server')
    parser.add_argument('--port', type=int, default=8080, help='Port to listen on (default: 8080)')
    parser.add_argument('--bind', default='0.0.0.0', help='Address to bind to (default: 0.0.0.0)')
    parser.add_argument('--backend', default='https://localhost:6385', help='Ironic backend URL')
    args = parser.parse_args()
    
    IRONIC_BACKEND = args.backend
    run_server(port=args.port, bind_address=args.bind)

