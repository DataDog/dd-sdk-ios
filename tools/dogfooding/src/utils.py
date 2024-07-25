#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

def print_err(message):
    print(f"\033[91m{message}\033[0m")

def print_warn(message):
    print(f"\033[93m{message}\033[0m")

def print_succ(message):
    print(f"\033[92m{message}\033[0m")

def print_info(message):
    print(f"\033[94m{message}\033[0m")
