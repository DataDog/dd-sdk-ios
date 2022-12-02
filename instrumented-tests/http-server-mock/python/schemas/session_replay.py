#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import zlib
import json
from flask import Request
from schemas.schema import Schema
from templates.components.card import Card, CardTab
from validation.validation import validate_event


class SRSchema(Schema):
    name = 'session-replay'
    pretty_name = 'Session Replay'
    is_known = True
    endpoint_template = 'session-replay/endpoint.html'
    request_template = 'session-replay/request.html'

    # SR-specific
    segment_json: dict

    def __init__(self, request: Request):
        segment_file = request.files['segment'].read()
        segment_json_string = zlib.decompress(segment_file).decode('utf-8')
        self.segment_json = json.loads(segment_json_string)

    def body_views_card(self) -> Card:
        return Card(
            title='Segment',
            tabs=[
                self.segment_body_view_data(),
                self.segment_body_view_data(),
            ]
        )

    def segment_body_view_data(self) -> CardTab:
        vd = validate_event(
            event=self.segment_json,
            schema_path='/Users/maciek.grzybowski/Temp/rum-events-format/session-replay-mobile-format.json'
        )

        obj = {
            'pretty_json': json.dumps(self.segment_json, indent=4),
            'sr_validation': vd
        }

        return CardTab(title='Segment', template='session-replay/segment_view.html', object=obj)

    def records_body_view_data(self) -> CardTab:
        try:

        except:

    @staticmethod
    def matches(method: str, path: str):
        return method == 'POST' and path.startswith('/api/v2/replay')
