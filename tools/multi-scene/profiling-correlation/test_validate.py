import copy
import unittest
from run_simulator import require_configuration
from validate import (BOUNDARIES, LAUNCH_VIEW, OPERATION_COUNTS, VIEW_NAMES,
                      seconds_to_nanoseconds, validate_attachment, validate_native)

RUN = "exp187-00000000-0000-0000-0000-000000000001"
REVISION = "a" * 40


def fixture():
    ids = [f"00000000-0000-0000-0000-{n:012}" for n in range(2, 10)]
    views = [{"id": ids[n], "name": name, "sessionID": ids[3], "active": False}
             for n, name in enumerate(VIEW_NAMES)]
    views.append({"id": "00000000-0000-0000-0000-000000000010", "name": LAUNCH_VIEW,
                  "sessionID": ids[3], "active": False})
    operations = []
    for index, (key, step, owner, time) in enumerate([
        ("A", "start", 0, 100), ("B", "start", 1, 101),
        ("B", "end", 2, 103), ("A", "end", 2, 106)
    ]):
        operations.append({
            "vital": {"id": ids[4 + index], "type": "vital", "name": "exp187.parallel",
                      "start_ns": int((time + 2 + 978307200) * 1e9)},
            "operationKey": RUN + "/" + key, "step": step, "viewID": views[owner]["id"],
            "viewName": views[owner]["name"], "sessionID": ids[3],
            "referenceTime": time, "serverTimeOffset": 2, "profilingRunning": True
        })
    expected = [dict(operations[n]["vital"], duration_ns=duration)
                for n, duration in [(0, 6_000_000_000), (1, 2_000_000_000)]]
    return {
        "schemaVersion": 2, "configuration": {"applicationLaunchSampleRate": 0, "continuousSampleRate": 100},
        "experiment": "EXP-187", "nativeStatus": "PASS",
        "backendStatus": "NOT_VERIFIED", "runID": RUN, "sourceRevision": REVISION,
        "platform": "PHYSICAL_DEVICE", "processID": 123,
        "boundaries": list(BOUNDARIES),
        "checkpoints": [{"number": n, "passed": True, "boundary": BOUNDARIES.index(f"assert:{n}") + 1,
                         "operationCount": count, "profilingRunning": n >= 3} for n, count in enumerate(OPERATION_COUNTS, 1)],
        "observations": {"ttidCount": 1, "profilingRunning": True, "views": views, "operations": operations},
        "expectedProfileVitals": expected
    }


