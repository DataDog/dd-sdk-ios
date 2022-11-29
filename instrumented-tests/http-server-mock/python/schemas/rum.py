#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import zlib
import json
from schemas.schema import Schema
from flask import Request
from schemas.schema import Schema, BodyView


class RUMEventsBodyView(BodyView):
    """
    Data model for rendering RUM payload as a list of separate RUM events.
    Each event is displayed with pretty JSON and additional header field (listing some of its metadata).
    """
    def __init__(self, value: [str]):
        super().__init__(
            name='RUM Pretty JSON',
            template='rum/rum_events_body_view.html',
            value=value  # an array of pretty-JSON strings
        )


class RUMSchema(Schema):
    name = 'rum'
    pretty_name = 'RUM'
    is_known = True
    endpoint_template = 'rum/endpoint.html'
    request_template = 'rum/request.html'
    body_views: [BodyView]

    def __init__(self, request: Request):
        if request.headers.get('Content-Encoding', None) == 'deflate':
            payload = zlib.decompress(request.get_data()).decode('utf-8')
        else:
            payload = request.get_data().decode('utf-8')

        events = map(lambda e: json.loads(e), payload.splitlines())
        pretty_json_strings = map(lambda e: json.dumps(e, indent=4), events)

        self.body_views = [RUMEventsBodyView(value=list(pretty_json_strings))]

    @staticmethod
    def matches(method: str, path: str):
        return method == 'POST' and path.startswith('/api/v2/rum')
