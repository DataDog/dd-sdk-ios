"""Focused H04 projection controls; no native input, timing or backend access."""
from copy import deepcopy
import unittest
import focus_activation_inventory as inventory


IDENTITY = dict(application_id="app", service="fixture", source="ios")
RUN = "run"


def fixture():
    owners = ["launch", "a1", "b1", "a2", "b2", "a3"]
    local = dict(session_id="session", views=[dict(view_id=v, session_id="session",
        name="ApplicationLaunch" if v == "launch" else "ProbeHomeView") for v in owners], work=[])
    rows = []
    def row(kind, owner=None):
        p = dict(application=dict(id="app"), service="fixture", session=dict(id="session"), type=kind)
        if owner is not None: p["view"] = dict(id=owner)
        r = dict(id=str(len(rows)), attributes=dict(source="ios", service="fixture", custom=p))
        rows.append(r)
        return p
    for v in local["views"]:
        p = row("view", v["view_id"]); p["view"]["name"] = v["name"]
        if v["view_id"] != "launch": p["context"] = dict(probe=dict(run_id=RUN))
    for phase, owner, scene in [("initial-b", "b1", "scene-B"), ("activate-a", "a2", "scene-A"),
                              ("reactivate-b", "b2", "scene-B"), ("reactivate-a", "a3", "scene-A")]:
        for kind in ["action", "resource"]:
            p = row(kind, owner); p[kind] = dict(id=phase + kind)
            p["context"] = dict(probe=dict(run_id=RUN, phase=phase, source_scene=scene))
            local["work"].append(dict(kind=kind, event_id=p[kind]["id"], session_id="session",
                view_id=owner, phase=phase, source_scene=scene))
    row("session")
    row("vital", "a1")["vital"] = dict(type="app_launch", app_launch_metric="ttid", name="time_to_initial_display")
    return local, rows


