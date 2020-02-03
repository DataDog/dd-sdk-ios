#!/usr/bin/python

from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
from io import BytesIO
import os
import sys

class SucceedingHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        global files_count
        content_length = int(self.headers['Content-Length'])
        body = self.rfile.read(content_length)
        self.send_response(200)
        self.end_headers()
        response = BytesIO()
        response.write(b'{}')
        self.wfile.write(response.getvalue())
        file = open("{}/request{}.txt".format(requests_directory, files_count), "w+")
        file.write(body)
        file.close()

        print("\n----- Request Begin -----\n")
        print(self.path)
        print(self.headers)
        print(body)
        print("----- Request End -----\n")

        files_count += 1

requests_directory = sys.argv[1]
files_count = 0
httpd = HTTPServer(('localhost', 8000), SucceedingHTTPRequestHandler)
httpd.serve_forever()
