"""Documentation-only controls for generated release views and active links."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "release_checklist", Path(__file__).with_name("release_checklist.py"))
CHECKLIST = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKLIST)


class ReleaseChecklistTests(unittest.TestCase):
    def register(self):
        return {"candidate_revision": "revision", "gates": [{
            "id": "T01", "deliverable": "Target actions", "owner": "Implementer",
            "dependencies": [], "decisive_test": "Exact owner", "environment": "Simulator",
            "completion_mode": "explicit target", "status": "OPEN", "evidence": None}]}

    def release_register(self):
        register = self.register()
        register["releases"] = [
            {"id": "S1", "name": "Reliability", "deadline": "2026-10-01", "shipping_rule": "required gates closed"},
            {"id": "S2", "name": "No worse", "deadline": "2026-10-08", "shipping_rule": "required gates closed"},
            {"id": "S3", "name": "Release", "deadline": "2026-10-16", "shipping_rule": "required gates closed"},
        ]

        def gate(ident):
            return {
                "id": ident, "deliverable": ident + " deliverable", "owner": "Implementer",
                "dependencies": [], "decisive_test": "Reference test", "environment": "Simulator",
                "completion_mode": None, "status": "OPEN", "evidence": None,
            }

        register["gates"].extend([gate("C07"), gate("F01"), gate("F04"), gate("F09")])
        register["gates"][0]["release_requirements"] = {
            "S1": {"scope": "prepared single scene", "status": "CLOSED", "dependencies": [],
                   "decisive_test": "human session", "environment": "Duo", "evidence": "proof", "required": True}}
        register["gates"][1]["release_requirements"] = {
            "S2": {"scope": "candidate comparison", "status": "OPEN", "dependencies": [],
                   "decisive_test": "paired session", "environment": "Duo", "evidence": None, "required": True}}
        register["gates"][2]["release_requirements"] = {
            "S3": {"scope": "API review", "status": "OPEN", "dependencies": [],
                   "decisive_test": "review", "environment": "CI", "evidence": None, "required": True}}
        register["gates"][3]["release_requirements"] = {
            "S2": {"scope": "physical acceptance", "status": "OPEN", "dependencies": [],
                   "decisive_test": "device matrix", "environment": "Duo", "evidence": None, "required": False}}
        register["gates"][4]["release_requirements"] = {
            "S2": {"scope": "optional observation", "status": "CONDITIONAL", "dependencies": ["S2:C07"],
                   "decisive_test": "follow-up", "environment": "Duo", "evidence": None, "required": False}}
        return register

    def test_closed_gate_requires_evidence_and_known_dependencies(self):
        register = self.register()
        register["gates"][0]["status"] = "CLOSED"
        with self.assertRaisesRegex(ValueError, "closed without evidence"):
            CHECKLIST.validate(register)
        register["gates"][0]["evidence"] = "record"
        register["gates"][0]["dependencies"] = ["T99"]
        with self.assertRaisesRegex(ValueError, "unknown dependency"):
            CHECKLIST.validate(register)

    def test_duplicate_and_cyclic_gates_are_rejected(self):
        register = self.register()
        register["gates"].append(copy.deepcopy(register["gates"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate gate"):
            CHECKLIST.validate(register)
        register["gates"].pop()
        register["gates"][0]["dependencies"] = ["T01"]
        with self.assertRaisesRegex(ValueError, "dependency cycle"):
            CHECKLIST.validate(register)

    def test_progress_drift_is_rejected_independently_of_plan(self):
        register = self.register()
        expected = CHECKLIST.progress_document(register, CHECKLIST.validate(register))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "progress.json"
            path.write_text(json.dumps(expected))
            CHECKLIST.check_progress(path, expected)
            stale = copy.deepcopy(expected)
            stale["counts"]["OPEN"] = 0
            path.write_text(json.dumps(stale))
            with self.assertRaisesRegex(ValueError, "stale"):
                CHECKLIST.check_progress(path, expected)

    def test_release_schema_validates_instances_and_preserves_reference_progress(self):
        register = self.release_register()
        gates = CHECKLIST.validate(register)
        progress = CHECKLIST.progress_document(register, gates)
        self.assertEqual(progress["gate_count"], 5)
        self.assertEqual(progress["release_progress"]["S2"]["required"]["count"], 1)
        self.assertEqual(progress["release_progress"]["S2"]["required"]["remaining"][0]["id"], "S2:C07")
        self.assertIn(
            {"id": "S2:F09", "status": "CONDITIONAL", "owner": "Implementer", "dependencies": ["S2:C07"]},
            progress["release_progress"]["S2"]["optional_follow_ups"],
        )

    def test_release_schema_rejects_bad_proof_dependencies_cycles_and_stage_contamination(self):
        register = self.release_register()
        register["gates"][0]["release_requirements"]["S1"]["evidence"] = None
        with self.assertRaisesRegex(ValueError, "closed release requirement without evidence"):
            CHECKLIST.validate(register)

        register = self.release_register()
        register["gates"][1]["release_requirements"]["S2"]["dependencies"] = ["C07"]
        with self.assertRaisesRegex(ValueError, "fully qualified"):
            CHECKLIST.validate(register)

        register = self.release_register()
        register["gates"][1]["release_requirements"]["S2"]["dependencies"] = ["S2:F09"]
        with self.assertRaisesRegex(ValueError, "release dependency cycle"):
            CHECKLIST.validate(register)

        register = self.release_register()
        register["gates"][0]["release_requirements"]["S1"]["dependencies"] = ["S3:F01"]
        with self.assertRaisesRegex(ValueError, "S1/S2 cannot depend on S3"):
            CHECKLIST.validate(register)

    def test_release_schema_rejects_invalid_release_scope_and_f01_f04_violations(self):
        register = self.release_register()
        register["releases"].append(copy.deepcopy(register["releases"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate release"):
            CHECKLIST.validate(register)

        register = self.release_register()
        register["gates"][2]["release_requirements"] = {
            "S2": register["gates"][2]["release_requirements"]["S3"]}
        with self.assertRaisesRegex(ValueError, "F01 is S3-only"):
            CHECKLIST.validate(register)

        register = self.release_register()
        register["gates"][3]["release_requirements"]["S2"]["required"] = True
        with self.assertRaisesRegex(ValueError, "F04 cannot be required"):
            CHECKLIST.validate(register)

        register = self.release_register()
        register["gates"][1]["release_requirements"]["S2"]["dependencies"] = ["S2:F04"]
        with self.assertRaisesRegex(ValueError, "dependency on F04"):
            CHECKLIST.validate(register)

    def test_release_views_render_and_require_markers(self):
        register = self.release_register()
        gates = CHECKLIST.validate(register)
        progress = CHECKLIST.progress_document(register, gates)
        gate_rows = '\n'.join('| ' + gate_id + ' | stale |' for gate_id in gates)
        rendered = CHECKLIST.render_release_views(
            CHECKLIST.plan_rows(gate_rows + "\n<!-- release-views:start -->old<!-- release-views:end -->\n", gates), register, progress)
        self.assertIn("| S1 — Reliability | 2026-10-01 | required gates closed | 1 | 1 | 0 |", rendered)
        self.assertIn("### S2 release gates", rendered)
        self.assertIn("| S2:F09 | F09 deliverable: optional observation |", rendered)
        self.assertIn("follow-up · CONDITIONAL", rendered)
        rerendered = CHECKLIST.render_release_views(
            CHECKLIST.plan_rows(rendered, CHECKLIST.validate(register)), register,
            CHECKLIST.progress_document(register, CHECKLIST.validate(register)))
        self.assertEqual(rerendered, rendered)
        with self.assertRaisesRegex(ValueError, "marker pair"):
            CHECKLIST.render_release_views("no markers", register, progress)

    def test_release_specific_f06_plan_row_replaces_only_the_legacy_dependency_summary(self):
        register = self.release_register()
        register["gates"].append({
            "id": "F06", "deliverable": "Release freeze", "owner": "Maintainer",
            "dependencies": [], "decisive_test": "release review", "environment": "CI",
            "completion_mode": None, "status": "OPEN", "evidence": None,
            "release_requirements": {
                "S3": {"scope": "final release", "status": "OPEN", "dependencies": [],
                       "decisive_test": "release review", "environment": "CI", "evidence": None, "required": True},
            },
        })
        gates = CHECKLIST.validate(register)
        rendered = CHECKLIST.plan_rows('\n'.join('| ' + gate_id + ' | stale |' for gate_id in gates), gates)
        self.assertIn('| F06 | Release freeze | Maintainer | Release-specific dependencies below |', rendered)

    def test_active_documents_include_new_single_scene_and_human_acceptance_records(self):
        self.assertIn('DatadogRUM/MultiSceneSupport/DEFERRED_SINGLE_SCENE_EXTRACTION.md', CHECKLIST.ACTIVE_DOCUMENTS)
        self.assertIn('DatadogRUM/MultiSceneSupport/HUMAN_ACCEPTANCE.md', CHECKLIST.ACTIVE_DOCUMENTS)

    def test_generated_rows_include_evidence_and_reject_missing_or_duplicate_gate(self):
        register = self.register()
        register["gates"][0]["evidence"] = "frozen proof"
        gates = CHECKLIST.validate(register)
        rendered = CHECKLIST.plan_rows("| T01 | stale |\n", gates)
        self.assertIn("| OPEN | [register evidence](release-gates.json) |", rendered)
        with self.assertRaisesRegex(ValueError, "duplicate plan row"):
            CHECKLIST.plan_rows(rendered + rendered, gates)
        with self.assertRaisesRegex(ValueError, "gates missing"):
            CHECKLIST.plan_rows("", gates)

    def test_links_validate_fragments_and_ignore_inert_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "source.md").write_text(
                "[proof](target.md#accepted-owner)\n~~~~markdown\n[old](missing.md)\n~~~~\n")
            (root / "target.md").write_text("# Accepted owner\n")
            self.assertEqual(CHECKLIST.validate_links(root, ["source.md"]), 1)
            (root / "target.md").write_text("# Different heading\n")
            with self.assertRaisesRegex(ValueError, "missing heading"):
                CHECKLIST.validate_links(root, ["source.md"])
            (root / "target.md").unlink()
            with self.assertRaisesRegex(ValueError, "missing link target"):
                CHECKLIST.validate_links(root, ["source.md"])

    def test_index_and_restart_ownership_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in CHECKLIST.ACTIVE_DOCUMENTS:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("# Document\n")
            historical = root / "DatadogRUM/MultiSceneSupport/Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md"
            historical.parent.mkdir(parents=True, exist_ok=True)
            historical.write_text("# History\n")
            index = root / "DatadogRUM/MultiSceneSupport/EXPERIMENTS.md"
            row = '| <a id="exp-001"></a>EXP-001 | T01 | PASS | Owner matched | [record](PLAN.md) |\n'
            index.write_text(row)
            gates = CHECKLIST.validate(self.register())
            self.assertEqual(CHECKLIST.validate_documents(root, gates)["experiments"], 1)
            record = historical.with_name("EXP-001-099.md")
            record.write_text("## EXP-002 — Second experiment\n")
            with self.assertRaisesRegex(ValueError, "unique and contiguous"):
                CHECKLIST.validate_documents(root, gates)
            record.unlink()
            index.write_text("")
            with self.assertRaisesRegex(ValueError, "unique and contiguous"):
                CHECKLIST.validate_documents(root, gates)
            index.write_text(row + row)
            with self.assertRaisesRegex(ValueError, "unique and contiguous"):
                CHECKLIST.validate_documents(root, gates)
            index.write_text("## Current checkpoint\n" + row)
            with self.assertRaisesRegex(ValueError, "restart cursor"):
                CHECKLIST.validate_documents(root, gates)
            index.write_text(row)
            overview = root / "DatadogRUM/MULTI_SCENE_SUPPORT.md"
            overview.write_text("32/66 release gates closed\n")
            with self.assertRaisesRegex(ValueError, "gate totals"):
                CHECKLIST.validate_documents(root, gates)


if __name__ == "__main__":
    unittest.main()
