"""Actual scope parser positives plus explicit synthetic Monitor grammar controls."""
import copy
import json
from pathlib import Path
import unittest
import default_off as oracle


SAVED = json.loads((Path(__file__).parent / "fixtures/default-off-scope-traces.json").read_text())["traces"]


def monitor_trace(scenario, revision):
    trace = copy.deepcopy(SAVED[scenario])
    publications = []
    for row in trace["rows"]:
        views = [(session, view) for session in row["sessions"] if session["active"]
                 for view in session["views"] if view["active"]]
        session = next((x for x in row["sessions"] if x["active"]), None)
        view = views[0][1] if views else None
        publication = ({"application": "routing-trace", "session": session["id"], "view": view["id"] if view else None,
                        "view_name": view["name"] if view else None} if session else {"cleared": True})
        publications.append(publication)
        row.update(owner_reads=0, event_context_writes=len(publications), publications=copy.deepcopy(publications),
                   active_view={"id": view["id"] if view else None, "name": view["name"] if view else None, "path": view["name"] if view else None})
        for key in oracle.MONITOR_STORAGE:
            row["dormant_state"][key] = {"present": revision != "pr3", "allocated": False}
    return trace


def public_trace(revision):
    """Constructed grammar control, not a captured Monitor/factory scenario."""
    trace = monitor_trace("navigation", revision)
    original = trace["rows"]
    groups = [original[:2], original[2:5], original[5:6], original[6:7], original[7:]]
    rows = []
    for phase, group in zip(oracle.PUBLIC_PHASES, groups):
        row = copy.deepcopy(group[-1])
        row["phase"] = phase
        row["events"] = [copy.deepcopy(e) for x in group for e in x["events"]]
        row["metadata"] = [copy.deepcopy(e) for x in group for e in x["metadata"]]
        rows.append(row)
    resource_trace = SAVED["retained-resource"]
    resource = next(copy.deepcopy(e) for row in resource_trace["rows"] for e in row["events"] if e["type"] == "resource")
    root = next(view for row in trace["rows"] for session in row["sessions"] for view in session["views"] if view["name"] == "root")
    resource["view"]["id"] = root["id"]
    resource["view"]["name"] = "root"
    rows[2]["events"].append(resource)
    rows[2]["metadata"].append({})
    trace.update(scenario=oracle.PUBLIC_SCENARIO, rows=rows)
    return trace


class DefaultOffTests(unittest.TestCase):
    def test_actual_scope_positives_are_unchanged(self):
        for trace in SAVED.values():
            self.assertEqual(oracle.validate(trace, "current"), trace)

    def test_constructed_monitor_grammar_for_all_eight_scope_scenarios(self):
        for name in SAVED:
            for before, after in [("pr3", "pr4"), ("pr4", "pr5")]:
                self.assertEqual(oracle.compare_monitor(monitor_trace(name, before), monitor_trace(name, after), before, after)["state"],
                                 "PASS_MONITOR_OFF_TRACE_ONLY")

    def test_owner_counter_and_each_optional_holder_are_decisive(self):
        a = monitor_trace("navigation", "pr3")
        b = monitor_trace("navigation", "pr4")
        for key in oracle.MONITOR_STORAGE:
            broken = copy.deepcopy(b)
            broken["rows"][1]["dormant_state"][key]["allocated"] = True
            self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["faults"], ["off-state-allocation"])
        b["rows"][1]["owner_reads"] = 1
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["off-owner-read"])

    def test_source_pair_and_holder_presence_cannot_be_normalized(self):
        a, b = monitor_trace("navigation", "pr3"), monitor_trace("navigation", "pr4")
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr5")["faults"], ["comparison-source-pair"])
        b["rows"][0]["dormant_state"]["monitor_snapshots"]["present"] = False
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["state-storage-presence"])

    def test_context_count_continuity_and_owner_binding(self):
        a, b = monitor_trace("navigation", "pr3"), monitor_trace("navigation", "pr4")
        broken = copy.deepcopy(b)
        broken["rows"][1]["event_context_writes"] += 1
        self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["faults"], ["context-publication-count"])
        broken = copy.deepcopy(b)
        broken["rows"][1]["publications"][0]["session"] = "foreign"
        self.assertNotEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["state"], "PASS_MONITOR_OFF_TRACE_ONLY")
        broken = copy.deepcopy(b)
        broken["rows"][1]["active_view"]["id"] = "foreign"
        self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["faults"], ["published-active-view"])

    def test_terminal_and_captured_effects_remain_decisive(self):
        a, b = monitor_trace("navigation", "pr3"), monitor_trace("navigation", "pr4")
        b["terminal"] = False
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["state"], "INCOMPLETE")
        b = monitor_trace("navigation", "pr4")
        error = next(e for row in b["rows"] for e in row["events"] if e["type"] == "error")
        error["view"]["id"] = "foreign"
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["event-owner"])
        b = monitor_trace("navigation", "pr4")
        b["rows"][-1]["callbacks"] = 0
        self.assertNotEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["state"], "PASS_MONITOR_OFF_TRACE_ONLY")

    def test_timing_fields_do_not_decide_off_semantics(self):
        a, b = monitor_trace("navigation", "pr3"), monitor_trace("navigation", "pr4")
        for row in b["rows"]:
            for event in row["events"]:
                event["date"] += 42
                if "view" in event and "time_spent" in event["view"]:
                    event["view"]["time_spent"] += 123
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["state"], "PASS_MONITOR_OFF_TRACE_ONLY")

    def test_malformed_counter_and_extra_observation_fail(self):
        a, b = monitor_trace("navigation", "pr3"), monitor_trace("navigation", "pr4")
        b["rows"][0]["owner_reads"] = False
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["off-owner-read"])
        b = monitor_trace("navigation", "pr4")
        b["rows"][0]["extra"] = "not-reviewed"
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["monitor-row-schema"])

    def test_constructed_public_grammar_passes(self):
        self.assertEqual(oracle.compare_monitor(public_trace("pr3"), public_trace("pr4"), "pr3", "pr4")["state"],
                         "PASS_MONITOR_OFF_TRACE_ONLY")

    def test_public_owner_metadata_phase_and_callback_controls(self):
        a, b = public_trace("pr3"), public_trace("pr4")
        broken = copy.deepcopy(b)
        resource = next(e for row in broken["rows"] for e in row["events"] if e["type"] == "resource")
        resource["session"]["id"] = "foreign"
        self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["faults"], ["event-owner"])
        broken = copy.deepcopy(b)
        broken["rows"][2]["metadata"].pop()
        self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["faults"], ["writer-inventory"])
        broken = copy.deepcopy(b)
        broken["rows"][2]["phase"] = "late-reconstructed"
        self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["state"], "INCOMPLETE")
        broken = copy.deepcopy(b)
        broken["rows"][-1]["pending_writer_completions"] = 1
        self.assertEqual(oracle.compare_monitor(a, broken, "pr3", "pr4")["faults"], ["public-completion"])

    def test_public_context_cannot_borrow_future_or_foreign_owner(self):
        a, b = public_trace("pr3"), public_trace("pr4")
        b["rows"][0]["publications"][0]["session"] = "foreign"
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["published-session-owner"])
        b = public_trace("pr4")
        b["rows"][0]["publications"][0]["view"] = "foreign"
        self.assertEqual(oracle.compare_monitor(a, b, "pr3", "pr4")["faults"], ["published-view-owner"])


if __name__ == "__main__":
    unittest.main()
