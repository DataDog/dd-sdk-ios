# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

from collections import Counter
from src.linter import Linter, linter_context
from src.test_file_parser import TestMethod, MonitorConfiguration, MonitorVariable


def lint_test_methods(test_methods: [TestMethod]):
    for test_method in test_methods:
        with linter_context(code_reference=test_method.code_reference):
            if test_method.monitors:
                for monitor in test_method.monitors:
                    with linter_context(code_reference=monitor.code_reference):
                        __monitor_id_has_method_name_prefix(monitor=monitor, test_method_name=test_method.method_name)
            elif not __is_excluded_from_lint(method=test_method):
                Linter.shared.emit_warning(f'Test method `{test_method.method_name}` defines no E2E monitors.')


def __is_excluded_from_lint(method: TestMethod):
    """
    Method can be excluded its signature is suffixed by `// E2E:wip`, e.g.:
    `    func test_logs_logger_DEBUG_log_with_error() { // E2E:wip`
    """
    return method.code_reference.line_text.endswith('// E2E:wip\n')


def __monitor_id_has_method_name_prefix(monitor: MonitorConfiguration, test_method_name: str):
    """
    $monitor_id must start with the test method name, e.g. method:
    `func test_logs_logger_DEBUG_log_with_error() {`
    must define monitor ID starting with `logs_logger_DEBUG_log_with_error`.
    """
    if monitor_id_variable := __find_monitor_variable(monitor=monitor, variable_name='$monitor_id'):
        expected_prefix = __remove_prefix(test_method_name.lower(), 'test_')
        if not monitor_id_variable.value.startswith(expected_prefix):
            with linter_context(code_reference=monitor_id_variable.code_reference):
                Linter.shared.emit_error(f'$monitor_id must start with method name ({expected_prefix})')


def lint_monitors(monitors: [MonitorConfiguration]):
    __have_unique_variable_values(monitors=monitors, variable_name='$monitor_id')
    __have_unique_variable_values(monitors=monitors, variable_name='$monitor_name')
    __have_unique_variable_values(monitors=monitors, variable_name='$monitor_query')


def __have_unique_variable_values(monitors: [MonitorConfiguration], variable_name: str):
    """
    Checks if $variable_name is unique among all `monitors`.
    """
    variables: [MonitorVariable] = []

    for monitor in monitors:
        if variable := __find_monitor_variable(monitor=monitor, variable_name=variable_name):
            variables.append(variable)

    values: [str] = list(map(lambda var: var.value, variables))

    for unique_value in set(values):
        occurrences = list(filter(lambda var: var.value == unique_value, variables))
        if len(occurrences) > 1:
            for occurrence in occurrences:
                with linter_context(code_reference=occurrence.code_reference):
                    Linter.shared.emit_error(f'{variable_name} must be unique - {occurrence.value} is already used.')


def __find_monitor_variable(monitor: MonitorConfiguration, variable_name: str):
    return next((v for v in monitor.variables if v.name == variable_name), None)


def __remove_prefix(s, prefix):
    return s[len(prefix):] if s.startswith(prefix) else s