# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
from src.test_file_parser import MonitorConfiguration, MonitorVariable, MONITOR_TYPE_LOGS, MONITOR_TYPE_APM, MONITOR_TYPE_RUM
from src.linter import Linter, linter_context


class MainTF:
    """
    Generates `main.tf` file.
    """
    def __init__(
            self,
            template_content: str,
            logs_monitor_template: 'MonitorTemplate',
            apm_monitor_template: 'MonitorTemplate',
            rum_monitor_template: 'MonitorTemplate'
    ):
        self.monitors: [MonitorConfiguration] = []
        self.template_content = template_content
        self.logs_monitor_template = logs_monitor_template
        self.apm_monitor_template = apm_monitor_template
        self.rum_monitor_template = rum_monitor_template

    @staticmethod
    def load_from_templates(
            main_template_path: str,
            logs_monitor_template_path: str,
            apm_monitor_template_path: str,
            rum_monitor_template_path: str
    ):
        with open(logs_monitor_template_path, 'r') as monitor_tf_src:
            logs_monitor_template = MonitorTemplate(template_content=monitor_tf_src.read())

        with open(apm_monitor_template_path, 'r') as monitor_tf_src:
            apm_monitor_template = MonitorTemplate(template_content=monitor_tf_src.read())

        with open(rum_monitor_template_path, 'r') as monitor_tf_src:
            rum_monitor_template = MonitorTemplate(template_content=monitor_tf_src.read())

        with open(main_template_path, 'r') as main_tf_src:
            return MainTF(
                template_content=main_tf_src.read(),
                logs_monitor_template=logs_monitor_template,
                apm_monitor_template=apm_monitor_template,
                rum_monitor_template=rum_monitor_template
            )

    def render(self, monitors: [MonitorConfiguration]) -> str:
        output = '# This file is auto-generated, do not edit it directly\n\n'
        output += f'{self.template_content}\n'
        output += '# Monitors:\n\n'
        for monitor in monitors:
            monitor_template: MonitorTemplate

            if monitor.type == MONITOR_TYPE_LOGS:
                monitor_template = self.logs_monitor_template
            elif monitor.type == MONITOR_TYPE_APM:
                monitor_template = self.apm_monitor_template
            else:
                assert monitor.type == MONITOR_TYPE_RUM, f'Unrecognized monitor type {monitor.type}'
                monitor_template = self.rum_monitor_template

            output += monitor_template.render(monitor=monitor)
            output += '\n'
        return output


class MonitorTemplate:
    """
    Renders `monitor-logs.tf.src` file by replacing variables with values read from `MonitorConfiguration`.
    If a given `$variable` is not defined in monitor configuration, then its default from template will be used.
    """
    def __init__(self, template_content: str):
        self.template_content = template_content

    def render(self, monitor: MonitorConfiguration) -> str:
        result = ''
        result += self.template_content
        result = MonitorTemplate.render_template_variables(template=result, monitor=monitor)
        result = MonitorTemplate.render_monitor_code(template=result, monitor=monitor)
        return result

    @staticmethod
    def render_template_variables(template: str, monitor: MonitorConfiguration) -> str:
        """
        Finds all variables ( ${{variable}} ) in the template and renders them using `monitor.variables`.
        If `monitor.variables` doesn't define the variable, its default value from the template is used.
        If variable doesn't define default value in the template and is not given in `monitor.variables` then
        linter error is emitted.
        """

        # e.g. variable definitions: ${name}, ${name_foo}, ${name1:-default value}
        variable_pattern = r"^.*\${{(?P<variable_name>[a-zA-Z0-9_]+)(?:\:-(?P<default_value>.+))?}}"
        variable_regex = re.compile(variable_pattern)

        rendered_lines: [str] = []
        rendered_user_variables: [MonitorVariable] = []

        with linter_context(code_reference=monitor.code_reference):
            # Find variables in template and render them using user variables defined in `MonitorConfiguration`:
            for line_no, line in enumerate(template.split('\n')):
                rendered_line = line

                if match := re.match(variable_regex, line):  # find variable in this line
                    template_variable_name = match.group('variable_name')
                    template_default_value = match.group('default_value')

                    # Find the `MonitorVariable` to substitute (or `None` if not defined):
                    user_variable = next((v for v in monitor.variables if v.name == f'${template_variable_name}'), None)

                    if user_variable:
                        rendered_user_variables.append(user_variable)

                    # Get the new value - prefer user value over template's default value
                    new_value = user_variable.value if user_variable else template_default_value

                    if new_value:
                        # Replace variable definition with `new_value`:
                        start_index = match.start('variable_name') - 3  # 3 indexes ('${{') before variable name match
                        end_index = match.end()  # right after match end
                        rendered_line = line[0:start_index] + new_value + line[end_index:len(line)]
                    else:
                        # Emit linter event:
                        Linter.shared.emit_error(
                            message=f'Variable ${template_variable_name} is required, but not defined for this monitor.'
                        )

                rendered_lines.append(rendered_line)

        # Check unused variables from `MonitorConfiguration`:
        for user_variable in monitor.variables:
            if user_variable not in rendered_user_variables:
                with linter_context(code_reference=user_variable.code_reference):
                    Linter.shared.emit_warning(
                        message=f'Variable {user_variable.name} is not defined in monitor template and won\'t be used.'
                    )

        return '\n'.join(rendered_lines)

    @staticmethod
    def render_monitor_code(template: str, monitor: MonitorConfiguration) -> str:
        """
        Replaces '## MONITOR_CODE ##' anchor in the template with the code associated to this monitor.
        """
        return template.replace("## MONITOR_CODE ##", monitor.code)
