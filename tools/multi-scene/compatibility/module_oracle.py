"""Exact discovery, diagnostics and parameter ownership for one XCTest target."""
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlsplit, parse_qs
import module_inputs as inputs

require = inputs.require


def discovery(value, target, excluded, raw_reference=None, objc_identifiers=(), non_case_identifiers=()):
    require(value.get('errors') == [] and len(value.get('values', [])) == 1, 'incomplete discovery')
    row = value['values'][0]
    enabled = [v['identifier'] for v in row['enabledTests']]
    disabled = [v['identifier'] for v in row.get('disabledTests', [])]
    union = enabled + disabled; helper = target + '/DDXCSkippedTestCase'
    require(union and len(union) == len(set(union)), 'empty or duplicate discovery')
    require(len(non_case_identifiers) == len(set(non_case_identifiers)) and all(
            v.startswith(target + '/') and len(v.split('/')) == 2 and v != helper and v in union and
            not any(method.startswith(v + '/') for method in union) for v in non_case_identifiers),
            'unproven or executable non-case class')
    non_cases = set(non_case_identifiers) | {helper}
    methods = sorted(v for v in union if v not in non_cases)
    require(methods and all(v.startswith(target + '/') and len(v.split('/')) == 3 and
                           (v.endswith(')') or v in objc_identifiers) for v in methods),
            'unknown executable discovery shape')
    require(len(excluded) == len(set(excluded)) and set(excluded) <= set(methods), 'unknown or duplicate scope exclusion')
    if raw_reference is None:
        require(not disabled and not excluded, 'full discovery has disabled entries')
    else:
        require(sorted(union) == raw_reference and sorted(v for v in disabled if v not in non_cases) == sorted(excluded),
                'changed raw inventory or exclusion partition')
    selected = sorted(v for v in enabled if v not in non_cases)
    require(selected == sorted(set(methods) - set(excluded)), 'selected inventory differs')
    return dict(raw=sorted(union), identifiers=selected, excluded=sorted(excluded),
                non_cases=[dict(identifier=v, enabled=v in enabled) for v in sorted(non_cases) if v in union],
                raw_sha256=hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest())


def decode(tree, target, parameters):
    cases = {}; invocations = []; messages = []
    def diagnostics(node, identifier, argument=None):
        children = []
        for child in node.get('children', []):
            kind = child['nodeType']
            if kind in ['Skip Message', 'Failure Message', 'Runtime Warning']:
                expected_results = {'Skip Message': ['Skipped'], 'Failure Message': ['Failed'],
                                    'Runtime Warning': ['Passed', 'Failed', 'Skipped']}
                require(node.get('result') in expected_results[kind] and
                        set(child) in [{'nodeType', 'name'}, {'nodeType', 'name', 'sourceLocation'}] and
                        isinstance(child['name'], str) and child['name'].strip(),
                        'contradictory or unknown diagnostic')
                if 'sourceLocation' in child:
                    location = child['sourceLocation']
                    require(isinstance(location, dict) and set(location) == {'filePath', 'lineNumber'} and
                            isinstance(location['filePath'], str) and Path(location['filePath']).is_absolute() and
                            '..' not in Path(location['filePath']).parts and type(location['lineNumber']) is int and
                            location['lineNumber'] > 0, 'unknown diagnostic source location')
                messages.append(dict(identifier=identifier, argument=argument, kind=kind, message=child['name'], node=copy.deepcopy(child)))
            else: children.append(child)
        return children
    def walk(node, bundle=None):
        kind = node['nodeType']
        if kind == 'Unit test bundle':
            bundle = node['name']; require(bundle == target, 'foreign result target')
        if kind == 'Test Case':
            require(bundle == target, 'case without expected target')
            identifier = target + '/' + node['nodeIdentifier']
            require(identifier not in cases, 'duplicate case result')
            cases[identifier] = node['result']; children = diagnostics(node, identifier)
            if identifier in parameters:
                require(children and all(c['nodeType'] == 'Arguments' for c in children), 'missing/unknown parameter executions')
                require(sorted(c['name'] for c in children) == sorted(parameters[identifier]), 'missing or duplicate argument')
                hashes = []
                for child in children:
                    url = urlsplit(child['nodeIdentifierURL']); args = parse_qs(url.query)
                    require(url.scheme == 'test' and url.netloc == 'com.apple.xcode' and not url.fragment and
                            url.path.endswith('/' + identifier) and set(args) == {'args'} and len(args['args']) == 1 and
                            re.fullmatch('[a-f0-9]{64}', args['args'][0]), 'foreign/missing argument identity')
                    require(not diagnostics(child, identifier, child['nodeIdentifierURL']), 'unknown argument children')
                    hashes.append(args['args'][0]); invocations.append((identifier, args['args'][0], child['result']))
                require(len(hashes) == len(set(hashes)), 'duplicate parameter execution')
            else:
                require(not children, 'unexpected parameterized case')
                invocations.append((identifier, None, node['result']))
        else:
            require(kind in ['Test Plan', 'Unit test bundle', 'Test Suite'], 'unknown result node')
            for child in node.get('children', []): walk(child, bundle)
    for node in tree['testNodes']: walk(node)
    require(cases and invocations, 'empty result')
    return cases, invocations, messages


