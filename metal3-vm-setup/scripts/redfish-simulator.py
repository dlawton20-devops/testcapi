#!/usr/bin/env python3
"""
Redfish API Simulator for Metal3 Bare Metal Provisioning
Simulates a Redfish-compatible BMC interface for testing Metal3
"""

import http.server
import socketserver
import json
import os
import sys

class RedfishSimulator(http.server.BaseHTTPRequestHandler):
    """Redfish API Simulator HTTP Request Handler"""
    
    def log_message(self, format, *args):
        """Suppress default HTTP logging for cleaner output"""
        pass
    
    def _send_json_response(self, data, status=200):
        """Helper to send JSON responses"""
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/redfish/v1/':
            # Service root
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#ServiceRoot.ServiceRoot",
                "@odata.id": "/redfish/v1/",
                "@odata.type": "#ServiceRoot.v1_5_0.ServiceRoot",
                "Id": "RootService",
                "Name": "Root Service",
                "Systems": {"@odata.id": "/redfish/v1/Systems"},
                "Managers": {"@odata.id": "/redfish/v1/Managers"}
            })
        
        elif self.path == '/redfish/v1/Systems':
            # Systems collection
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#ComputerSystemCollection.ComputerSystemCollection",
                "@odata.id": "/redfish/v1/Systems",
                "@odata.type": "#ComputerSystemCollection.ComputerSystemCollection",
                "Name": "Computer System Collection",
                "Members@odata.count": 1,
                "Members": [{"@odata.id": "/redfish/v1/Systems/1"}]
            })
        
        elif self.path == '/redfish/v1/Systems/1':
            # System details
            cpu_count = int(os.environ.get('CPU_COUNT', 8))
            memory_gb = int(os.environ.get('MEMORY_GB', 64))
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#ComputerSystem.ComputerSystem",
                "@odata.id": "/redfish/v1/Systems/1",
                "@odata.type": "#ComputerSystem.v1_15_0.ComputerSystem",
                "Id": "1",
                "Name": "System",
                "PowerState": "On",
                "Boot": {
                    "BootSourceOverrideEnabled": "Once",
                    "BootSourceOverrideTarget": "Cd",
                    "BootSourceOverrideMode": "UEFI"
                },
                "Processors": {
                    "Count": cpu_count,
                    "Model": os.environ.get('CPU_MODEL', 'Intel Xeon E5-2680 v4')
                },
                "Memory": {
                    "TotalSystemMemoryGiB": memory_gb
                },
                "Storage": {
                    "Drives": [{
                        "CapacityBytes": int(os.environ.get('STORAGE_BYTES', 1000000000000)),
                        "MediaType": "SSD"
                    }]
                }
            })
        
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1':
            # Virtual Media status
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#VirtualMedia.VirtualMedia",
                "@odata.id": "/redfish/v1/Systems/1/VirtualMedia/1",
                "@odata.type": "#VirtualMedia.v1_4_0.VirtualMedia",
                "Id": "1",
                "Name": "Virtual Media",
                "Image": os.environ.get('INSERTED_IMAGE', ''),
                "Inserted": os.environ.get('INSERTED_IMAGE', '') != '',
                "WriteProtected": True
            })
        
        elif self.path == '/redfish/v1/Managers':
            # Managers collection
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#ManagerCollection.ManagerCollection",
                "@odata.id": "/redfish/v1/Managers",
                "@odata.type": "#ManagerCollection.ManagerCollection",
                "Name": "Manager Collection",
                "Members@odata.count": 1,
                "Members": [{"@odata.id": "/redfish/v1/Managers/1"}]
            })
        
        elif self.path == '/redfish/v1/Managers/1':
            # Manager details
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#Manager.Manager",
                "@odata.id": "/redfish/v1/Managers/1",
                "@odata.type": "#Manager.v1_15_0.Manager",
                "Id": "1",
                "Name": "BMC Manager",
                "ManagerType": "BMC",
                "FirmwareVersion": "1.0.0"
            })
        
        else:
            # Not found
            self.send_response(404)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found", "path": self.path}).encode())
    
    def do_POST(self):
        """Handle POST requests (actions)"""
        if self.path == '/redfish/v1/Systems/1/Actions/ComputerSystem.Reset':
            # System reset action
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                post_data = self.rfile.read(content_length)
            
            self._send_json_response({
                "Status": "Success",
                "Message": "System reset initiated"
            })
        
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1/Actions/VirtualMedia.InsertMedia':
            # Insert virtual media (ISO/image)
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = {}
            if content_length > 0:
                post_data = json.loads(self.rfile.read(content_length).decode())
            
            # Store inserted image in environment (simulated)
            image_url = post_data.get('Image', '')
            if image_url:
                os.environ['INSERTED_IMAGE'] = image_url
            
            self._send_json_response({
                "Status": "Success",
                "ImageInserted": True,
                "Image": image_url
            })
        
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1/Actions/VirtualMedia.EjectMedia':
            # Eject virtual media
            os.environ.pop('INSERTED_IMAGE', None)
            self._send_json_response({
                "Status": "Success",
                "Message": "Media ejected"
            })
        
        else:
            # Not found
            self.send_response(404)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found"}).encode())

if __name__ == "__main__":
    PORT = int(os.environ.get('PORT', 8000))
    HOST = os.environ.get('HOST', '0.0.0.0')
    
    with socketserver.TCPServer((HOST, PORT), RedfishSimulator) as httpd:
        print(f"Redfish Simulator running on {HOST}:{PORT}", flush=True)
        print(f"CPU Count: {os.environ.get('CPU_COUNT', 8)}", flush=True)
        print(f"Memory: {os.environ.get('MEMORY_GB', 64)} GB", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down simulator", flush=True)
            sys.exit(0)

