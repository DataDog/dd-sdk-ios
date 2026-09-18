import copy
import unittest
from run_simulator import require_configuration
from validate import BOUNDARIES, OPERATION_COUNTS, VIEW_NAMES, validate_attachment, validate_native

RUN = "exp187-00000000-0000-0000-0000-000000000001"
REVISION = "a" * 40


def fixture():
    ids = [f"00000000-0000-0000-0000-{n:012}" for n in range(2, 10)]
    views = [{"id": ids[n], "name": name, "sessionID": ids[3], "active": False}
             for n, name in enumerate(VIEW_NAMES)]
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
            "referenceTime": time, "serverTimeOffset": 2
        })
    expected = [dict(operations[n]["vital"], duration_ns=duration)
                for n, duration in [(0, 6_000_000_000), (1, 2_000_000_000)]]
    return {
        "schemaVersion": 1, "experiment": "EXP-187", "nativeStatus": "PASS",
        "backendStatus": "NOT_VERIFIED", "runID": RUN, "sourceRevision": REVISION,
        "platform": "PHYSICAL_DEVICE", "processID": 123,
        "boundaries": list(BOUNDARIES),
        "checkpoints": [{"number": n, "passed": True, "boundary": BOUNDARIES.index(f"assert:{n}") + 1,
                         "operationCount": count} for n, count in enumerate(OPERATION_COUNTS, 1)],
        "observations": {"ttidCount": 1, "views": views, "operations": operations},
        "expectedProfileVitals": expected
    }


class NativeValidationTests(unittest.TestCase):
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
