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

    def test_generated_rows_include_evidence_and_reject_missing_or_duplicate_gate(self):
        register = self.register()
        register["gates"][0]["evidence"] = "frozen proof"
        gates = CHECKLIST.validate(register)
        rendered = CHECKLIST.plan_rows("| T01 | stale |\n", gates)
        self.assertIn("| OPEN | frozen proof |", rendered)
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
