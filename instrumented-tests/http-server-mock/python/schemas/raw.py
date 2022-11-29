#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import zlib
from flask import Request
from schemas.schema import Schema, BodyView


class RAWTextBodyView(BodyView):
    def __init__(self, value: str):
        print(f'Creating RAWTextBodyView for {value}')
        super().__init__(
            name='RAW text',
            template='raw/text_body_view.html',
            value=value  # a text
        )


class RAWUncompressedTextBodyView(BodyView):
    def __init__(self, value: str):
        print(f'Creating RAWUncompressedTextBodyView for {value}')
        super().__init__(
            name='RAW text (uncompressed)',
            template='raw/text_body_view.html',
            value=value  # a text
        )


class RAWSchema(Schema):
    name = 'raw'
    pretty_name = 'Raw'
    is_known = False
    endpoint_template = 'raw/endpoint.html'
    request_template = 'raw/request.html'
    body_views: [BodyView]

    def __init__(self, request: Request):
        views: [BodyView] = [RAWTextBodyView(value=request.get_data(as_text=True))]

        if request.headers.get('Content-Encoding', None) == 'deflate':
            views.append(RAWUncompressedTextBodyView(value=zlib.decompress(request.get_data()).decode('utf-8')))

        self.body_views = views

    @staticmethod
    def matches(method: str, path: str):
        return True
