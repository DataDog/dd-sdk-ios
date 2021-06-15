# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
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

    def test_it_reads_monitor_definition(self):
        file = NamedTemporaryFile(delete=False)
        file.write(b"""
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
                            id='test_method_name',
                            type='apm',
                            variables=[
                                MonitorVariable(
                                    name='$foo',
                                    value='<foo value>',
                                    code_reference=CodeReference(
                                        file_path=file.name,
                                        line_no=3,
                                        line_text='/// $foo = <foo value>')
                                ),
                                MonitorVariable(
                                    name='$bar',
                                    value='<bar value>',
                                    code_reference=CodeReference(
                                        file_path=file.name,
                                        line_no=4,
                                        line_text='/// $bar = <bar value>')
                                )
                            ],
                            code_reference=CodeReference(
                            file_path=file.name,
                            line_no=2,
                            line_text='/// ```'
                            )
                        )
                    ],
                    code_reference=CodeReference(
                        file_path=file.name,
                        line_no=6,
                        line_text='        func test_method_name() {\n'
                    )
                )
            ]
        )

        actual_test_file: TestFile = read_test_file(file.name)

        self.assertEqual(actual_test_file, expected_test_file)
        os.unlink(file.name)
