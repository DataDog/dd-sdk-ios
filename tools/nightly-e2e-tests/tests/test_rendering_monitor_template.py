# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import unittest
import string
import random
from unittest import mock
from src.linter import Linter, NoOpLinter, CodeReference
from src.main_tf_renderer import MonitorTemplate, MonitorVariable, MonitorConfiguration


class MonitorTemplateTestCase(unittest.TestCase):
    """
    Terraform syntax: https://www.terraform.io/docs/language/syntax/configuration.html
    """

    @classmethod
    def setUpClass(cls):
        Linter.shared = NoOpLinter()

    def test_it_renders_variable_with_no_default_value(self):
        template = MonitorTemplate('argument = ${{argument_value}} # comment')

        variable = MonitorVariable(name='$argument_value', value=random_string(), code_reference=any_code_reference())
        monitor = MonitorConfiguration(
            type='',
            variables=[variable],
            code_reference=any_code_reference()
        )

        rendered_template = template.render(monitor=monitor)
        expected_template = f'argument = {variable.value} # comment'

        self.assertEqual(expected_template, rendered_template, 'The variable should be substituted.')

    def test_it_renders_variable_with_default_value(self):
        template = MonitorTemplate('argument = ${{argument_value:-default value}} # comment')

        variable = MonitorVariable(name='$argument_value', value=random_string(), code_reference=any_code_reference())
        monitor = MonitorConfiguration(
            type='',
            variables=[variable],
            code_reference=any_code_reference()
        )

        rendered_template = template.render(monitor=monitor)
        expected_template = f'argument = {variable.value} # comment'

        self.assertEqual(expected_template, rendered_template, 'The variable should be substituted.')

    def test_it_uses_default_value(self):
        template = MonitorTemplate('argument = ${{argument_value:-"default value"}} # comment')

        monitor = MonitorConfiguration(
            type='',
            variables=[],
            code_reference=any_code_reference()
        )

        rendered_template = template.render(monitor=monitor)
        expected_template = f'argument = "default value" # comment'

        self.assertEqual(expected_template, rendered_template, 'It should use default value from the template.')

    def test_it_renders_multiline_template(self):
        template = MonitorTemplate(
            '''
            resource "datadog_monitor" ${{monitor_id}} {
                argument1 = ${{argument1_value}} # comment
                argument2 = ${{argument2_value:-"default value for argument 2"}}
            }
            '''
        )

        variable1 = MonitorVariable(name='$monitor_id', value=random_string(), code_reference=any_code_reference())
        variable2 = MonitorVariable(name='$argument1_value', value=random_string(), code_reference=any_code_reference())
        monitor = MonitorConfiguration(
            type='',
            variables=[variable1, variable2],
            code_reference=any_code_reference()
        )

        rendered_template = template.render(monitor=monitor)
        expected_template = f'''
            resource "datadog_monitor" {variable1.value} {{
                argument1 = {variable2.value} # comment
                argument2 = "default value for argument 2"
            }}
            '''

        self.assertEqual(expected_template, rendered_template)

    # noinspection PyMethodMayBeStatic
    def test_when_mandatory_variable_is_not_specified_it_fails(self):
        template = MonitorTemplate('argument = ${{argument_with_no_default}}')

        monitor = MonitorConfiguration(
            type='',
            variables=[],
            code_reference=any_code_reference()
        )

        with mock.patch.object(Linter.shared, 'emit_error') as linter_method:
            _ = template.render(monitor=monitor)

        linter_method.assert_called_once_with(
            message='Variable $argument_with_no_default is required, but not defined for this monitor.'
        )

    def test_it_renders_monitor_code(self):
        template = MonitorTemplate(
            '''
            some text before
            ## MONITOR_CODE ##
            some text after
            '''
        )

        monitor_code = random_multiline_string(length=256)

        monitor = MonitorConfiguration(
            type='',
            variables=[],
            code_reference=any_code_reference(),
            code=monitor_code
        )

        rendered_template = template.render(monitor=monitor)
        expected_template = f'''
            some text before
            {monitor_code}
            some text after
            '''

        self.assertEqual(expected_template, rendered_template)


def random_string(length: int = 32):
    characters_set = string.ascii_letters + string.digits + string.punctuation + ' \t'
    return ''.join((random.choice(characters_set) for i in range(length)))


def random_multiline_string(length: int = 32):
    characters_set = string.ascii_letters + string.digits + string.punctuation + ' \t' + '\n'
    return ''.join((random.choice(characters_set) for i in range(length)))


def any_code_reference():
    return CodeReference(file_path='', line_no=0, line_text='')