class NativeValidationTests(unittest.TestCase):
    def test_disabled_missing_stopped_and_late_profiler_readiness_fail(self):
        for mutation in ["disabled", "missing", "stopped", "late", "lost", "operation"]:
            with self.subTest(mutation=mutation):
                receipt = fixture()
                if mutation == "disabled":
                    receipt["configuration"]["continuousSampleRate"] = 0
                elif mutation == "missing":
                    receipt["observations"]["profilingRunning"] = None
                elif mutation == "stopped":
                    receipt["observations"]["profilingRunning"] = False
                elif mutation == "late":
                    receipt["checkpoints"][2]["profilingRunning"] = False
                elif mutation == "lost":
                    receipt["checkpoints"][5]["profilingRunning"] = False
                else:
                    receipt["observations"]["operations"][0]["profilingRunning"] = False
                with self.assertRaises(ValueError):
                    validate_native(receipt, RUN, REVISION)

    def test_builtin_launch_is_explicit_and_cannot_hide_inventory_errors(self):
        for mutation in ["missing", "extra", "session", "active", "collapsed", "name"]:
            with self.subTest(mutation=mutation):
                receipt = fixture()
                views = receipt["observations"]["views"]
                if mutation == "missing":
                    views.pop()
                elif mutation == "extra":
                    views.append(copy.deepcopy(views[-1]))
                elif mutation == "session":
                    views[-1]["sessionID"] = views[0]["id"]
                elif mutation == "active":
                    views[-1]["active"] = True
                elif mutation == "collapsed":
                    views[-1]["id"] = views[0]["id"]
                else:
                    views[-1]["name"] = "unexpected.view"
                with self.assertRaises(ValueError):
                    validate_native(receipt, RUN, REVISION)

    def test_nanosecond_conversion_matches_swift_rounding_and_saturation(self):
        for seconds, expected in [(0.5e-9, 1), (-0.5e-9, -1), (1.5e-9, 2), (-1.5e-9, -2),
                                  (0.49e-9, 0), (-0.49e-9, 0), (1e12, 2 ** 63 - 1), (-1e12, -(2 ** 63))]:
            with self.subTest(seconds=seconds):
                self.assertEqual(seconds_to_nanoseconds(seconds), expected)

    def test_observed_fractional_duration_keeps_exact_nanosecond_oracle(self):
        # Actual attempt C clocks. Truncation loses one nanosecond for A.
        receipt = fixture()
        operations = receipt["observations"]["operations"]
        clocks = [
            (811412335.529603, 0.04941272735595703, 1789719535579015680),
            (811412336.632536, 0.07980263233184814, 1789719536712338688),
            (811412338.744279, 0.07980263233184814, 1789719538824081664),
            (811412341.925247, 0.07980263233184814, 1789719542005049600),
        ]
        for operation, (reference, offset, start) in zip(operations, clocks):
            operation["referenceTime"] = reference
            operation["serverTimeOffset"] = offset
            operation["vital"]["start_ns"] = start
        receipt["expectedProfileVitals"] = [dict(operations[n]["vital"], duration_ns=duration)
                                            for n, duration in [(0, 6395643950), (1, 2111742973)]]
        expected = validate_native(receipt, RUN, REVISION)
        validate_attachment(expected, expected)
        for delta in [-1, 1]:
            with self.subTest(delta=delta):
                wrong_receipt = copy.deepcopy(receipt)
                wrong_receipt["expectedProfileVitals"][0]["duration_ns"] += delta
                with self.assertRaises(ValueError):
                    validate_native(wrong_receipt, RUN, REVISION)
                wrong_attachment = copy.deepcopy(expected)
                wrong_attachment[0]["duration_ns"] += delta
                with self.assertRaises(ValueError):
                    validate_attachment(expected, wrong_attachment)

    def test_missing_or_unresolved_configuration_rejected_before_install(self):
        for configuration in [
            {}, {"ClientToken": "", "ApplicationID": RUN[7:]},
            {"ClientToken": "$(DATADOG_CLIENT_TOKEN)", "ApplicationID": RUN[7:]},
            {"ClientToken": "synthetic-test-token", "ApplicationID": ""},
            {"ClientToken": "synthetic-test-token", "ApplicationID": "$(RUM_APPLICATION_ID)"},
        ]:
            with self.subTest(configuration=configuration):
                with self.assertRaises(ValueError):
                    require_configuration({"DatadogConfiguration": configuration})
        require_configuration({"DatadogConfiguration": {
            "ClientToken": "synthetic-test-token", "ApplicationID": RUN[7:]}})

    def test_actual_identity_and_reverse_attachment_order_pass(self):
        receipt = fixture()
        expected = validate_native(receipt, RUN, REVISION)
        validate_attachment(expected, list(reversed(expected)))

    def test_missing_duplicate_and_wrong_operation_owner_fail(self):
        for mutation in ["missing", "duplicate", "owner", "key", "session", "clock", "nan", "infinity"]:
            with self.subTest(mutation=mutation):
                receipt = fixture()
                operations = receipt["observations"]["operations"]
                if mutation == "missing":
                    operations.pop()
                elif mutation == "duplicate":
                    operations[1]["vital"]["id"] = operations[0]["vital"]["id"]
                elif mutation == "owner":
                    operations[2]["viewID"] = operations[0]["viewID"]
                elif mutation == "key":
                    operations[1]["operationKey"] = operations[0]["operationKey"]
                elif mutation == "session":
                    operations[2]["sessionID"] = operations[0]["viewID"]
                elif mutation == "clock":
                    operations[0]["serverTimeOffset"] += 1
                else:
                    operations[0]["referenceTime"] = float("nan" if mutation == "nan" else "inf")
                with self.assertRaises(ValueError):
                    validate_native(receipt, RUN, REVISION)

    def test_stale_identity_and_consumed_or_late_readiness_fail(self):
        for mutation in ["run", "revision", "pid", "ttid", "late", "consumed", "failed"]:
            with self.subTest(mutation=mutation):
                receipt = fixture()
                if mutation == "run":
                    receipt["runID"] += "restored"
                elif mutation == "revision":
                    receipt["sourceRevision"] = "b" * 40
                elif mutation == "pid":
                    receipt["processID"] = -1
                elif mutation == "ttid":
                    receipt["observations"]["ttidCount"] = 0
                elif mutation == "late":
                    receipt["boundaries"][3:5] = list(reversed(receipt["boundaries"][3:5]))
                elif mutation == "consumed":
                    receipt["checkpoints"][4]["operationCount"] = 0
                else:
                    receipt["checkpoints"][7]["passed"] = False
                with self.assertRaises(ValueError):
                    validate_native(receipt, RUN, REVISION)

    def test_simulator_requires_explicit_mechanics_mode(self):
        receipt = fixture()
        receipt["platform"] = "SIMULATOR_MECHANICS_ONLY"
        with self.assertRaises(ValueError):
            validate_native(receipt, RUN, REVISION)
        validate_native(receipt, RUN, REVISION, allow_simulator=True)

    def test_view_inventory_and_native_expectation_must_be_exact(self):
        for mutation in ["extra", "active", "collapsed", "expected"]:
            with self.subTest(mutation=mutation):
                receipt = fixture()
                views = receipt["observations"]["views"]
                if mutation == "extra":
                    views.append(copy.deepcopy(views[0]))
                elif mutation == "active":
                    views[0]["active"] = True
                elif mutation == "collapsed":
                    views[1]["id"] = views[0]["id"]
                else:
                    receipt["expectedProfileVitals"][0]["duration_ns"] += 1
                with self.assertRaises(ValueError):
                    validate_native(receipt, RUN, REVISION)

    def test_profile_start_identity_and_exact_numerics_cannot_be_weakened(self):
        receipt = fixture()
        expected = validate_native(receipt, RUN, REVISION)
        for mutation in ["missing", "duplicate", "end_id", "duration", "start", "name", "float", "extra_field"]:
            with self.subTest(mutation=mutation):
                attachment = copy.deepcopy(expected)
                if mutation == "missing":
                    attachment.pop()
                elif mutation == "duplicate":
                    attachment[1] = copy.deepcopy(attachment[0])
                elif mutation == "end_id":
                    attachment[0]["id"] = receipt["observations"]["operations"][3]["vital"]["id"]
                elif mutation == "duration":
                    attachment[0]["duration_ns"], attachment[1]["duration_ns"] = attachment[1]["duration_ns"], attachment[0]["duration_ns"]
                elif mutation == "start":
                    attachment[0]["start_ns"] += 1
                elif mutation == "name":
                    attachment[0]["name"] = "another.operation"
                elif mutation == "float":
                    attachment[0]["duration_ns"] = float(attachment[0]["duration_ns"])
                else:
                    attachment[0]["view"] = receipt["observations"]["views"][0]["id"]
                with self.assertRaises(ValueError):
                    validate_attachment(expected, attachment)


if __name__ == "__main__":
    unittest.main()
