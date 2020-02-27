#!/usr/bin/python

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
import re
import json
import os

class HTTPMockServer(BaseHTTPRequestHandler):
    """
    This server exposes followig endpoints:

    POST /*
    - Generic endpoint for recording any POST request.

    GET /inspect
    - Endpoint listing history of recorded generic requests. It provides <request-id> information
    for each request to access its HTTP body with `GET /inspect/<request-id>`.

    GET /inspect/<request-id>
    - Endpoint returning HTTP body of specific generic request. 
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
            (r"/inspect/([0-9]+)$", self.__GET_inspect_request),
        ])

    def __POST_any(self, parameters):
        """
        POST /*

        Records generic request sent to this endpoint.
        """
        global history
        request_path = parameters[0]
        request_body = self.rfile.read(int(self.headers['Content-Length']))
        request = GenericRequest("POST", request_path, request_body)
        history.add_request(request)
        return "{}"

    def __GET_inspect(self, parameters):
        """
        GET /inspect

        Returns inspection info on all generic requests.
        """
        global history
        inspection_info = []
        for request in history.all_requests():
            inspection_info.append({
                "request_method": request.http_method,
                "request_path": request.path,
                "inspection_path": "/inspect/{request_id}".format( request_id = request.id )
            })
        return json.dumps(inspection_info)

    def __GET_inspect_request(self, parameters):
        """
        GET /inspect/<request-id>

        Returns http body of a generic requests with given id.
        """
        global history
        request_id = parameters[0]
        return history.request(request_id).http_body

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

    def __init__(self, http_method, path, http_body):
        self.id = None # set later by `GenericRequestsHistory`
        self.path = path
        self.http_method = http_method
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

# If any previous instance of this server is running - kill it
os.system('pkill -f run-server-mock.py')

history = GenericRequestsHistory()
httpd = HTTPServer(('localhost', 8000), HTTPMockServer)
httpd.serve_forever()
