# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
from src.semver import Version
from dataclasses import dataclass


@dataclass()
class UnitTestsWorkflow:
    simulator_device_name: str
    simulator_os_name: str
    simulator_os_version: Version

    def get_invocation_yml(self):
        return f'- _run_unit_tests_on_{self.simulator_os_version}'

    def get_definition_yml(self):
        return f'''
_run_unit_tests_on_{self.simulator_os_version}:
  envs:
  - SIMULATOR_DEVICE: '{self.simulator_device_name}'
  - SIMULATOR_OS_VERSION: '{self.simulator_os_version}'
  after_run:
  - _run_unit_tests
'''[1:-1]

    def get_slack_report_row(self):
        return f'- tested on {self.simulator_os_name} {self.simulator_os_version} - {self.simulator_device_name}'


class BitriseYML:
    def __init__(self, template_content: str):
        self.template_content = template_content
        self.unit_test_workflows: [UnitTestsWorkflow] = []
        self.issues = []
        self.host_os_version = ''

    @staticmethod
    def load_from_template(path: str):
        with open(path, 'r') as file:
            return BitriseYML(template_content=file.read())

    def add_unit_tests_workflow(self, workflow: UnitTestsWorkflow):
        self.unit_test_workflows.append(workflow)

    def add_issue(self, issue: str):
        self.issues.append(f'- {issue}')

    def set_host_os_version(self, version_string: str):
        self.host_os_version = version_string

    def write(self, path: str):
        with open(path, 'w') as file:
            file.write(self.__rendered_template())

    def __rendered_template(self):
        workflow_invocations = [f'{utw.get_invocation_yml()}\n' for utw in self.unit_test_workflows]
        workflow_definitions = [f'{utw.get_definition_yml()}\n\n' for utw in self.unit_test_workflows]
        slack_simulators_list = [f'{utw.get_slack_report_row()}\n' for utw in self.unit_test_workflows]
        slack_issues_list = ['- none'] if len(self.issues) == 0 else [f'{issue}\n' for issue in self.issues]

        if len(slack_simulators_list) == 0:
            slack_simulators_list = ['- ⚠️ Tests were not run on any device\n']

        template = self.template_content

        template = self.__render(
            template=template,
            variable='### <WORKFLOW INVOCATIONS> ###',
            value=''.join(workflow_invocations).rstrip()
        )
        template = self.__render(
            template=template,
            variable='### <WORKFLOW DEFINITIONS> ###',
            value=''.join(workflow_definitions).rstrip()
        )
        template = self.__render(
            template=template,
            variable='### <SLACK SIMULATORS LIST> ###',
            value=''.join(slack_simulators_list).rstrip()
        )
        template = self.__render(
            template=template,
            variable='### <SLACK ISSUES LIST> ###',
            value=''.join(slack_issues_list).rstrip()
        )

        template = template.replace('## <MACOS VERSION> ##', self.host_os_version)

        return template

    @staticmethod
    def __render(template: str, variable: str, value: str):
        """
        Replaces given `variable` with `value` in `template` string
        by preserving the `variable` indentation.
        """
        pattern = re.compile(r'^([ \t]*)' + re.escape(variable) + r'$', re.MULTILINE)

        while True:
            next_match = re.search(pattern, template)
            if next_match:
                indentation = next_match.groups()[0]
                indented_value = '\n'.join([f'{indentation}{line}' for line in value.split(sep='\n')])
                template = template[0:next_match.start()] + indented_value + template[next_match.end():len(template)]
            else:
                break

        return template
