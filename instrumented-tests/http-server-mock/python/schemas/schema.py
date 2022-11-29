#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

class BodyView:
    """
    A way of viewing HTTP body, e.g. as RAW requetst, JSON string or any custom parser implemented in subclasses.
    """
    name: str  # displayed in the UI
    value: any  # ambiguous data - different subclass
    template: str  # a template that can understand this `DataView` and render it

    def __init__(self, name: str, value: any, template: str):
        self.name = name
        self.value = value
        self.template = template


class Schema:
    name: str  # displayed in the UI
    pretty_name: str
    is_known: bool
    endpoint_template: str
    request_template: str
    body_views: [BodyView]

    @staticmethod
    def matches(method: str, path: str):
        pass
