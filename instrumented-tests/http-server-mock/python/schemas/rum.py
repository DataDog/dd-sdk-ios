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
from templates.components.stat import Stat
from validation.validation import validate_event


class RUMSchema(Schema):
    name = 'rum'
    pretty_name = 'RUM'
    is_known = True
    endpoint_template = 'rum/endpoint.html'
    request_template = 'rum/request.html'

    # RUM-specific:
    stats = [Stat]
    event_jsons: [dict]

    def __init__(self, request: Request):
        if request.headers.get('Content-Encoding', None) == 'deflate':
            payload = zlib.decompress(request.get_data()).decode('utf-8')
        else:
            payload = request.get_data().decode('utf-8')

        self.event_jsons = list(map(lambda e: json.loads(e), payload.splitlines()))
        self.stats = [
            Stat(title='number of events', value=f'{len(self.event_jsons)}')
        ]

    def body_views_card(self) -> Card:
        return Card(
            title='View as:',
            tabs=[
                self.events_data(),
                self.events_metadata(),
            ]
        )

    def events_data(self) -> CardTab:
        obj = {
            'events': [],
            'dd_events': json.dumps(self.event_jsons),
        }

        for event in self.event_jsons:
            vd = validate_event(
                event=event,
                schema_path='/Users/maciek.grzybowski/Temp/rum-events-format/rum-events-format.json'
            )

            pills = []  # pills rendered below validation result
            if vd.all_ok:
                pills = [
                    f"{event['type']}",
                    f"view.id: {event['view']['id']}",
                    f"session.id: {event['session']['id']}",
                    f"application.id: {event['application']['id']}"
                ]

            obj['events'].append({
                'pills': pills,
                'pretty_json': json.dumps(event, indent=4),
                'rum_validation': vd
            })

        return CardTab(title=f'Events ({len(self.event_jsons)})', template='rum/events_view.html', object=obj)

    def events_metadata(self) -> CardTab:
        data = self.events_data()
        data.title = 'Metadata'
        data.template = 'rum/events_metadata.html'
        return data

    @staticmethod
    def matches(method: str, path: str):
        return method == 'POST' and path.startswith('/api/v2/rum')
