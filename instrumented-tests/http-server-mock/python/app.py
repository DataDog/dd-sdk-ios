#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import os
import json

import datetime
from hashlib import sha1
from typing import Optional
from dataclasses import dataclass
from flask import Flask, request, Request, render_template, url_for, redirect
from schemas.schema import Schema
from schemas.raw import RAWSchema
from schemas.rum import RUMSchema
from schemas.session_replay import SRSchema
from templates.components.card import Card, CardTab


app = Flask(__name__)


@dataclass()
class GenericRequest:
    method: str
    path: str
    query_string: str
    date: datetime
    content_type: str
    content_length: Optional[int]
    data_as_text: str
    schemas: [Schema]

    def __init__(self, r: Request):
        self.method = r.method
        self.path = r.path
        self.query_string = f'?{request.query_string.decode("utf-8")}' if request.query_string else ''
        self.date = datetime.datetime.now()
        self.content_type = r.content_type
        self.content_length = r.content_length
        self.data_as_text = r.get_data(as_text=True)
        self.schemas = schemas_for_request(request)

    def follow_url(self, schema: Schema):
        return url_for(
            'inspect_request',
            schema_name=schema.name,
            endpoint_hash=self.endpoint_hash(),
            request_hash=self.hash()
        )

    def hash(self) -> str:
        meta = f'{self.method} {self.path} {self.date}'.encode('utf-8')
        body = self.data_as_text.encode('utf-8')
        return sha1(meta + body).hexdigest()

    def endpoint_hash(self) -> str:
        return sha1(f'{self.method} {self.path}'.encode('utf-8')).hexdigest()

    def schema_with_name(self, name: str):
        return next((s for s in self.schemas if s.name == name), None)


@dataclass()
class GenericEndpoint:
    method: str
    path: str
    requests: [GenericRequest]  # all requests sent to this endpoint
    schemas: [Schema]

    def name(self):
        return f'{self.method} {self.path}'

    def requests_count(self):
        return len(self.requests)

    def bytes_received(self):
        return sum(map(lambda r: r.content_length, self.requests))

    def follow_url(self, schema: Schema):
        return url_for('inspect_endpoint', schema_name=schema.name, endpoint_hash=self.hash())

    def hash(self) -> str:
        return sha1(f'{self.method} {self.path}'.encode('utf-8')).hexdigest()

    def schema_with_name(self, name: str):
        return next((s for s in self.schemas if s.name == name), None)


def schemas_for_request(r: Request) -> [Schema]:
    schemas: [Schema] = []

    if RAWSchema.matches(r.method, r.path):
        schemas.append(RAWSchema(request=r))

    if RUMSchema.matches(r.method, r.path):
        schemas.append(RUMSchema(request=r))

    if SRSchema.matches(r.method, r.path):
        schemas.append(SRSchema(request=r))

    return schemas


endpoints: [GenericEndpoint] = []


def write_to_file(endpoint: GenericEndpoint):
    no = len(endpoint.requests)
    if 'rum' in endpoint.path:
        pass
        with open(f'fixtures/rum/{no}', 'wb') as f:
            f.write(request.get_data())
    elif 'replay' in endpoint.path:
        with open(f'fixtures/replay/{no}', 'wb') as f:
            f.write(request.get_data())


@app.route('/<path:rest>', methods=['POST'])
def generic_post(rest):
    """
    POST /*

    Record generic (any) POST request sent to `/**/*`
    """
    global endpoints

    gr = GenericRequest(r=request)

    if existing := next((e for e in endpoints if e.hash() == gr.endpoint_hash()), None):
        existing.requests.append(gr)
        # write_to_file(endpoint=existing)
        return f'OK - request recorded to known endpoint\n'
    else:
        endpoints.append(
            GenericEndpoint(
                method=gr.method,
                path=gr.path,
                requests=[gr],
                schemas=gr.schemas
            )
        )
        # write_to_file(endpoint=endpoints[len(endpoints)-1])
        return f'OK - request recorded to new endpoint\n'


@app.route('/inspect/')
def inspect():
    """
    GET /inspect

    Browse recorded requests.
    """
    global endpoints
    return render_template('endpoints.html', title='Endpoints', endpoints=endpoints)


@app.route('/inspect/<schema_name>/<endpoint_hash>')
def inspect_endpoint(schema_name, endpoint_hash):
    global endpoints

    if endp := next((e for e in endpoints if e.hash() == endpoint_hash), None):
        if schm := endp.schema_with_name(name=schema_name):
            return render_template(
                'endpoint.html',
                back_url=url_for('inspect'),
                endpoint=endp,
                selected_schema=schm
            )
        else:
            print(f'⚠️ Endpoint has no schema named {schema_name}')
            return redirect(url_for('inspect'))
    else:
        print(f'⚠️ Could not find endpoint with hash {endpoint_hash}')
        return redirect(url_for('inspect'))


@app.route('/inspect/<schema_name>/<endpoint_hash>/<request_hash>')
def inspect_request(schema_name, endpoint_hash, request_hash):
    global endpoints

    if endp := next((e for e in endpoints if e.hash() == endpoint_hash), None):
        if req := next((r for r in endp.requests if r.hash() == request_hash), None):
            if schm := req.schema_with_name(name=schema_name):
                return render_template(
                    'request.html',
                    back_url=url_for('inspect'),
                    endpoint=endp,
                    request=req,
                    selected_schema=schm
                )
            else:
                print(f'⚠️ Could not find request with hash {request_hash}')
                return redirect(url_for('inspect'))
        else:
            print(f'⚠️ Endpoint has no schema named {schema_name}')
            return redirect(url_for('inspect'))
    else:
        print(f'⚠️ Could not find endpoint with hash {endpoint_hash}')
        return redirect(url_for('inspect'))


if __name__ == '__main__':
    app.run(debug=True)
    # app.run()
