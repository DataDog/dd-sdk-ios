"""Three launches against one verified installation; invoked by the shared runner."""
import json
import os
import re
import subprocess
import time
import uuid
from pathlib import Path
from acceptance_common import require
import fatal_contract


def run_phases(runner, installed, executable, binary_sha, parse_records, file_hash, save):
    bundle = "com.datadoghq.rum-native-multi-scene-probe"
    container = runner.capture(["xcrun", "simctl", "get_app_container", runner.args.device, bundle, "data"]).strip()
    phases = []
    for index, scenario in enumerate(fatal_contract.SCENARIOS):
        run_id = runner.run_id if index == 0 else runner.run_id + "-" + str(index) + "-" + uuid.uuid4().hex[:8]
        phase = dict(scenario_id=scenario, run_id=run_id, process_exit=None, terminated=False)
        phases.append(phase)
        save(runner.out / "fatal-phases.json", phases)
        require(runner.capture(["xcrun", "simctl", "get_app_container", runner.args.device, bundle, "data"]).strip()
                == container, "data container changed between processes")
        phase["data_container"] = container
        phase["installed_binary_sha256"] = file_hash(installed / executable)
        require(phase["installed_binary_sha256"] == binary_sha, "installed binary changed between processes")
        console = runner.out / ("phase-" + str(index) + ".raw.log")
        with console.open("w") as output:
            runner.launch_process = subprocess.Popen(
                ["xcrun", "simctl", "launch", "--console-pty", runner.args.device, bundle,
                 "--probe-scenario", scenario, "--probe-run-id", run_id, "--probe-run-mode", "clean"],
                cwd=runner.repo, env=runner.environment, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + runner.args.scenario_timeout
        while time.monotonic() < deadline:
            records = parse_records(console.read_text(errors="replace"))
            terminal = any(r["type"] == "semantic-result" for r in records)
            if runner.launch_process.poll() is not None or (index > 0 and terminal):
                break
            if index == 0 and terminal:
                verdict = next(r["result"]["state"] for r in records if r["type"] == "semantic-result")
                if verdict != "PASS":
                    break
            time.sleep(0.25)
        records = parse_records(console.read_text(errors="replace"))
        phase["records"] = records
        phase["process_exit"] = runner.launch_process.poll()
        save(runner.out / "fatal-phases.json", phases)
        process = [r["signal"].get("fatal", {}).get("processID") for r in records
                   if r["type"] == "signal" and r["signal"].get("name") == "fatal-process"]
        require(len(process) == 1 and type(process[0]) is int, "native process identity not observed", "INCONCLUSIVE")
        launch_ids = re.findall(re.escape(bundle) + r":\s+(\d+)", console.read_text(errors="replace"))
        require(len(set(launch_ids)) == 1 and int(launch_ids[0]) == process[0],
                "launcher process identity differs from native observation", "INCONCLUSIVE")
        phase["process_id"] = int(launch_ids[0])
        if index == 0:
            try:
                os.kill(process[0], 0)
                phase["terminated"] = False
            except ProcessLookupError:
                phase["terminated"] = True
            save(runner.out / "fatal-phases.json", phases)
            # Validate the declared boundary before a recovery launch can consume evidence.
            signals, _, terminal, _ = fatal_contract.phase_records(phase, scenario)
            boundary = fatal_contract.assertion(signals, "fatal-crash-boundary")
            boundary_record = next(r for r in records if r.get("signal") == boundary)
            require(records.index(terminal) < records.index(boundary_record),
                    "process crashed before preparation PASS", "FAIL")
            require(phase["terminated"] and phase["process_exit"] not in [None, 0],
                    "fixture did not terminate with declared crash", "FAIL")
        else:
            fatal_contract.phase_records(phase, scenario)
            require(phase["process_exit"] is None, "recovery process terminated unexpectedly", "FAIL")
            runner.command(["xcrun", "simctl", "terminate", runner.args.device, bundle], "terminate-phase-" + str(index))
            runner.launch_process.wait(timeout=10)
            phase["terminated"] = True
            phase["process_exit_after_cleanup"] = runner.launch_process.returncode
        save(runner.out / "fatal-phases.json", phases)
        runner.stage("fatal_phase_" + str(index), dict(
            state="PASS", run_id=run_id, process_id=phase["process_id"], scenario=scenario,
            installed_binary_sha256=binary_sha, data_container=container,
            process_exit=phase["process_exit"]))
    return phases, fatal_contract.validate_local(phases, runner.run_id)
