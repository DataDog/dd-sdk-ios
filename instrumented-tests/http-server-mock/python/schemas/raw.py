#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

from schemas.schema import Schema


class RAWSchema(Schema):
    name = 'raw'
    pretty_name = 'Raw'
    is_known = False
    endpoint_template = 'raw/endpoint.html'
    request_template = 'raw/request.html'

    def matches(self, method: str, path: str):
        return True
