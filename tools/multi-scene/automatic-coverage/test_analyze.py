import copy
import unittest
import analyze


def input_fixture():
    """Synthetic oracle control, never a native acceptance artifact."""
    run = {"run_id": "unit-control", "framework": "UIKit", "layout": "stack", "poses": False,
           "clean_install": True, "cleanup": True, "test_exit": 0,
           "installed": {"UIKit": {"binaries": {"Fixture": "unit-hash"}}}}
    rows = []; receipts = []
    def row(kind, payload, time):
        rows.append({"run_id": run["run_id"], "sequence": len(rows)+1, "timestamp": time, "kind": kind, "payload": payload})
    def receipt(phase, time, payload=None):
        receipts.append({"run_id": run["run_id"], "phase": phase, "timestamp": time, "payload": payload or {}})
    receipt("launch", 0)
    row("launch", {"framework": "UIKit", "layout": "stack", "multiple_scenes": False}, 0)
    row("geometry", {"scenes": []}, 0.1)
    stages = ["root.tap", "root.toggle", "root.scroll", "navigate", "detail.tap", "detail.toggle", "detail.scroll", "present",
              "sheet.tap", "dismiss", "detail.return.tap", "back", "root.return.tap"]
    for i, stage in enumerate(stages, 1):
        target = stage if stage.endswith(("tap", "toggle")) else ""
        receipt("initial."+stage+".before", i, {"target": target})
        if target: row("native_input", {"name": target}, i+0.1)
        receipt("initial."+stage+".delivered", i+0.2)
        receipt("initial."+stage+".effect", i+0.3)
    receipt("background.before", 14); row("native_background", {}, 14.1)
    receipt("background.effect", 14.2); receipt("complete", 15); receipt("terminated", 16)
    return run, rows, receipts, {"passedTests": 1, "failedTests": 0}


class InputQualificationTests(unittest.TestCase):
    def test_complete_native_control(self):
        analyze.qualify(*input_fixture())

    def rejects(self, mutate):
        values = input_fixture(); mutate(*values)
        with self.assertRaises(ValueError): analyze.qualify(*values)

    def test_stale_run(self): self.rejects(lambda run,rows,receipts,s: rows[0].update(run_id="old"))
    def test_missing_sequence(self): self.rejects(lambda run,rows,receipts,s: rows[2].update(sequence=99))
    def test_no_clean_install(self): self.rejects(lambda run,rows,receipts,s: run.update(clean_install=False))
    def test_no_cleanup(self): self.rejects(lambda run,rows,receipts,s: run.update(cleanup=False))
    def test_failed_ui_test(self): self.rejects(lambda run,rows,receipts,s: s.update(passedTests=0,failedTests=1))
    def test_wrong_framework(self): self.rejects(lambda run,rows,receipts,s: rows[0]["payload"].update(framework="SwiftUI"))
    def test_multiscene_fixture(self): self.rejects(lambda run,rows,receipts,s: rows[0]["payload"].update(multiple_scenes=True))
    def test_missing_installed_identity(self): self.rejects(lambda run,rows,receipts,s: run.update(installed={}))
    def test_missing_native_outcome(self): self.rejects(lambda run,rows,receipts,s: rows[2]["payload"].update(name="other"))
    def test_missing_background_flush(self): self.rejects(lambda run,rows,receipts,s: rows[-1].update(kind="not-background"))
    def test_stale_background(self): self.rejects(lambda run,rows,receipts,s: rows[-1].update(timestamp=0))
    def test_missing_terminal_receipt(self): self.rejects(lambda run,rows,receipts,s: receipts.pop())
    def test_late_assertion(self): self.rejects(lambda run,rows,receipts,s: receipts[1].update(timestamp=100))
    def test_duplicate_native_callback(self):
        def mutate(run, rows, receipts, summary):
            duplicate=copy.deepcopy(rows[2]); duplicate["sequence"]=len(rows)+1; rows.append(duplicate)
        self.rejects(mutate)
    def test_missing_pose_receipt(self): self.rejects(lambda run,rows,receipts,s: run.update(poses=True))


