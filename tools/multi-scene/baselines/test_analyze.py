import unittest

from analyze import compatibility, compare, abba_issues, focused_reentrancy


class BaselineOracleTests(unittest.TestCase):
    def fixture(self):
        events = []
        for phase, name, identity in [("Home1", "Home", "h1"), ("Detail1", "Detail", "d1"), ("Home2", "Home", "h2")]:
            events += [{"type": "view", "id": identity, "name": name}, {"type": "action", "id": "a-" + phase, "name": phase, "owner": identity}, {"type": "resource", "id": "r-" + phase, "url": "https://fixture.invalid/" + phase, "owner": identity}]
        return {"events": events, "failures": []}

    def test_exact_fresh_occurrences_and_owners_pass(self):
        self.assertEqual(compatibility(self.fixture()), [])

    def test_correct_view_counts_with_wrong_return_owner_fail(self):
        data = self.fixture()
        data["events"][7]["owner"] = "d1"
        self.assertTrue(compatibility(data))

    def test_duplicate_marker_fails(self):
        data = self.fixture(); data["events"].append(data["events"][1])
        self.assertTrue(compatibility(data))

    def test_returned_home_uuid_reuse_fails(self):
        data = self.fixture(); data["events"][6]["id"] = "h1"
        self.assertTrue(compatibility(data))

    def test_missing_resource_fails(self):
        data = self.fixture(); data["events"].pop()
        self.assertTrue(compatibility(data))

    def test_absolute_and_relative_thresholds_are_not_raised(self):
        self.assertEqual(compare([100] * 100, [600] * 100, 500, 1000, .1, .2)["status"], "PASS")
        self.assertEqual(compare([100] * 100, [601] * 100, 500, 1000, .1, .2)["status"], "FAIL")
        self.assertEqual(compare([10000] * 100, [11001] * 100, 500, 1000, .1, .2)["status"], "FAIL")

    def test_p95_regression_is_not_hidden_by_median(self):
        self.assertEqual(compare([100] * 100, [100] * 90 + [1101] * 10, 500, 1000, .1, .2)["status"], "FAIL")

    def test_missing_samples_are_inconclusive(self):
        self.assertEqual(compare([], [100], 500, 1000, .1, .2)["status"], "INCONCLUSIVE")

    def test_full_context_oracle_requires_all_boundaries(self):
        data = {"focused": {"oracle": "full-RUMCoreContext-Equatable-and-handoff-fields-v1", "iterations": 10000,
                "live_home_context": True, "original_dispatches": 20000, "expected_dispatches": 20000,
                "boundary_checks": 90000, "caught_throws": 10000, "errors": 0, "timing_claim": False}, "failures": []}
        self.assertEqual(focused_reentrancy(data), "PASS")
        data["focused"]["errors"] = 1
        self.assertEqual(focused_reentrancy(data), "FAIL")
        data["focused"]["errors"] = 0
        data["focused"]["boundary_checks"] = 0
        self.assertEqual(focused_reentrancy(data), "FAIL")

    def test_scene_labels_alone_cannot_pass_full_context_gate(self):
        self.assertEqual(focused_reentrancy({"reentrancy": {"errors": 0}}), "INCONCLUSIVE")

    def test_abba_requires_complete_ordered_workload(self):
        manifest = {"builds": {a: {"Scene": {"sha256": a}} for a in ["baseline", "candidate"]}, "fixture": {"sha256": "fixture"}}
        rows = [{"arm": a, "order": i, "status": "MEASURED", "clean_install": True, "lifecycle": "Scene",
                 "result": {"dispatch_event_ns": [1] * 2000, "dispatch_ns": [1] * 7, "iterations_per_batch": 20000, "failures": []}}
                for i, a in enumerate(["baseline", "candidate", "candidate", "baseline"])]
        self.assertEqual(abba_issues(rows, "dispatch", manifest), [])
        self.assertTrue(abba_issues(rows[:-1], "dispatch", manifest))
        self.assertTrue(abba_issues(list(reversed(rows)), "dispatch", manifest))
        rows[0]["binary_sha256"] = "stale"
        self.assertTrue(abba_issues(rows, "dispatch", manifest))
        del rows[0]["binary_sha256"]
        rows[0]["result"]["dispatch_event_ns"].pop()
        self.assertTrue(abba_issues(rows, "dispatch", manifest))


if __name__ == "__main__":
    unittest.main()
