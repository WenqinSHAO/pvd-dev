#!/usr/bin/env python
 
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket
import json
import time
from filelock import FileLock, Timeout

OPER_DIR = "/tmp"
REQUEST_LOCK_FILE = OPER_DIR + "/login_requests6.lock"
REQUEST_FILE = OPER_DIR + "/login_requests6.json"

def RequestAccess(ip_address):
    ipList = [ip_address]

    print("Requesting access for %s" % ip_address)
    
    lock = FileLock(REQUEST_LOCK_FILE, timeout=1)
    try:
        with lock:
            with open(REQUEST_FILE, "w") as request_file:
                json.dump(ipList, request_file)
    except Timeout:
        return "Request Timed Out"

    tries = 0
    while tries < 5:
        try:
            with lock:
                with open(REQUEST_FILE, "r") as request_file:
                    result = json.load(request_file)
                    ipSet = set(result)
                    if result.count(ip_address) == 0:
                        return "Success"
        except Timeout:
            pass;
        except json.decoder.JSONDecodeError:
            # this is the same as the list being empty
            return "Success"
        
        tries += 1
        # try again in a bit
        time.sleep(1)
         


 
# HTTPRequestHandler class
class CapportHTTPServer_RequestHandler(BaseHTTPRequestHandler):
 
  # GET
  def do_GET(self):
        # Send response status code
        self.send_response(200)
 
        # Send headers
        self.send_header('Content-type','text/html')
        self.end_headers()
 
        message = RequestAccess(self.client_address[0])
        # Write content as utf-8 data
        self.wfile.write(bytes(message, "utf8"))
        return
 
class HTTPServerV6(HTTPServer):
    address_family=socket.AF_INET6

def run():
 
  server_address = ('2001:67c:1230:f1a1::1', 80)
  httpd = HTTPServerV6(server_address, CapportHTTPServer_RequestHandler)
  print("The cake is a lie")
  httpd.serve_forever()
 
 
run()
