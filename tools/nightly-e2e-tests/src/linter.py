# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import contextlib
from dataclasses import dataclass
from os.path import abspath


@dataclass
class CodeReference:
    file_path: str
    line_no: int
    line_text: str


@contextlib.contextmanager
def linter_context(code_reference: CodeReference):
    """
    Context manager for convenient work with linter's code reference.
    After context returns, the code reference is reseted to its previous value.
    """
    Linter.shared.push_context(code_reference=code_reference)
    try:
        yield
    finally:
        Linter.shared.pop_context()


class NoOpLinter:
    """
    Base, no-op linter.
    """

    shared: 'NoOpLinter'

    def push_context(self, code_reference: CodeReference):
        pass

    def pop_context(self):
        pass

    def emit_warning(self, message: str):
        pass

    def emit_error(self, message: str):
        pass


class Linter(NoOpLinter):
    """
    Linter emitting warnings and errors to STDOUT in Xcode format.
    """

    def __init__(self):
        self.context: [CodeReference] = []  # code reference stack
        self.events: [str] = []  # linter events (errors and warnings)

    def push_context(self, code_reference: CodeReference):
        """
        Adds new code reference to the top of the context stack.
        """
        self.context.append(code_reference)

    def pop_context(self):
        """
        Removes code reference from the top of the context stack - bringing back the previous context.
        """
        _ = self.context.pop()

    def __current_context(self):
        return self.context[-1]

    def emit_warning(self, message: str):
        code_reference = self.__current_context()
        event = f'{abspath(code_reference.file_path)}:{code_reference.line_no}: warning: {message}'
        self.events.append(event)

    def emit_error(self, message: str):
        code_reference = self.__current_context()
        event = f'{abspath(code_reference.file_path)}:{code_reference.line_no}: error: {message}'
        self.events.append(event)

    def print(self, strict: bool):
        if self.events:
            print(f'E2E tests linter found {len(self.events)} issue(s):')
            for event in self.events:
                print(event)
            if strict:
                print('Running in a strict mode, aborting 🛑.')
                exit(1)
