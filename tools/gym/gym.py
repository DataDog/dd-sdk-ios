#!/usr/bin/env python

# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.

# GYM: Generate Your Model.  See -h output for instructions

import os
import json
import argparse
import copy
import re
from jinja2 import Environment, FileSystemLoader  

class Resolver:
    """
    Resolves a JSON Schema from its root definition.
    Any '$ref' found will be resolved from the file
    system and added to the list of subschemas.
    """

    def __init__(self, path: str):
        self.location = os.path.dirname(path)
        self.root: dict = json.load(open(path))

    def resolve(self, subschemas: dict[str, dict]):
        return self.__resolve_schema(self.root, subschemas)

    def __resolve_ref(self, ref: str, subschemas: dict[str, dict]):
        path = os.path.join(self.location, ref)

        # stop if already resolved -
        # prevent infinite recursion with reference loop
        for subschema in subschemas:
            if subschema in path: return subschemas[subschema]

        resolver = Resolver(path)
        # referred schema should have an '$id' -
        # default to 'ref' just in case
        id = resolver.root.get('$id', ref)
        subschemas[id] = resolver.root
        return resolver.resolve(subschemas)

    def __resolve_schema(self, schema: dict, subschemas):
        if '$ref' in schema:
            return self.__resolve_ref(schema['$ref'], subschemas)

        if '$id' not in schema:
            schema['$parent'] = self.root['$id']

        if 'oneOf' in schema:
            schema['oneOf'] = list(map(lambda s: self.__resolve_schema(s, subschemas), schema['oneOf']))

        if 'anyOf' in schema:
            schema['anyOf'] = list(map(lambda s: self.__resolve_schema(s, subschemas), schema['anyOf']))

        if 'allOf' in schema:
            schema['allOf'] = list(map(lambda s: self.__resolve_schema(s, subschemas), schema['allOf']))

        if 'items' in schema:
            schema['items'] = self.__resolve_schema(schema['items'], subschemas)

        if 'properties' in schema:
            schema['properties'] = map_values(lambda s: self.__resolve_schema(s, subschemas), schema['properties'])

        # all properties from `allOf` will be merged into 'schema'
        self.__merge_allof(schema)
        return schema

    def __merge_allof(self, schema: dict):
        if 'allOf' not in schema: return
        for s in schema['allOf']: self.__merge_properties(from_=s, to_=schema)

    def __merge_properties(self, from_: dict, to_: dict):
        required = to_.get('required', [])
        required.extend(from_.get('required', []))
        if required: to_['required'] = remove_dup(required)

        properties = copy.deepcopy(to_.get('properties', {}))
        deepmerge(properties, from_.get('properties', {}))
        if properties: to_['properties'] = properties
            

class Renderer:
    """
    Renders a resolved JSON Schemas using Jinja templates.

    The root schema and subschemas will be provided as
    context to jinja. The generated files are written to
    the output directory using schema titles (or $id) and
    the given extension.
    """

    def __init__(self, template: str, output: str, ext: str):
        loader = FileSystemLoader(os.path.dirname(template))

        env = Environment(
            loader=loader,
            trim_blocks=True,
            lstrip_blocks=True,
        )

        env.filters['camelcase'] = camelcase
        env.filters['capitalcase'] = capitalcase
        env.filters['constcase'] = constcase
        env.filters['pascalcase'] = pascalcase
        env.filters['snakecase'] = snakecase
        env.filters['trimcase'] = trimcase
        env.filters['alphanumcase'] = alphanumcase
        
        self.template = env.get_template(os.path.basename(template))
        self.output = output
        self.ext = ext

    def render(self, schema: dict, subschemas: dict[str, dict]):
        if not os.path.exists(self.output): os.makedirs(self.output)

        self.__render(schema, subschemas)
        for subschema in subschemas.values():
            self.__render(subschema, subschemas)

    def __render(self, schema: dict, subschemas: dict[str, dict]):
        rendering = self.template.render(schema = schema, subschemas = subschemas)

        if 'title' not in schema and '$id' not in schema:
            raise 'Schema must define a "title" or "$id"'

        filename = schema.get('title', schema['$id'])
        path = os.path.join(self.output, filename + "." + self.ext)
        with open(path, 'w') as f: f.write(rendering)


def map_values(fn, obj: dict):
    return dict((k, fn(v)) for k, v in obj.items())

def remove_dup(l: list):
    return list(dict.fromkeys(l))

def deepmerge(obj: dict, merge_obj: dict):
    """ Recursive dict merge. Inspired by :meth:``dict.update()``, instead of
    updating only top-level keys, deepmerge recurses down into dicts nested
    to an arbitrary depth, updating keys. The ``merge_obj`` is merged into
    ``obj``.
    :param obj: dict onto which the merge is executed
    :param merge_obj: dict merged into obj
    :return: None
    """
    for k in merge_obj:
        if (k in obj and isinstance(obj[k], dict) and isinstance(merge_obj[k], dict)):
            deepmerge(obj[k], merge_obj[k])
        else: obj[k] = merge_obj[k]

# From: https://github.com/okunishinishi/python-stringcase

def camelcase(string):
    string = re.sub(r"^[\-_\.]", '', string)
    if not string: return string
    return lowercase(string[0]) + re.sub(r"[\-_\.\s]([a-z])", lambda matched: capitalcase(matched.group(1)), string[1:])

def capitalcase(string):
    string = str(string)
    if not string: return string
    return uppercase(string[0]) + string[1:]

def pascalcase(string):
    return capitalcase(camelcase(string))

def snakecase(string):
    string = re.sub(r"[\-\.\s]", '_', str(string))
    if not string:
        return string
    return lowercase(string[0]) + re.sub(r"[A-Z]", lambda matched: '_' + lowercase(matched.group(0)), string[1:])

def trimcase(string):
    return str(string).strip()

def alphanumcase(string):
    return ''.join(filter(str.isalnum, str(string)))

def constcase(string):
    return uppercase(snakecase(string))

def uppercase(string):
    return str(string).upper()

def lowercase(string):
    return str(string).lower()


def main():
    """Generate Your Model."""

    parser = argparse.ArgumentParser()
    parser.add_argument('--input', '-i', help='Path to JSON Schema.')
    parser.add_argument('--template', '-t', help='Path to template.')
    parser.add_argument('--output', '-o', default= './', help='Output directory.')
    parser.add_argument('--ext', help='Generated soucre file extension.')
    args = parser.parse_args()

    resolver = Resolver(args.input)
    renderer = Renderer(args.template, args.output, args.ext)

    subschemas = {}
    schema = resolver.resolve(subschemas)

    renderer.render(schema, subschemas) 

if __name__ == '__main__': 
    main()
 