def assess(selected, tree, summary, target, parameters, reasons, expected_device, allowed_warnings=()):
    cases, invocations, messages = decode(tree, target, parameters)
    require(sorted(cases) == selected, 'executed inventory differs')
    expected = {key: len(parameters.get(key, [None])) for key in selected}
    require(dict(Counter(v[0] for v in invocations)) == expected, 'execution multiplicity differs')
    inputs.common.original.result_environment(summary, tree, expected_device, invocations)
    skipped = sorted(k for k, v in cases.items() if v == 'Skipped')
    require(skipped == sorted(reasons) and sorted(v[0] for v in invocations if v[2] == 'Skipped') == sorted(reasons), 'unexpected OS skip inventory')
    actual_reasons = {}
    for message in messages:
        if message['kind'] == 'Skip Message':
            require(message['argument'] is None and message['identifier'] not in actual_reasons, 'duplicate/parameter skip message')
            actual_reasons[message['identifier']] = message['message']
    require(actual_reasons == reasons, 'missing or unexpected skip reason')
    require(all(v in ['Passed', 'Skipped'] for v in cases.values()) and all(v[2] in ['Passed', 'Skipped'] for v in invocations), 'test assertion failure')
    require(summary['totalTestCount'] == len(cases) and summary['passedTests'] == len(cases) - len(skipped) and
            summary['skippedTests'] == len(skipped) and summary['failedTests'] == 0 and summary['expectedFailures'] == 0 and
            summary['result'] == 'Passed' and not summary.get('testFailures'), 'failed/unfinalized summary')
    warnings = summary.get('runtimeWarnings', [])
    require(isinstance(warnings, list) and (not warnings or
            Counter(json.dumps(v, sort_keys=True) for v in warnings) ==
            Counter(json.dumps(v, sort_keys=True) for v in allowed_warnings)), 'unclassified runtime warning')
    tree_warnings = []
    for message in messages:
        if message['kind'] == 'Runtime Warning':
            warning = dict(issueType=message['kind'], message=message['message'])
            if 'sourceLocation' in message['node']:
                warning['sourceURL'] = Path(message['node']['sourceLocation']['filePath']).as_uri()
            tree_warnings.append(warning)
    require(not tree_warnings or Counter(json.dumps(v, sort_keys=True) for v in tree_warnings) ==
            Counter(json.dumps(v, sort_keys=True) for v in warnings), 'runtime warning tree/summary mismatch')
    return dict(cases=len(cases), invocations=len(invocations), passed=len(cases) - len(skipped), skipped=skipped,
                parameter_multiplicities=expected, messages=messages, runtime_warnings=warnings)
