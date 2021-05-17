# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

from src.semver import Version
from dataclasses import dataclass


@dataclass()
class UnitTestsWorkflow:
    simulator_device_name: str
    simulator_os_name: str
    simulator_os_version: Version

    def get_invocation_yml(self):
        return f'    - _run_unit_tests_on_{self.simulator_os_version}'

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
        return f'            - tested on {self.simulator_os_name} {self.simulator_os_version} - {self.simulator_device_name}'


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
        self.issues.append(f'            - {issue}')

    def set_host_os_version(self, version_string: str):
        self.host_os_version = version_string

    def write(self, path: str):
        with open(path, 'w') as file:
            file.write(self.__rendered_template())

    def __rendered_template(self):
        workflow_invocations = list(map(lambda utw: utw.get_invocation_yml() + '\n', self.unit_test_workflows))
        workflow_definitions = list(map(lambda utw: utw.get_definition_yml() + '\n\n', self.unit_test_workflows))
        slack_simulators_list = list(map(lambda utw: utw.get_slack_report_row() + '\n', self.unit_test_workflows))
        slack_issues_list = ['            - none'] if len(self.issues) == 0 else self.issues

        if len(slack_simulators_list) == 0:
            slack_simulators_list = ['            - ⚠️ Tests were not run on any device\n']

        template = self.template_content
        template = template.replace('### <WORKFLOW INVOCATIONS> ###', ''.join(workflow_invocations)[:-1])
        template = template.replace('### <WORKFLOW DEFINITIONS> ###', ''.join(workflow_definitions)[:-2])
        template = template.replace('### <SLACK SIMULATORS LIST> ###', ''.join(slack_simulators_list)[:-1])
        template = template.replace('### <SLACK ISSUES LIST> ###', '\n'.join(slack_issues_list))
        template = template.replace('## <MACOS VERSION> ##', self.host_os_version)
        return template
