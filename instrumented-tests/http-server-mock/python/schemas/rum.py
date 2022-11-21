#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

from schemas.schema import Schema


class RUMSchema(Schema):
    name = 'rum'
    pretty_name = 'RUM'
    is_known = True
    endpoint_template = 'rum/endpoint.html'
    request_template = 'rum/request.html'

    def matches(self, method: str, path: str):
        return method == 'POST' and path.startswith('/rum/')