class ProjectionControls(unittest.TestCase):
    def setUp(self): self.local, self.rows = fixture()
    def grade(self, count=None):
        return inventory.validate(self.local, RUN, self.rows, len(self.rows) if count is None else count, identity=IDENTITY)
    def reject(self):
        with self.assertRaises(ValueError): self.grade()
    def test_actual_envelope_shape_without_process_probe(self):
        before = deepcopy(self.rows); result = self.grade()
        self.assertEqual(result["raw_count"], 16); self.assertEqual(result["marker_pairs"], 4)
        self.assertEqual(len(result["infrastructure"]), 3); self.assertEqual(self.rows, before)
    def test_matching_inner_source(self):
        for r in self.rows: r["attributes"]["custom"]["source"] = "ios"
        self.assertEqual(self.grade()["state"], "PASS")
    def test_singleton_envelope_service(self):
        for r in self.rows: r["attributes"]["service"] = ["fixture"]
        self.assertEqual(self.grade()["state"], "PASS")
    def test_count_mismatch(self):
        with self.assertRaises(ValueError): self.grade(15)
    def test_duplicate_raw_id(self): self.rows[1]["id"] = self.rows[0]["id"]; self.reject()
    def test_missing_raw_id(self): del self.rows[1]["id"]; self.reject()
    def test_wrong_outer_source(self): self.rows[0]["attributes"]["source"] = "browser"; self.reject()
    def test_conflicting_source(self): self.rows[0]["attributes"]["custom"]["source"] = "browser"; self.reject()
    def test_missing_source(self): del self.rows[0]["attributes"]["source"]; self.reject()
    def test_foreign_application(self): self.rows[0]["attributes"]["custom"]["application"]["id"] = "other"; self.reject()
    def test_foreign_service(self): self.rows[0]["attributes"]["custom"]["service"] = "other"; self.reject()
    def test_conflicting_service(self): self.rows[0]["attributes"]["service"] = ["fixture", "other"]; self.reject()
    def test_foreign_session(self): self.rows[14]["attributes"]["custom"]["session"]["id"] = "other"; self.reject()
    def test_missing_home_probe(self): del self.rows[1]["attributes"]["custom"]["context"]; self.reject()
    def test_foreign_home_run(self): self.rows[1]["attributes"]["custom"]["context"]["probe"]["run_id"] = "other"; self.reject()
    def test_missing_work_probe(self): del self.rows[6]["attributes"]["custom"]["context"]; self.reject()
    def test_foreign_work_run(self): self.rows[6]["attributes"]["custom"]["context"]["probe"]["run_id"] = "other"; self.reject()
    def test_wrong_work_owner(self): self.rows[6]["attributes"]["custom"]["view"]["id"] = "a1"; self.reject()
    def test_wrong_work_id(self): self.rows[6]["attributes"]["custom"]["action"]["id"] = "other"; self.reject()
    def test_wrong_phase(self): self.rows[6]["attributes"]["custom"]["context"]["probe"]["phase"] = "other"; self.reject()
    def test_wrong_scene(self): self.rows[6]["attributes"]["custom"]["context"]["probe"]["source_scene"] = "scene-A"; self.reject()
    def test_missing_work(self): self.rows.pop(6); self.reject()
    def test_extra_work(self):
        r = deepcopy(self.rows[6]); r["id"] = "extra"; self.rows.append(r); self.reject()
    def test_duplicate_view_identity(self):
        r = deepcopy(self.rows[0]); r["id"] = "extra"; self.rows.append(r); self.reject()
    def test_changed_view_name(self): self.rows[1]["attributes"]["custom"]["view"]["name"] = "other"; self.reject()
    def test_foreign_infrastructure_owner(self): self.rows[15]["attributes"]["custom"]["view"]["id"] = "other"; self.reject()
    def test_unqualified_vital(self): self.rows[15]["attributes"]["custom"]["vital"]["type"] = "operation"; self.reject()
    def test_wrong_vital_metric(self): self.rows[15]["attributes"]["custom"]["vital"]["app_launch_metric"] = "fbc"; self.reject()
    def test_error_row(self): self.rows[15]["attributes"]["custom"]["type"] = "error"; self.reject()
    def test_foreign_present_infrastructure_run(self):
        for index in [0, 14, 15]:
            with self.subTest(index=index):
                self.local, self.rows = fixture()
                self.rows[index]["attributes"]["custom"]["context"] = dict(probe=dict(run_id="other"))
                self.reject()
    def test_aggregate_cannot_claim_view(self): self.rows[14]["attributes"]["custom"]["view"] = dict(id="a1"); self.reject()

    def test_partial_inventory_waits_for_missing_work(self):
        self.rows.pop(6)
        result = inventory.validate(self.local, RUN, self.rows, len(self.rows), identity=IDENTITY, partial=True)
        self.assertEqual(result["state"], "PENDING")
        self.assertEqual(result["work_count"], 7)
    def test_empty_inventory_is_pending(self):
        self.assertEqual(inventory.validate(self.local, RUN, [], 0, identity=IDENTITY, partial=True)["state"], "PENDING")
    def test_partial_inventory_rejects_present_mismatch(self):
        self.rows.pop(6)
        self.rows[1]["attributes"]["custom"]["view"]["name"] = "other"
        with self.assertRaises(ValueError):
            inventory.validate(self.local, RUN, self.rows, len(self.rows), identity=IDENTITY, partial=True)
    def test_partial_inventory_requires_complete_raw_count(self):
        with self.assertRaises(ValueError):
            inventory.validate(self.local, RUN, self.rows, 15, identity=IDENTITY, partial=True)

    def long_task(self):
        row = deepcopy(self.rows[6]); row["id"] = "long-task"
        row["attributes"]["custom"]["type"] = "long_task"
        self.rows.append(row)
    def test_long_task_keeps_same_run_owner(self):
        self.long_task()
        self.assertEqual(self.grade()["raw_count"], 17)
    def test_long_task_missing_run_rejects(self):
        self.long_task(); del self.rows[-1]["attributes"]["custom"]["context"]; self.reject()
    def test_long_task_foreign_owner_rejects(self):
        self.long_task(); self.rows[-1]["attributes"]["custom"]["view"]["id"] = "other"; self.reject()


if __name__ == "__main__": unittest.main()
