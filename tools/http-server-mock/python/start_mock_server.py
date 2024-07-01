#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

from http.server import HTTPServer, BaseHTTPRequestHandler
from server_address import get_localhost, get_best_server_address
import re
import json
import os
import sys
import time
import base64
import zlib

# If `--prefer-localhost` argument is set, the server will listen on http://127.0.0.1:8000.
# By default it tries to discover private IP address on local network and uses localhost as fallback.
prefer_localhost_flag = "--prefer-localhost" in sys.argv

class HTTPMockServer(BaseHTTPRequestHandler):
    """
    This server exposes followig endpoints:

    POST /*
    - Generic endpoint for recording any POST request.

    GET /inspect
    - Endpoint listing the history of recorded generic requests.
    """

    def do_POST(self):
        """
        Routes all incoming POST requests
        """
        self.__route([
            (r"(.*)$", self.__POST_any),
        ])

    def do_GET(self):
        """
        Routes all incoming GET requests
        """
        self.__route([
            (r"/inspect$", self.__GET_inspect),
        ])

    def do_DELETE(self):
        """
        Routes all incoming DELETE requests
        """
        self.__route([
            (r"/requests$", self.__DELETE_requests),
        ])

    def __POST_any(self, parameters):
        """
        POST /*

        Records generic request sent to this endpoint.
        """
        global history
        request_path = parameters[0]
        request_body = self.rfile.read(int(self.headers['Content-Length']))
        request_headers = '\n'.join([ f'{field}: {self.headers[field]}' for field in self.headers ]).encode('utf-8')

        # Decompress 'deflate' encoded body 
        if 'Content-Encoding' in self.headers and self.headers['Content-Encoding'] == 'deflate':
            request_body = zlib.decompress(request_body)

        request = GenericRequest("POST", request_path, request_headers, request_body)
        history.add_request(request)
        return bytes()

    def __GET_inspect(self, parameters):
        """
        GET /inspect

        Returns inspection info on all generic requests.
        """
        global history
        inspection_info = []
        for request in history.all_requests():
            inspection_info.append({
                "method": request.http_method,
                "path": request.path,
                "body": base64.b64encode(request.http_body).decode("utf-8") , # use Base64 string to not corrupt the JSON
                "headers": base64.b64encode(request.http_headers).decode("utf-8") # use Base64 string to not corrupt the JSON
            })

        return json.dumps(inspection_info).encode("utf-8")

    def __DELETE_requests(self, parameters):
        """
        DELETE /requests

        Remove all.
        """
        global history
        history.clear()
        return bytes()

    def __route(self, routes):
        try:
            for url_regexp, method in routes:
                match = re.match(url_regexp, self.path)
                if match is not None:
                    result = method(match.groups())
                    self.send_response(200) # OK
                    self.end_headers()
                    self.wfile.write(result)
                    return
        except (IndexError, KeyError) as e:
            self.send_response(400) # bad request
            self.end_headers()
            return

        self.send_response(404) # not found
        self.end_headers()
        return

class GenericRequest:
    """
    Represents data of request sent to generic endponit.
    """

    def __init__(self, http_method, path, http_headers, http_body):
        self.id = None # set later by `GenericRequestsHistory`
        self.path = path
        self.http_method = http_method
        self.http_headers = http_headers
        self.http_body = http_body

class GenericRequestsHistory:
    """
    Stores requests sent to generic endpoint.
    """

    __requests = []

    def add_request(self, generic_request):
        generic_request.id = len(self.__requests)
        self.__requests.append(generic_request)

    def all_requests(self):
        return self.__requests

    def request(self, request_id):
        return self.__requests[int(request_id)]

    def clear(self):
        self.__requests.clear()

# If any previous instance of this server is running - kill it
os.system('pkill -f start_mock_server.py')
time.sleep(1) # wait a bit until socket is eventually released

# Configure the server
history = GenericRequestsHistory()
address = get_localhost() if prefer_localhost_flag is True else get_best_server_address()
httpd = HTTPServer((address.ip, address.port), HTTPMockServer)

print("Starting server on http://{ip}:{port}".format( ip = address.ip, port = address.port))
httpd.serve_forever()
