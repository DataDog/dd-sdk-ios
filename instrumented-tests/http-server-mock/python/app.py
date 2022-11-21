#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import datetime
from hashlib import sha1
from typing import Optional
from dataclasses import dataclass
from flask import Flask, request, render_template, url_for, redirect
from schemas.schema import Schema
from schemas.raw import RAWSchema
from schemas.rum import RUMSchema
from schemas.session_replay import SRSchema


app = Flask(__name__)


@dataclass()
class GenericRequest:
    method: str
    path: str
    date: datetime
    content_type: str
    content_length: Optional[int]
    data: bytes
    headers: [str]  # ['field1: value1', 'field2: value2', ...]
    schemas: [Schema]

    def follow_url(self, schema: Schema):
        return url_for(
            'inspect_request',
            schema_name=schema.name,
            endpoint_hash=self.endpoint_hash(),
            request_hash=self.hash()
        )

    def hash(self) -> str:
        meta = f'{self.method} {self.path} {self.date}'.encode('utf-8')
        body = self.data
        return sha1(meta + body).hexdigest()

    def endpoint_hash(self) -> str:
        return sha1(f'{self.method} {self.path}'.encode('utf-8')).hexdigest()


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

    def avg_request_size(self):
        return self.bytes_received() / len(self.requests)

    def follow_url(self, schema: Schema):
        return url_for('inspect_endpoint', schema_name=schema.name, endpoint_hash=self.hash())

    def hash(self) -> str:
        return sha1(f'{self.method} {self.path}'.encode('utf-8')).hexdigest()

    def schema_with_name(self, name: str):
        return next((s for s in self.schemas if s.name == name), None)


def schemas_for_request(method: str, path: str) -> [Schema]:
    raw = RAWSchema()
    rum = RUMSchema()
    sr = SRSchema()

    schemas: [Schema] = []
    if raw.matches(method, path):
        schemas.append(raw)
    if rum.matches(method, path):
        schemas.append(rum)
    if sr.matches(method, path):
        schemas.append(sr)
    return schemas


endpoints: [GenericEndpoint] = []


@app.route('/<path:rest>', methods=['POST'])
def generic_post(rest):
    """
    POST /*

    Record generic (any) POST request sent to `/**/*`
    """
    global endpoints

    gr = GenericRequest(
        method=request.method,
        path=request.path,
        date=datetime.datetime.now(),
        content_type=request.content_type,
        content_length=request.content_length,
        data=request.data,
        headers=list(map(lambda h: f'{h[0]}: {h[1]}', request.headers)),
        schemas=schemas_for_request(request.method, request.path)
    )

    if existing := next((e for e in endpoints if e.hash() == gr.endpoint_hash()), None):
        existing.requests.append(gr)
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
        if schm := endp.schema_with_name(name=schema_name):
            if req := next((r for r in endp.requests if r.hash() == request_hash), None):
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