class ComparisonTests(unittest.TestCase):
    def sample(self):
        run={"run_id":"unit-comparison","build":"candidate-27.1","device":"regular","framework":"UIKit","layout":"stack"}
        rows=[{"kind":"rum","payload":{"type":"view","date":1000,"view":{"id":"home","name":"Home","url":"Home"}}},
              {"kind":"rum","payload":{"type":"view","date":3000,"view":{"id":"detail","name":"Detail","url":"Detail"}}},
              {"kind":"rum","payload":{"type":"action","date":2100,"view":{"id":"home"},"action":{"id":"tap","type":"tap","target":{"name":"Open detail"}}}}]
        receipts=[{"phase":"initial.navigate.before","timestamp":2},{"phase":"complete","timestamp":4}]
        return run, rows, receipts
    def test_same_sample_is_unchanged(self):
        value=analyze.summarize(*self.sample())
        self.assertEqual(analyze.compare(value,value,"actions")["status"],"UNCHANGED_OBSERVED_COVERAGE")
    def test_wrong_existing_owner_cannot_pass(self):
        args=self.sample();before=analyze.summarize(*args);args[1][2]["payload"]["view"]["id"]="detail"
        self.assertEqual(analyze.compare(before,analyze.summarize(*args),"actions")["status"],"DIFFERENCE_REQUIRES_CLASSIFICATION")
    def test_missing_action_cannot_pass(self):
        args=self.sample();before=analyze.summarize(*args);args[1].pop()
        self.assertEqual(analyze.compare(before,analyze.summarize(*args),"actions")["status"],"DIFFERENCE_REQUIRES_CLASSIFICATION")
    def test_duplicate_action_cannot_pass(self):
        args=self.sample();before=analyze.summarize(*args);args[1].append(copy.deepcopy(args[1][2]))
        self.assertEqual(analyze.compare(before,analyze.summarize(*args),"actions")["status"],"REVIEW_REQUIRED")
    def test_unresolved_owner_cannot_pass(self):
        args=self.sample();before=analyze.summarize(*args);args[1][2]["payload"]["view"]["id"]="foreign"
        self.assertEqual(analyze.compare(before,analyze.summarize(*args),"actions")["status"],"REVIEW_REQUIRED")
    def test_view_name_change_cannot_pass(self):
        args=self.sample();before=analyze.summarize(*args);args[1][1]["payload"]["view"]["name"]="Unexpected"
        self.assertEqual(analyze.compare(before,analyze.summarize(*args),"views")["status"],"DIFFERENCE_REQUIRES_CLASSIFICATION")
    def test_custom_marker_cannot_count_as_automatic(self):
        args=self.sample();args[1][2]["payload"]["action"]["type"]="custom"
        with self.assertRaises(ValueError): analyze.summarize(*args)
    def test_unchanged_missing_action_is_labeled_limitation(self):
        args=self.sample();args[1].pop();value=analyze.summarize(*args)
        self.assertEqual(analyze.compare(value,value,"actions")["status"],"UNCHANGED_LIMITATION")

class ExternalHomeTests(unittest.TestCase):
    def fixture(self):
        return ([{"phase":"background.before","timestamp":1}, {"phase":"await-home","timestamp":2},
                 {"phase":"received-home","timestamp":5,"payload":{"run_id":"home-control","command_id":"fresh-command",
                  "native_background_sequence":10,"observed_at":4}}], [{"sequence":10,"timestamp":3}], "home-control")
    def test_actual_native_boundary(self): analyze.qualify_home(*self.fixture())
    def rejects(self, mutate):
        receipts, rows, ident = self.fixture(); mutate(receipts, rows)
        with self.assertRaises(ValueError): analyze.qualify_home(receipts, rows, ident)
    def test_old_run(self): self.rejects(lambda r,b: r[-1]["payload"].update(run_id="old"))
    def test_missing_command_identity(self): self.rejects(lambda r,b: r[-1]["payload"].pop("command_id"))
    def test_unknown_native_sequence(self): self.rejects(lambda r,b: r[-1]["payload"].update(native_background_sequence=9))
    def test_native_boundary_before_wait(self): self.rejects(lambda r,b: b[0].update(timestamp=1.5))
    def test_native_boundary_after_observation(self): self.rejects(lambda r,b: b[0].update(timestamp=4.5))
    def test_observation_after_receipt(self): self.rejects(lambda r,b: r[-1]["payload"].update(observed_at=6))
    def test_missing_wait(self): self.rejects(lambda r,b: r.pop(1))

class ManifestIdentityTests(unittest.TestCase):
    def fixture(self):
        metadata = {fw: {"declared_multiple_scenes": True, "info_sha256": fw + "-hash"} for fw in ["UIKit", "SwiftUI"]}
        run = {"declared_multiple_scenes": True, "built_app_metadata": metadata,
               "installed_app_metadata": copy.deepcopy(metadata), "app_metadata_after_test": copy.deepcopy(metadata)}
        rows = [{"kind": "geometry", "payload": {"scenes": [{"id": "one"}]}}]
        return run, rows, {"multiple_scenes": False}
    def test_manifest_and_native_capability_are_distinct(self): analyze.qualify_manifest(*self.fixture())
    def test_native_capability_true_with_one_scene_is_valid(self):
        run, rows, launch = self.fixture(); launch["multiple_scenes"] = True
        analyze.qualify_manifest(run, rows, launch)
    def rejects(self, change):
        args = self.fixture(); change(*args)
        with self.assertRaises(ValueError): analyze.qualify_manifest(*args)
    def test_missing_manifest_inventory(self): self.rejects(lambda r,g,l: r.pop("built_app_metadata"))
    def test_changed_install_manifest(self): self.rejects(lambda r,g,l: r["installed_app_metadata"]["UIKit"].update(info_sha256="wrong"))
    def test_manifest_changed_during_test(self): self.rejects(lambda r,g,l: r["app_metadata_after_test"]["SwiftUI"].update(declared_multiple_scenes=False))
    def test_second_native_scene(self): self.rejects(lambda r,g,l: g[0]["payload"]["scenes"].append({"id":"two"}))
    def test_no_native_scene(self): self.rejects(lambda r,g,l: g[0]["payload"].update(scenes=[]))
    def test_missing_capability_observation(self): self.rejects(lambda r,g,l: l.clear())

if __name__ == "__main__": unittest.main()
