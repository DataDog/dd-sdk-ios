#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

from uuid import uuid4


class CardTab:
    title: str
    template: str
    object: any  # ambiguous object, specific to `template`

    def __init__(self, title: str, template: str, object: any):
        self.title = title
        self.template = template
        self.object = object


class Card:
    id: str
    title: str
    tabs: [CardTab]

    def __init__(self, title: str, tabs: [CardTab]):
        self.id = str(uuid4())
        self.title = title
        self.tabs = tabs
