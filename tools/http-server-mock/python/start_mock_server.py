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

    GET /cache-test/<resource_id>
    - Endpoint simulating a cacheable resource with ETag-based revalidation
      (`Cache-Control: no-cache` + `ETag`, i.e. cacheable but must always revalidate).
      Responds `200` with a small JSON body on the first request for a given
      `resource_id`, then `304` (no body) on subsequent requests carrying a
      matching `If-None-Match` header.

    GET /cache-test-stale/<resource_id>
    - Endpoint simulating a resource that never revalidates as fresh: it always
      responds `200` with a different body/ETag, regardless of `If-None-Match`.
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
        cache_test_match = re.search(r"/cache-test/([^/?]+)", self.path)
        if cache_test_match is not None:
            self.__GET_cache_test(cache_test_match.group(1))
            return

        cache_test_stale_match = re.search(r"/cache-test-stale/([^/?]+)", self.path)
        if cache_test_stale_match is not None:
            self.__GET_cache_test_stale(cache_test_stale_match.group(1))
            return

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

    def __GET_cache_test(self, resource_id):
        """
        GET /cache-test/<resource_id>

        Simulates a cacheable resource with ETag-based revalidation:
        - 1st request for `resource_id` -> `200` with a JSON body and an `ETag`.
        - subsequent requests sending `If-None-Match` matching that `ETag` -> `304`, no body.

        Each request is also recorded into `history`, with the response status it was
        actually served, so tests can prove which branch (`200` or `304`) was taken.
        """
        global cache_test_registry, history
        etag = cache_test_registry.etag(resource_id)
        if_none_match = self.headers.get('If-None-Match')
        request_headers = '\n'.join([ f'{field}: {self.headers[field]}' for field in self.headers ]).encode('utf-8')

        if if_none_match is not None and if_none_match == etag:
            history.add_request(GenericRequest("GET", self.path, request_headers, json.dumps({"response_status": 304}).encode('utf-8')))
            self.send_response(304) # not modified
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('ETag', etag)
            self.end_headers()
            return

        history.add_request(GenericRequest("GET", self.path, request_headers, json.dumps({"response_status": 200}).encode('utf-8')))
        body = json.dumps({"id": resource_id}).encode('utf-8')
        self.send_response(200) # ok
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('ETag', etag)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def __GET_cache_test_stale(self, resource_id):
        """
        GET /cache-test-stale/<resource_id>

        Simulates a resource that always misses the cache: every request gets a fresh
        `200` response with a different body and `ETag`, regardless of `If-None-Match`.
        """
        global cache_test_registry
        etag = cache_test_registry.next_stale_etag(resource_id)

        body = json.dumps({"id": resource_id, "etag": etag}).encode('utf-8')
        self.send_response(200) # ok
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('ETag', etag)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

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

class CacheTestRegistry:
    """
    Stores per-`resource_id` state for the `/cache-test/*` and `/cache-test-stale/*` endpoints:
    - a fixed `ETag` used for revalidation on `/cache-test/<resource_id>`,
    - a request counter used to produce an always-different `ETag` on `/cache-test-stale/<resource_id>`.
    """

    __etags = {}
    __stale_counters = {}

    def etag(self, resource_id):
        if resource_id not in self.__etags:
            self.__etags[resource_id] = f'"{resource_id}-etag"'
        return self.__etags[resource_id]

    def next_stale_etag(self, resource_id):
        count = self.__stale_counters.get(resource_id, 0) + 1
        self.__stale_counters[resource_id] = count
        return f'"{resource_id}-stale-etag-{count}"'

# If any previous instance of this server is running - kill it
os.system('pkill -f start_mock_server.py')
time.sleep(1) # wait a bit until socket is eventually released

# Configure the server
history = GenericRequestsHistory()
cache_test_registry = CacheTestRegistry()
address = get_localhost() if prefer_localhost_flag is True else get_best_server_address()
httpd = HTTPServer((address.ip, address.port), HTTPMockServer)

print("Starting server on http://{ip}:{port}".format( ip = address.ip, port = address.port))
httpd.serve_forever()
