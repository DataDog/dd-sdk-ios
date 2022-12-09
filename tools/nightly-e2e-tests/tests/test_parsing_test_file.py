# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import unittest
import os
from tempfile import NamedTemporaryFile
from src.test_file_parser import read_test_file, TestFile, TestMethod, MonitorConfiguration, MonitorVariable
from src.linter import Linter, NoOpLinter, CodeReference


class TestFileTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Linter.shared = NoOpLinter()

    def test_it_reads_monitor_definition_from_test_method(self):
        file = NamedTemporaryFile(delete=False)
        file.write(b"""
        /// Monitor definition assigned to the test method:
        /// ```apm
        /// $foo = <foo value>
        /// $bar = <bar value>
        /// ```
        func test_method_name() {
        }
        """)
        file.close()

        expected_test_file = TestFile(
            test_methods=[
                TestMethod(
                    method_name='test_method_name',
                    monitors=[
                        MonitorConfiguration(
                            type='apm',
                            variables=[
                                MonitorVariable(
                                    name='$foo',
                                    value='<foo value>',
                                    code_reference=CodeReference(
                                        file_path=file.name,
                                        line_no=4,
                                        line_text='/// $foo = <foo value>')
                                ),
                                MonitorVariable(
                                    name='$bar',
                                    value='<bar value>',
                                    code_reference=CodeReference(
                                        file_path=file.name,
                                        line_no=5,
                                        line_text='/// $bar = <bar value>')
                                )
                            ],
                            code_reference=CodeReference(
                                file_path=file.name,
                                line_no=3,
                                line_text='/// ```'
                            ),
                            code='\n'.join(
                                [
                                    '        /// Monitor definition assigned to the test method:',
                                    '        /// ```apm',
                                    '        /// $foo = <foo value>',
                                    '        /// $bar = <bar value>',
                                    '        /// ```',
                                    '        func test_method_name() {',
                                    '        }',
                                    ''
                                ]
                            )
                        )
                    ],
                    code_reference=CodeReference(
                        file_path=file.name,
                        line_no=7,
                        line_text='        func test_method_name() {\n'
                    ),
                    code='\n'.join(
                        [
                            '        func test_method_name() {',
                            '        }',
                            ''
                        ]
                    )
                )
            ],
            independent_monitors=[]
        )

        actual_test_file: TestFile = read_test_file(file.name)

        self.assertEqual(actual_test_file, expected_test_file)
        os.unlink(file.name)

    def test_it_reads_independent_monitor_definition_from_test_file(self):
        file = NamedTemporaryFile(delete=False)
        file.write(b"""
        class Foo {
            /// Monitor definition not assigned to any test method:
            /// ```apm
            /// $foo = <foo value>
            /// $bar = <bar value>
            /// ```
        }
        """)
        file.close()

        expected_test_file = TestFile(
            test_methods=[],
            independent_monitors=[
                MonitorConfiguration(
                    type='apm',
                    variables=[
                        MonitorVariable(
                            name='$foo',
                            value='<foo value>',
                            code_reference=CodeReference(
                                file_path=file.name,
                                line_no=5,
                                line_text='/// $foo = <foo value>')
                        ),
                        MonitorVariable(
                            name='$bar',
                            value='<bar value>',
                            code_reference=CodeReference(
                                file_path=file.name,
                                line_no=6,
                                line_text='/// $bar = <bar value>')
                        )
                    ],
                    code_reference=CodeReference(
                        file_path=file.name,
                        line_no=4,
                        line_text='/// ```'
                    ),
                    code='\n'.join(
                        [
                            '            /// Monitor definition not assigned to any test method:',
                            '            /// ```apm',
                            '            /// $foo = <foo value>',
                            '            /// $bar = <bar value>',
                            '            /// ```',
                            ''
                        ]
                    )
                )
            ]
        )

        actual_test_file: TestFile = read_test_file(file.name)

        self.assertEqual(actual_test_file, expected_test_file)
        os.unlink(file.name)
