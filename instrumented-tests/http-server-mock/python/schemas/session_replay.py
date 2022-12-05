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


record_name_by_type = {
    4: 'meta',
    6: 'focus',
    7: 'view-end',
    8: 'visual-viewport',
    10: 'full snapshot',
    11: 'incremental snapshot',
}


class SRSchema(Schema):
    name = 'session-replay'
    pretty_name = 'Session Replay'
    is_known = True
    endpoint_template = 'session-replay/endpoint.html'
    request_template = 'session-replay/request.html'

    # SR-specific
    stats = [Stat]
    segment_json: dict

    def __init__(self, request: Request):
        segment_file = request.files['segment'].read()
        segment_json_string = zlib.decompress(segment_file).decode('utf-8')
        self.segment_json = json.loads(segment_json_string)
        self.stats = SRSchema.create_stats(records=self.segment_json['records'])

    def body_views_card(self) -> Card:
        return Card(
            title='View as:',
            tabs=[
                self.segment_data(),
                self.records_data(),
            ]
        )

    def segment_data(self) -> CardTab:
        vd = validate_event(
            event=self.segment_json,
            schema_path='/Users/maciek.grzybowski/Temp/rum-events-format/session-replay-mobile-format.json'
        )

        obj = {
            'pretty_json': json.dumps(self.segment_json, indent=4),
            'sr_validation': vd,
            'dd_segment': json.dumps(self.segment_json),  # for integration with JS console
        }

        return CardTab(title='Segment', template='session-replay/segment_view.html', object=obj)

    def records_data(self) -> CardTab:
        record_schema_path_by_type = {
            4: '/Users/maciek.grzybowski/Temp/rum-events-format/schemas/session-replay/common/meta-record-schema.json',
            6: '/Users/maciek.grzybowski/Temp/rum-events-format/schemas/session-replay/common/focus-record-schema.json',
            7: '/Users/maciek.grzybowski/Temp/rum-events-format/schemas/session-replay/common/view-end-record-schema.json',
            8: '/Users/maciek.grzybowski/Temp/rum-events-format/schemas/session-replay/common/visual-viewport-record-schema.json',
            10: '/Users/maciek.grzybowski/Temp/rum-events-format/schemas/session-replay/mobile/full-snapshot-record-schema.json',
            11: '/Users/maciek.grzybowski/Temp/rum-events-format/schemas/session-replay/mobile/incremental-snapshot-record-schema.json',
        }

        obj = {
            'records': [],
            'dd_records': json.dumps(self.segment_json['records']),  # for integration with JS console
        }

        for record in self.segment_json['records']:
            vd = validate_event(
                event=record,
                schema_path=record_schema_path_by_type[record['type']]
            )

            pills = [
                f"{record_name_by_type[record['type']]}"
            ]

            obj['records'].append({
                'pills': pills,
                'pretty_json': json.dumps(record, indent=4),
                'sr_validation': vd,
            })

        records_count = len(self.segment_json['records'])
        return CardTab(title=f'Records ({records_count})', template='session-replay/records_view.html', object=obj)

    @staticmethod
    def matches(method: str, path: str):
        return method == 'POST' and path.startswith('/api/v2/replay')

    @staticmethod
    def create_stats(records: dict) -> [Stat]:
        stats: [Stat] = []
        for r_type in record_name_by_type:
            count = 0

            for record in records:
                if record['type'] == r_type:
                    count += 1

            stat = Stat(title=f'"{record_name_by_type[r_type]}" records', value=f'{count}')
            stats.append(stat)

        return stats
