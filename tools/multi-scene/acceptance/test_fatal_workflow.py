import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import fatal_workflow
from test_fatal_contract import fixture


class FatalWorkflowTests(unittest.TestCase):
    def run_fixture(self, directory, late_failure=False, wrong_pid=False):
        phases, run = fixture()
        launched, stages = [], []
        bundle = "com.datadoghq.rum-native-multi-scene-probe"

        class Process:
            def __init__(self, command, **kwargs):
                self.index = len(launched)
                self.path = Path(kwargs["stdout"].name)
                phase = phases[self.index]
                actual_run = command[command.index("--probe-run-id") + 1]
                self.records = json.loads(json.dumps(phase["records"]).replace(phase["run_id"], actual_run))
                self.returncode = 0 if self.index == 0 else None
                self.pid = phase["process_id"]
                self.write_console(include_pid=self.index == 0)
                launched.append(self)

            def write_console(self, include_pid):
                value = json.dumps(self.records)
                if include_pid:
                    pid = 1 if wrong_pid and self.index == 1 else self.pid
                    value += "\nLAUNCHER\n" + bundle + ": " + str(pid)
                self.path.write_text(value)

            def poll(self):
                return self.returncode

            def wait(self, timeout):
                if late_failure and self.index == 1:
                    last = next(r["signal"] for r in reversed(self.records) if r["type"] == "signal")
                    failed = copy.deepcopy(last)
                    failed.update(kind="assertion", name="late-failure", result="FAIL", sequence=last["sequence"] + 1)
                    self.records.append(dict(type="signal", signal=failed))
                self.returncode = 0
                self.write_console(include_pid=True)
                return self.returncode

        runner = SimpleNamespace(
            run_id=run, out=Path(directory), repo=Path(directory), environment={},
            args=SimpleNamespace(device="synthetic-device", scenario_timeout=5),
            capture=lambda _: "/synthetic/current-install",
            command=lambda *_: None,
            stage=lambda name, value: stages.append((name, value)),
        )
        self.launched = launched
        parse = lambda value: json.loads(value.split("\nLAUNCHER\n")[0])
        save = lambda path, value: path.write_text(json.dumps(value))
        with patch.object(fatal_workflow.subprocess, "Popen", Process), \
             patch.object(fatal_workflow.os, "kill", side_effect=ProcessLookupError), \
             patch.object(fatal_workflow.uuid, "uuid4", return_value=SimpleNamespace(hex="a" * 32)):
            return fatal_workflow.run_phases(runner, Path(directory), "Probe", "a" * 64,
                                            parse, lambda _: "a" * 64, save)

    def test_buffered_launcher_pid_is_collected_after_recovery_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            phases, local = self.run_fixture(directory)
            self.assertEqual(local["state"], "PASS")
            self.assertEqual(len(phases), 3)
            self.assertEqual(phases[1]["process_id"], 1841)
            self.assertIsNone(phases[1]["launcher_exit"])
            self.assertEqual(phases[1]["launcher_exit_after_cleanup"], 0)

    def test_late_failure_is_reparsed_before_consumption_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(Rejected):
                self.run_fixture(directory, late_failure=True)
            self.assertEqual(len(self.launched), 2)

    def test_buffered_foreign_pid_is_rejected_before_consumption_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(Rejected):
                self.run_fixture(directory, wrong_pid=True)
            self.assertEqual(len(self.launched), 2)


if __name__ == "__main__":
    unittest.main()
