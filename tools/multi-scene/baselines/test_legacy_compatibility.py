"""Negative controls for the C03 owner and pre-transition acceptance contract."""
import copy
from datetime import datetime, timezone
import itertools
import unittest

import legacy_compatibility as legacy


def view(identifier, name="Home", active=True):
    return {"type": "view", "id": identifier, "name": name, "active": active}


def pair(phase, owner):
    return [{"type": "action", "id": "action-" + phase, "name": phase, "owner": owner},
            {"type": "resource", "id": "resource-" + phase,
             "url": "https://fixture.invalid/" + phase, "owner": owner}]


def navigation():
    return {"run_id": "fresh", "mode": "automatic", "os": "27.0", "fixture_version": 1,
            "has_scene_manifest": False, "failures": [], "events": [
                view("home-1"), *pair("Home1", "home-1"), view("home-1", active=False),
                view("detail", "Detail"), *pair("Detail1", "detail"), view("detail", "Detail", False),
                view("home-2"), *pair("Home2", "home-2")]}


def lifecycle(manual=False):
    rows = [view("home-1"), {"type": "lifecycle", "name": legacy.ACTIVE},
            *pair("BeforeBackground", "home-1"),
            {"type": "lifecycle", "name": legacy.BACKGROUND}]
    if not manual:
        rows.append(view("home-1", active=False))
    rows += [{"type": "lifecycle", "name": legacy.FOREGROUND},
             {"type": "lifecycle", "name": legacy.ACTIVE}]
    if not manual:
        rows.append(view("home-2"))
    rows += pair("AfterForeground", "home-1" if manual else "home-2")
    return {"run_id": "fresh", "mode": "lifecycle-manual" if manual else "lifecycle-automatic",
            "os": "27.0", "fixture_version": 1, "has_scene_manifest": False,
            "failures": [], "events": rows}


def ready():
    return {"run_id": "fresh", "failures": [], "events": [
        view("home-1"), {"type": "lifecycle", "name": legacy.ACTIVE},
        *pair("BeforeBackground", "home-1")]}


def matrix():
    cases = []
    for arm, version, mode in itertools.product(legacy.ARMS, legacy.VERSIONS, legacy.MODES):
        data = lifecycle(mode.endswith("manual")) if mode.startswith("lifecycle-") else navigation()
        data.update(mode=mode, os=version, run_id="/".join((arm, version, mode)))
        cases.append({"arm": arm, "os": version, "mode": mode, "run_id": data["run_id"],
                      "status": "PASS", "installed_identity": True, "clean_install": True,
                      "cleanup": {"status": "PASS"},
                      "signature": legacy.check_result(data, data["run_id"], mode, version)})
    return cases


