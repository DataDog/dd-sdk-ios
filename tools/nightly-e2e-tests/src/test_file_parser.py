# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import re
from dataclasses import dataclass
from src.linter import Linter, CodeReference, linter_context


MONITOR_TYPE_LOGS = 'logs'
MONITOR_TYPE_APM = 'apm'


@dataclass
class MonitorVariable:
    name: str  # the $name of the variable to lookup in template file (the value includes "$" sign)
    value: str  # the new value of this value to render in template
    code_reference: CodeReference


@dataclass
class MonitorConfiguration:
    type: str  # a type of monitor (allowed values: 'apm' | 'logs'), used to select monitor template
    variables: [MonitorVariable]  # list of monitor variables
    code_reference: CodeReference


@dataclass
class TestMethod:
    method_name: str  # the name of this test method
    monitors: [MonitorConfiguration]  # monitors defined in method comment
    code_reference: CodeReference


@dataclass()
class TestFile:
    test_methods: [TestMethod]
    independent_monitors: [MonitorConfiguration]  # monitors defined in test file, but not attached to any `TestMethod`


def read_test_file(path: str):
    """
    Reads `TestFile` from the file at given `path`.
    :return: `TestFile` if the file contains any E2E tests definitions; `None` otherwise.
    """
    with open(path, 'r') as file:
        comment_regex = r'^[\t ]*(\/\/\/.*)'  # e.g. '    /// Sample comment'
        method_signature_regex = r'^[\s ]+func (test\w*)\(\)( throws)? {'  # e.g. '    func test_sample() throws {'

        test_methods: [TestMethod] = []
        independent_monitors: [MonitorConfiguration] = []
        comment_lines_buffer: [(int, str)] = []

        for line_no, line_text in enumerate(file.readlines()):
            if comment_match := re.match(comment_regex, line_text):  # matched comment `///`
                comment_lines_buffer.append((line_no, comment_match.groups()[0]))

            elif method_signature_match := re.match(method_signature_regex, line_text):  # matched test method signature
                method_name = method_signature_match.groups()[0]
                method = TestMethod(
                    method_name=method_name,
                    monitors=read_monitor_configuration(
                        comment_lines=comment_lines_buffer,
                        file_path=path
                    ),
                    code_reference=CodeReference(
                        file_path=path,
                        line_no=line_no + 1,
                        line_text=line_text
                    )
                )
                test_methods.append(method)
                comment_lines_buffer = []
            else:  # matched some other line in the file
                # Check if buffered comments define any additional monitors:
                additional_monitors = read_monitor_configuration(
                    comment_lines=comment_lines_buffer,
                    file_path=path
                )
                # Add to the list of independent monitors for this file:
                independent_monitors += additional_monitors

                comment_lines_buffer = []  # keep the comment lines buffer empty

        if test_methods or independent_monitors:
            return TestFile(
                test_methods=test_methods,
                independent_monitors=independent_monitors
            )
        else:
            return None


def read_monitor_configuration(comment_lines: [(int, str)], file_path: str) -> [MonitorConfiguration]:
    """
    Parses method comment lines and produces one or more `MonitorConfiguration` objects.

    The expected method comment has following structure:

    /// ... anything before
    /// ```logs
    /// $foo = bar1
    /// $fizz = buzz1
    /// ```
    /// ```apm
    /// $foo = bar2
    /// $fizz = buzz2
    /// ```
    /// ... anything after

    The "```" token indicates the beginning and end of the monitor definition. There can be more than one
    monitor defined in each comment.

    :return: returns list of `MonitorConfiguration` objects (0 to many) recognized in the method comment.
    """
    monitor_region_start_regex = r'^\/\/\/[\s ]+```([a-zA-Z0-9]+)[\s ]*$'  # e.g. '/// ```apm'
    monitor_region_end_regex = r'^\/\/\/[\s ]+```[\s ]*$'  # e.g. '/// ```'
    in_monitor_region = False  # if iterating through monitor variables
    monitor_type = None  # one of allowed monitor types (used later to pick the monitor template)
    allowed_monitor_types = [MONITOR_TYPE_LOGS, MONITOR_TYPE_APM]

    monitors: [MonitorConfiguration] = []
    variables_buffer: [MonitorVariable] = []

    for line_no, line_text in comment_lines:
        comment_line_code_reference = CodeReference(
            file_path=file_path,
            line_no=(line_no + 1),
            line_text=line_text
        )

        if match := re.match(monitor_region_start_regex, line_text):  # match the beginning of monitor definition
            monitor_type = match.group(1)

            if monitor_type in allowed_monitor_types:
                in_monitor_region = True
                variables_buffer = []
            else:
                with linter_context(code_reference=comment_line_code_reference):
                    Linter.shared.emit_error(f'Invalid monitor type, allowed values: {allowed_monitor_types}')

        elif re.match(monitor_region_end_regex, line_text):  # match the end of monitor definition
            if in_monitor_region:
                in_monitor_region = False

                monitor_code_reference = CodeReference(
                    file_path=file_path,
                    line_no=(line_no - len(variables_buffer)),  # first line of the monitor definition
                    line_text=line_text
                )
                monitor = MonitorConfiguration(
                    type=monitor_type,
                    variables=variables_buffer,
                    code_reference=monitor_code_reference
                )
                monitors.append(monitor)
            else:
                with linter_context(code_reference=comment_line_code_reference):
                    Linter.shared.emit_error(
                        f'Monitor end not matching any monitor start: ```({"|".join(allowed_monitor_types)}).'
                    )

        elif in_monitor_region:  # iterating through variables in monitor's definition region
            if variable := read_variable(
                    line_text=line_text,
                    comment_line_code_reference=comment_line_code_reference
            ):
                variables_buffer.append(variable)

    return monitors


def read_variable(line_text: str, comment_line_code_reference: CodeReference):
    """
    Parses single line of monitor definition.

    The expected variables line has following structure:

    /// $foo = bar1

    :return: the `MonitorVariable` object if recognized in this line; `None` otherwise.
    """
    variable_regex = r'^\/\/\/[\s ]+(\$.+)\s*=\s*(.+)$'
    variable_match = re.match(variable_regex, line_text)

    if variable_match:
        name = variable_match.groups()[0].rstrip()
        value = variable_match.groups()[1].rstrip()

        return MonitorVariable(
            name=name,
            value=value,
            code_reference=comment_line_code_reference
        )
    else:
        with linter_context(code_reference=comment_line_code_reference):
            Linter.shared.emit_error('Incorrect variable definitions - variable must follow `$name = value` syntax.')
            return None
