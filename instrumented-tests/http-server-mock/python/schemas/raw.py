#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import zlib
from typing import Optional
from flask import Request
from schemas.schema import Schema
from templates.components.card import Card, CardTab


class RAWSchema(Schema):
    name = 'raw'
    pretty_name = 'Raw'
    is_known = False
    endpoint_template = 'raw/endpoint.html'
    request_template = 'raw/request.html'

    # RAW-specific:
    data_as_text: str
    decompressed_data: Optional[str]  # `None` if data was not compressed

    def __init__(self, request: Request):
        self.data_as_text = request.get_data(as_text=True)
        if request.headers.get('Content-Encoding', None) == 'deflate':
            self.decompressed_data = zlib.decompress(request.get_data()).decode('utf-8')
        else:
            self.decompressed_data = None

    def body_views_card(self) -> Card:
        tabs = []

        if self.decompressed_data:
            tabs.append(
                CardTab(title='RAW (decompressed)', template='raw/text_body_view.html', object=self.decompressed_data)
            )

        tabs.append(CardTab(title='RAW (original)', template='raw/text_body_view.html', object=self.data_as_text))

        return Card(title='Body', tabs=tabs)

    @staticmethod
    def matches(method: str, path: str):
        return True