class LegacyOracleTests(unittest.TestCase):
    def test_accepts_original_navigation_contract(self):
        for mode in ("automatic", "manual"):
            data = navigation()
            data["mode"] = mode
            self.assertEqual(legacy.check_result(data, "fresh", mode, "27.0")["view_names"],
                             ["Home", "Detail", "Home"])

    def test_accepts_original_lifecycle_contract(self):
        for manual in (False, True):
            data = lifecycle(manual)
            signature = legacy.check_result(data, "fresh", data["mode"], "27.0")
            self.assertEqual(signature["stopped"], [False] if manual else [True, False])

    def test_rejects_navigation_wrong_owner_and_duplicate(self):
        for mutation in ("owner", "duplicate", "reused"):
            data = navigation()
            if mutation == "owner":
                data["events"][1]["owner"] = "detail"
            elif mutation == "duplicate":
                data["events"].append(copy.deepcopy(data["events"][1]))
            else:
                for row in data["events"]:
                    if row.get("id") == "home-2":
                        row["id"] = "home-1"
                    if row.get("owner") == "home-2":
                        row["owner"] = "home-1"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                legacy.check_result(data, "fresh", "automatic", "27.0")

    def test_rejects_restored_identity_manifest_and_runtime(self):
        for field, value in (("run_id", "restored"), ("has_scene_manifest", True),
                             ("has_scene_manifest", None), ("os", "26.5"),
                             ("fixture_version", 0), ("mode", "manual"),
                             ("failures", ["initial Home missing"])):
            data = navigation()
            data[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                legacy.check_result(data, "fresh", "automatic", "27.0")

    def test_rejects_wrong_lifecycle_owner_even_if_count_is_correct(self):
        data = lifecycle()
        data["events"][-1]["owner"] = "home-1"
        with self.assertRaisesRegex(ValueError, "wrong owner"):
            legacy.check_result(data, "fresh", data["mode"], "27.0")

    def test_rejects_missing_duplicate_and_reordered_notifications(self):
        for mutation in ("missing", "duplicate", "reordered"):
            data = lifecycle()
            indexes = [i for i, r in enumerate(data["events"]) if r["type"] == "lifecycle"]
            if mutation == "missing":
                data["events"].pop(indexes[1])
            elif mutation == "duplicate":
                data["events"].insert(indexes[1], {"type": "lifecycle", "name": legacy.BACKGROUND})
            else:
                data["events"][indexes[1]], data["events"][indexes[2]] = data["events"][indexes[2]], data["events"][indexes[1]]
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                legacy.check_result(data, "fresh", data["mode"], "27.0")

    def test_rejects_assertions_after_boundary(self):
        data = lifecycle()
        action = data["events"].pop(2)
        data["events"].append(action)
        with self.assertRaisesRegex(ValueError, "wrong lifecycle boundary"):
            legacy.check_result(data, "fresh", data["mode"], "27.0")

    def test_rejects_manual_stop_and_automatic_reuse(self):
        manual = lifecycle(True)
        manual["events"].append(view("home-1", active=False))
        automatic = lifecycle()
        for row in automatic["events"]:
            if row.get("id") == "home-2":
                row["id"] = "home-1"
            if row.get("owner") == "home-2":
                row["owner"] = "home-1"
        for data in (manual, automatic):
            with self.assertRaises(ValueError):
                legacy.check_result(data, "fresh", data["mode"], "27.0")

    def test_readiness_rejects_stale_consumed_and_wrong_owner(self):
        legacy.check_ready(ready(), "fresh")
        for mutation in ("stale", "consumed", "wrong-owner", "fixture-failure", "duplicate"):
            data = ready()
            if mutation == "stale":
                data["run_id"] = "restored"
            elif mutation == "consumed":
                data["events"].append({"type": "lifecycle", "name": legacy.BACKGROUND})
            elif mutation == "wrong-owner":
                data["events"][2]["owner"] = "peer"
            elif mutation == "fixture-failure":
                data["failures"] = ["marker not ready"]
            else:
                data["events"].append(copy.deepcopy(data["events"][2]))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                legacy.check_ready(data, "fresh")

    def test_driver_boundaries_reject_late_or_missing_assertion(self):
        keys = ("launched_at", "readiness_accepted_at", "background_command_started_at",
                "background_observed_at", "foreground_command_started_at",
                "foreground_command_finished_at", "finished_at")
        good = {key: f"2026-09-18T20:00:0{i}+00:00" for i, key in enumerate(keys)}
        legacy.check_boundaries(good)
        late = dict(good, readiness_accepted_at=good["foreground_command_started_at"])
        with self.assertRaises(ValueError):
            legacy.check_boundaries(late)
        del good["readiness_accepted_at"]
        with self.assertRaises(KeyError):
            legacy.check_boundaries(good)

    def test_complete_matrix_requires_each_cell_identity_and_cleanup(self):
        self.assertEqual(legacy.matrix_verdict(matrix()), "PASS")
        cases = matrix()
        self.assertEqual(legacy.matrix_verdict(cases[:-1]), "INCONCLUSIVE")
        for field in ("installed_identity", "clean_install"):
            cases = matrix()
            cases[0][field] = False
            self.assertEqual(legacy.matrix_verdict(cases), "INCONCLUSIVE")
        cases = matrix()
        cases[0]["cleanup"]["status"] = "INCONCLUSIVE"
        self.assertEqual(legacy.matrix_verdict(cases), "INCONCLUSIVE")

    def test_matrix_rejects_duplicate_cell_or_run_and_preserves_fail(self):
        cases = matrix()
        cases[-1] = copy.deepcopy(cases[0])
        self.assertEqual(legacy.matrix_verdict(cases), "FAIL")
        cases = matrix()
        cases[-1]["run_id"] = cases[0]["run_id"]
        self.assertEqual(legacy.matrix_verdict(cases), "FAIL")
        cases = matrix()
        cases[0]["status"] = "FAIL"
        self.assertEqual(legacy.matrix_verdict(cases[:1]), "FAIL")

    def test_matrix_requires_matching_occurrence_relationships(self):
        cases = matrix()
        cases[0]["signature"]["owners"][0]["occurrence"] = 9
        self.assertEqual(legacy.matrix_verdict(cases), "FAIL")

    def test_apple_timestamp_space_recovers_without_loosening_timezone(self):
        expected = datetime(2026, 9, 18, 19, 59, 1, 773900, tzinfo=timezone.utc)
        self.assertEqual(legacy.crash_time("2026-09-18 21:59:01.7739 +0200"), expected)
        self.assertEqual(legacy.crash_time(expected.isoformat()), expected)
        with self.assertRaises(ValueError):
            legacy.crash_time("2026-09-18T19:59:01")


if __name__ == "__main__":
    unittest.main()
