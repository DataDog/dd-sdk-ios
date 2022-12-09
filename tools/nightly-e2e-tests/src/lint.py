# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
from src.linter import Linter, linter_context
from src.test_file_parser import TestMethod, MonitorConfiguration, MonitorVariable


def lint_test_methods(test_methods: [TestMethod]):
    for test_method in test_methods:
        with linter_context(code_reference=test_method.code_reference):
            if test_method.monitors:
                for monitor in test_method.monitors:
                    with linter_context(code_reference=monitor.code_reference):
                        # `tested_method_name` is computed from test method name, e.g.:
                        # for `test_logs_logger_DEBUG_log_with_error` it is `logs_logger_debug_log_with_error`
                        tested_method_name = __remove_prefix(test_method.method_name.lower(), 'test_')
                        __monitor_id_has_method_name_prefix(
                            monitor=monitor, tested_method_name=tested_method_name
                        )
                        __method_name_occurs_in_monitor_name(
                            monitor=monitor, tested_method_name=tested_method_name
                        )
            elif not __is_excluded_from_lint(method=test_method):
                Linter.shared.emit_warning(f'Test method `{test_method.method_name}` defines no E2E monitors.')


def __is_excluded_from_lint(method: TestMethod):
    """
    Method can be excluded its signature is suffixed by `// E2E:wip`, e.g.:
    `    func test_logs_logger_DEBUG_log_with_error() { // E2E:wip`
    """
    return method.code_reference.line_text.endswith('// E2E:wip\n')


def __monitor_id_has_method_name_prefix(monitor: MonitorConfiguration, tested_method_name: str):
    """
    $monitor_id must start with the test method name, e.g. method:
    `func test_logs_logger_DEBUG_log_with_error() {`
    must define monitor ID starting with `logs_logger_debug_log_with_error`.
    """
    if monitor_id_variable := __find_monitor_variable(monitor=monitor, variable_name='$monitor_id'):
        if not monitor_id_variable.value.startswith(tested_method_name):
            with linter_context(code_reference=monitor_id_variable.code_reference):
                Linter.shared.emit_error(f'$monitor_id must start with method name ({tested_method_name})')


def __method_name_occurs_in_monitor_name(monitor: MonitorConfiguration, tested_method_name: str):
    """
    The test method name must occur in $monitor_name.
    """
    regex = re.compile(rf"^.*(\W+){tested_method_name}(\W+).*$")

    if monitor_name_variable := __find_monitor_variable(monitor=monitor, variable_name='$monitor_name'):
        if not re.match(regex, monitor_name_variable.value):
            with linter_context(code_reference=monitor_name_variable.code_reference):
                Linter.shared.emit_warning(f'$monitor_name must include method name ({tested_method_name})')


def lint_monitors(monitors: [MonitorConfiguration]):
    __have_unique_variable_values(monitors=monitors, variable_name='$monitor_id')
    __have_unique_variable_values(monitors=monitors, variable_name='$monitor_name')
    __have_unique_variable_values(monitors=monitors, variable_name='$monitor_query')
    __feature_variable_has_allowed_value(monitors=monitors)


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


def __feature_variable_has_allowed_value(monitors: [MonitorConfiguration]):
    """
    Checks if `$feature` variable is one of allowed values. Skips if this variable is not defined.
    """
    allowed_values = ['core', 'logs', 'trace', 'rum', 'crash']
    for monitor in monitors:
        if variable := __find_monitor_variable(monitor=monitor, variable_name='$feature'):
            if variable.value not in allowed_values:
                with linter_context(code_reference=variable.code_reference):
                    Linter.shared.emit_error(f'$feature must be one of: {allowed_values}')


def __find_monitor_variable(monitor: MonitorConfiguration, variable_name: str) -> MonitorVariable:
    return next((v for v in monitor.variables if v.name == variable_name), None)


def __remove_prefix(s, prefix):
    return s[len(prefix):] if s.startswith(prefix) else s