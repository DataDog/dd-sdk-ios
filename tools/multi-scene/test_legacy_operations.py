"""Offline fault-injection controls. Synthetic traces are never native evidence."""
from __future__ import annotations

import base64
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("legacy_operations", Path(__file__).with_name("legacy_operations.py"))
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


def rum_trace():
    scenarios = []
    for name, steps in oracle.RUM_STEPS.items():
        messages, raw = [], []
        views = {("session-1", "home-view"): {
            "type": "view", "application": {"id": "legacy-trace-application"},
            "session": {"id": "session-1"}, "view": {"id": "home-view", "name": "Home", "url": "home", "is_active": False},
        }}
        for index, (operation, key, step, reason, expected_message, attr) in enumerate(steps):
            session = "session-1"
            view = "home-view"
            if name == "off-view":
                view = oracle.NULL_VIEW if index < 2 else "background-view"
            elif name == "session-boundaries":
                session = "session-1" if index == 0 else "session-2" if index < 4 else "session-3"
                view = "home-view" if index == 0 else oracle.NULL_VIEW if index < 4 else "successor-view"
            if view != oracle.NULL_VIEW:
                view_name = "Background" if view == "background-view" else "Successor" if view == "successor-view" else "Home"
                views[(session, view)] = {
                    "type": "view", "application": {"id": "legacy-trace-application"},
                    "session": {"id": session}, "view": {"id": view, "name": view_name, "url": "Background" if view_name == "Background" else "successor" if view_name == "Successor" else "home", "is_active": False},
                }
            context = dict([attr]) if attr else {}
            vital = {"id": f"vital-{index}", "name": operation, "type": "operation_step", "step_type": step}
            if key is not None:
                vital["operation_key"] = key
            if reason is not None:
                vital["failure_reason"] = reason
            row = {
                "type": "vital", "date": (oracle.BASE_DATE + index) * 1000,
                "application": {"id": "legacy-trace-application"}, "session": {"id": session},
                "view": {"id": view, "url": "" if view == oracle.NULL_VIEW else views[(session, view)]["view"]["url"]}, "context": context,
                "vital": vital,
            }
            raw.append(row)
            if expected_message:
                attrs = {"application.id": "legacy-trace-application", "session.id": session}
                if view != oracle.NULL_VIEW:
                    attrs["view.id"] = [view]
                    attrs["view.name"] = [views[(session, view)]["view"]["name"]]
                messages.append({"type": "OperationMessage", "id": vital["id"], "name": operation,
                                 "key": key, "step": step, "date": oracle.BASE_DATE + index,
                                 "server_offset": 0, "attributes": attrs})
        raw.extend(views.values())
        callbacks = ["session-1", "nil"]
        if name == "session-boundaries":
            callbacks = ["session-1", "nil", "session-2", "session-3", "nil"]
        scenarios.append({"name": name, "terminal": True, "raw_events": raw,
                          "events": copy.deepcopy(raw), "messages": messages,
                          "session_callbacks": callbacks, "warnings": oracle.RUM_WARNINGS[name][:],
                          "errors": [], "provider_calls": 0})
    return {"schema_version": 1, "family": "legacy-operations", "terminal": True,
            "pid": 123, "loaded_images": ["/synthetic-control-only"], "scenarios": scenarios}


def profiling_trace():
    scenarios = []
    names = ["empty", "non-step", "completed", "ongoing", "default-background-stop",
             "continuous-non-step", "continuous-duration-events", "orphan-and-latest-start",
             "original-snapshot", "consent-regrant", "quota-regrant", "mixed-ongoing"]
    for name in names:
        inputs = copy.deepcopy(oracle.PROFILE_INPUTS[name])
        for row in inputs:
            if row["kind"] == "context":
                row["version"] = "later-version" if row["label"] == "later-context" else "original-version"
        checkpoints = []
        if name == "original-snapshot":
            checkpoints.extend([
                {"label": "before-mutation", "pending": 1, "written": 0, "status": "stopped",
                 "attributes": copy.deepcopy(oracle.ORIGINAL_ATTRIBUTES)},
                {"label": "before-release", "pending": 1, "written": 0, "status": "stopped",
                 "attributes": copy.deepcopy(oracle.LATER_ATTRIBUTES)},
            ])
        elif name in ("consent-regrant", "quota-regrant"):
            checkpoints.append({"label": "refused", "pending": 0, "written": 0,
                                "status": "stopped", "attributes": {}})
        profiles = []
        for identifiers in oracle.PROFILE_IDS[name]:
            # Preserve source grouping: unspecified vital dictionary order, then hang/task arrays.
            rows = [copy.deepcopy(oracle.EXPECTED_ATTACHMENT_ROWS[identifier]) for identifier in identifiers]
            vitals = [row for row in rows if row["type"] == "vital"]
            others = [row for row in rows if row["type"] != "vital"]
            rows = vitals + others
            event = {
                "family": "ios", "runtime": "ios", "version": "4", "start": 1, "end": 2,
                "attachments": ["profile.pprof", "rum-mobile-events.json"],
                "tags_profiler": "operation:custom,version:later-version" if name == "original-snapshot" else "operation:custom,version:original-version",
                **copy.deepcopy(oracle.ORIGINAL_ATTRIBUTES),
                "error.id": [row["id"] for row in rows if row["type"] == "error"],
                "long_task.id": [row["id"] for row in rows if row["type"] == "long_task"],
            }
            if vitals:
                event["vital.id"] = [row["id"] for row in vitals]
                event["vital.label"] = [row["name"] for row in vitals]
            profiles.append({"event": event, "rum_events": rows,
                             "pprof_base64": base64.b64encode(b"synthetic-control-not-native").decode()})
        checkpoints.append({"label": "terminal", "pending": 0, "written": len(profiles),
                            "status": "stopped", "attributes": copy.deepcopy(oracle.ORIGINAL_ATTRIBUTES)})
        scenarios.append({"name": name, "family": oracle.PROFILE_FAMILIES[name], "terminal": True,
                          "inputs": inputs, "checkpoints": checkpoints, "profiles": profiles,
                          "configured_background_eligibility": name in ("ongoing", "mixed-ongoing"),
                          "quota_inputs": ["quotaKO", "pending"] if name == "quota-regrant" else []})
    return {"schema_version": 1, "family": "legacy-profiling", "terminal": True,
            "pid": 123, "loaded_images": ["/synthetic-control-only"], "scenarios": scenarios}


def scenario(trace, name):
    return next(row for row in trace["scenarios"] if row["name"] == name)


class LegacyTraceOracleControls(unittest.TestCase):
    def assert_rejected(self, original, change, fault=None):
        altered = copy.deepcopy(original)
        change(altered)
        result = oracle.compare(original, altered)
        self.assertNotEqual(result["verdict"], "PASS")
        self.assertEqual(result["gates_closed"], [])
        if fault is not None:
            self.assertEqual(result["faults"], [fault])

    def test_valid_examples_give_component_credit_only(self):
        for trace in (rum_trace(), profiling_trace()):
            with self.subTest(family=trace["family"]):
                result = oracle.compare(trace, trace)
                self.assertEqual(result["verdict"], "PASS")
                self.assertEqual(result["scope"], "FINITE_COMPONENT_ORACLE_ONLY")
                self.assertEqual(result["gates_closed"], [])

    def test_missing_terminal_is_incomplete(self):
        for trace in (rum_trace(), profiling_trace()):
            for mutate in (
                lambda t: t.pop("terminal"),
                lambda t: t["scenarios"][0].pop("terminal"),
            ):
                with self.subTest(family=trace["family"]):
                    altered = copy.deepcopy(trace)
                    mutate(altered)
                    self.assertEqual(oracle.compare(trace, altered)["verdict"], "INCOMPLETE")

    def test_missing_or_extra_scenario_is_rejected(self):
        for trace in (rum_trace(), profiling_trace()):
            for mutate in (lambda t: t["scenarios"].pop(), lambda t: t["scenarios"].append(t["scenarios"][0])):
                with self.subTest(family=trace["family"]):
                    self.assert_rejected(trace, mutate, "scenario-inventory")

    def test_missing_actual_image_or_process_inventory_is_rejected(self):
        for trace in (rum_trace(), profiling_trace()):
            for mutate, fault in ((lambda t: t.update(pid=0), "actual-process"),
                                  (lambda t: t.update(loaded_images=[]), "loaded-images")):
                with self.subTest(family=trace["family"]):
                    self.assert_rejected(trace, mutate, fault)

    def test_rum_lost_duplicate_or_foreign_bus_message_is_rejected(self):
        original = rum_trace()
        for mutate, fault in (
            (lambda t: t["scenarios"][0]["messages"].pop(), "message-count"),
            (lambda t: t["scenarios"][0]["messages"].append(t["scenarios"][0]["messages"][0]), "message-count"),
            (lambda t: t["scenarios"][0]["messages"][0].update(type="OwnedOperationMessage"), "legacy-message-type"),
            (lambda t: t["scenarios"][0]["messages"][0].update(id="foreign"), "message-vital-join"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(original, mutate, fault)

    def test_rum_sampled_out_start_must_not_gain_message(self):
        original = rum_trace()
        self.assert_rejected(original, lambda t: scenario(t, "profiling-options")["messages"].append(
            copy.deepcopy(t["scenarios"][0]["messages"][0])), "message-count")

    def test_rum_lost_event_wrong_key_failure_and_command_attributes_are_rejected(self):
        for mutate, fault in (
            (lambda t: t["scenarios"][0]["raw_events"].pop(0), "vital-count"),
            (lambda t: t["scenarios"][0]["raw_events"][0]["vital"].update(operation_key="foreign"), "vital-step-key-reason"),
            (lambda t: scenario(t, "failure")["raw_events"][1]["vital"].update(failure_reason="other"), "vital-step-key-reason"),
            (lambda t: t["scenarios"][0]["raw_events"][0]["context"].clear(), "command-attributes"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(rum_trace(), mutate, fault)

    def test_rum_foreign_correlation_and_null_vs_empty_are_rejected(self):
        for mutate, fault in (
            (lambda t: t["scenarios"][0]["messages"][0]["attributes"].update({"session.id": "foreign"}), "message-session-owner"),
            (lambda t: t["scenarios"][0]["messages"][0]["attributes"].update({"view.id": ["foreign"]}), "message-view-owner"),
            (lambda t: scenario(t, "off-view")["messages"][0]["attributes"].update({"view.id": []}), "null-view-message-owner"),
            (lambda t: scenario(t, "off-view")["messages"][0]["attributes"].update({"view.name": []}), "null-view-message-owner"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(rum_trace(), mutate, fault)

    def test_rum_warning_callback_and_provider_differences_are_rejected(self):
        for mutate, fault in (
            (lambda t: scenario(t, "legacy-key-collision")["warnings"].clear(), "warning-inventory"),
            (lambda t: t["scenarios"][0]["session_callbacks"].append("nil"), "session-callbacks"),
            (lambda t: t["scenarios"][0].update(provider_calls=1), "owned-provider-reached"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(rum_trace(), mutate, fault)

    def test_final_stop_warning_is_required_once_for_each_ordinary_scenario(self):
        for name in oracle.FINAL_STOP_OFFSETS:
            for mutation in (lambda rows: rows.pop(), lambda rows: rows.append(rows[-1])):
                with self.subTest(name=name, mutation=mutation):
                    self.assert_rejected(rum_trace(), lambda t: mutation(scenario(t, name)["warnings"]),
                                         "warning-inventory")

    def test_final_stop_warning_fields_and_controlled_clock_are_strict(self):
        replacements = (
            ("RUMStopViewCommand", "RUMStartViewCommand"),
            ("processRepresentative", "foreignTarget"),
            ('key("successor")', 'key("home")'),
            ("2023-11-14", "2023-11-15"),
            ("globalAttributes: [:]", "globalAttributes: [foreign: true]"),
            ("canStartBackgroundView: false", "canStartBackgroundView: true"),
            ("missedEventType: nil", "missedEventType: foreign"),
        )
        for name in oracle.FINAL_STOP_OFFSETS:
            for old, new in replacements:
                with self.subTest(name=name, field=old):
                    def change(t):
                        warnings = scenario(t, name)["warnings"]
                        self.assertIn(old, warnings[-1])
                        warnings[-1] = warnings[-1].replace(old, new)
                    self.assert_rejected(rum_trace(), change, "warning-inventory")

    def test_final_stop_does_not_replace_or_reorder_operation_warnings(self):
        for name in ("duplicate-and-orphan", "legacy-key-collision"):
            for mutation in (lambda rows: rows.pop(0), lambda rows: rows.reverse()):
                with self.subTest(name=name, mutation=mutation):
                    self.assert_rejected(rum_trace(), lambda t: mutation(scenario(t, name)["warnings"]),
                                         "warning-inventory")

    def test_final_stop_warning_does_not_extend_other_scenarios(self):
        for name in ("off-view", "session-boundaries"):
            with self.subTest(name=name):
                self.assert_rejected(rum_trace(), lambda t: scenario(t, name)["warnings"].append(
                    oracle.RUM_WARNINGS["success"][-1]), "warning-inventory")

    def test_rum_wire_and_message_consistently_foreign_view_is_rejected(self):
        original = rum_trace()
        def change(t):
            s = scenario(t, "off-view")
            for index in (2, 3):
                s["raw_events"][index]["view"]["id"] = "foreign-view"
                s["messages"][index]["attributes"]["view.id"] = ["foreign-view"]
        self.assert_rejected(original, change, "vital-view-inventory-join")

    def test_raw_inventory_not_filtered_projection_decides(self):
        original = rum_trace()
        def change(t):
            t["scenarios"][0]["raw_events"][0]["service"] = "new-service"
        self.assert_rejected(original, change, "semantic-source-pair-difference")

    def test_wrong_message_name_or_matched_view_pane_is_rejected(self):
        self.assert_rejected(rum_trace(), lambda t: t["scenarios"][0]["messages"][0]["attributes"].update(
            {"view.name": ["Wrong pane"]}), "message-view-name")
        def wrong_matched_view(t):
            t["scenarios"][0]["raw_events"][-1]["view"]["name"] = "Wrong pane"
            t["scenarios"][0]["raw_events"].append({
                "type": "view", "application": {"id": "legacy-trace-application"},
                "session": {"id": "session-1"}, "view": {"id": "unrelated", "name": "Home", "url": "home"}})
        self.assert_rejected(rum_trace(), wrong_matched_view, "vital-view-inventory-join")

    def test_attachment_group_order_cannot_be_normalized_away(self):
        def change(t):
            rows = scenario(t, "original-snapshot")["profiles"][0]["rum_events"]
            rows.insert(0, rows.pop(2))
        self.assert_rejected(profiling_trace(), change, "attachment-group-order")

    def test_stale_projection_receipt_is_rejected(self):
        self.assert_rejected(rum_trace(), lambda t: t["scenarios"][0]["events"][0]["view"].update(
            id="older-matching-observation"), "projection-receipt")

    def test_view_timing_changes_are_diagnostic(self):
        original = rum_trace()
        altered = copy.deepcopy(original)
        altered["scenarios"][0]["raw_events"][-1]["view"]["time_spent"] = 1.234567891
        altered["scenarios"][0]["events"][-1]["view"]["time_spent"] = 1.234567891
        self.assertEqual(oracle.compare(original, altered)["verdict"], "PASS")

    def test_missing_or_extra_profile_and_attachment_are_rejected(self):
        for mutate, fault in (
            (lambda t: scenario(t, "completed")["profiles"].clear(), "profile-count"),
            (lambda t: scenario(t, "completed")["profiles"].append(scenario(t, "completed")["profiles"][0]), "profile-count"),
            (lambda t: scenario(t, "original-snapshot")["profiles"][0]["rum_events"].pop(), "profile-attachment-ids"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(profiling_trace(), mutate, fault)

    def test_consistently_corrupted_attachment_label_time_duration_is_rejected(self):
        for field, value in (("name", "corrupt"), ("start_ns", 123), ("duration_ns", 123)):
            def change(t, field=field, value=value):
                profile = scenario(t, "completed")["profiles"][0]
                profile["rum_events"][0][field] = value
                if field == "name":
                    profile["event"]["vital.label"][0] = value
            with self.subTest(field=field):
                self.assert_rejected(profiling_trace(), change, "attachment-fields")

    def test_later_owner_or_attachments_must_not_replace_original_snapshot(self):
        for mutate, fault in (
            (lambda t: scenario(t, "original-snapshot")["profiles"][0]["event"].update({"session.id": "later-session"}), "profile-session-owner"),
            (lambda t: scenario(t, "original-snapshot")["profiles"][0]["event"].update({"fixture-attribute": "later"}), "profile-snapshot-attributes"),
            (lambda t: scenario(t, "original-snapshot")["profiles"][0]["rum_events"][0].update(id="later-non-step"), "profile-attachment-ids"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(profiling_trace(), mutate, fault)

    def test_joined_labels_and_duration_event_owners_are_checked(self):
        for mutate, fault in (
            (lambda t: scenario(t, "completed")["profiles"][0]["event"].update({"vital.label": ["wrong"]}), "profile-vital-label-join"),
            (lambda t: scenario(t, "continuous-duration-events")["profiles"][0]["event"].update({"error.id": ["wrong"]}), "duration-event-joins"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(profiling_trace(), mutate, fault)

    def test_profile_input_keys_steps_and_consumption_are_independent(self):
        for field, value in (("key", "wrong"), ("step", "end"), ("date", 123)):
            def change(t, field=field, value=value):
                scenario(t, "completed")["inputs"][1]["vital"][field] = value
            with self.subTest(field=field):
                self.assert_rejected(profiling_trace(), change, "message-input-fields")
        self.assert_rejected(profiling_trace(), lambda t: scenario(t, "completed")["inputs"][1].update(consumed=True),
                             "message-input-fields")

    def test_missing_mutation_or_early_release_is_rejected(self):
        for mutate, fault in (
            (lambda t: scenario(t, "original-snapshot")["checkpoints"][1].update(attributes=oracle.ORIGINAL_ATTRIBUTES),
             "mutation-not-observed"),
            (lambda t: scenario(t, "original-snapshot")["checkpoints"][1].update(written=1),
             "deferred-boundary"),
        ):
            with self.subTest(fault=fault):
                self.assert_rejected(profiling_trace(), mutate, fault)

    def test_configured_background_does_not_certify_default(self):
        self.assert_rejected(profiling_trace(), lambda t: scenario(t, "default-background-stop").update(
            configured_background_eligibility=True), "background-conditions")

    def test_unordered_vitals_keep_id_label_and_attachment_joins(self):
        original = profiling_trace()
        altered = copy.deepcopy(original)
        profile = scenario(altered, "original-snapshot")["profiles"][0]
        profile["rum_events"][:2] = reversed(profile["rum_events"][:2])
        profile["event"]["vital.id"].reverse()
        profile["event"]["vital.label"].reverse()
        self.assertEqual(oracle.compare(original, altered)["verdict"], "PASS")
        profile["event"]["vital.label"].reverse()
        self.assertEqual(oracle.compare(original, altered)["faults"], ["profile-vital-label-join"])

    def test_duplicate_vitals_are_not_erased_by_multiset_comparison(self):
        self.assert_rejected(profiling_trace(), lambda t: scenario(t, "completed")["profiles"][0]["rum_events"].append(
            scenario(t, "completed")["profiles"][0]["rum_events"][0]), "profile-attachment-ids")

    def test_missing_empty_or_corrupt_native_payload_is_rejected(self):
        for value, fault in (("", "pprof-empty"), ("???", "pprof-encoding")):
            with self.subTest(value=value):
                self.assert_rejected(profiling_trace(), lambda t: scenario(t, "completed")["profiles"][0].update(
                    pprof_base64=value), fault)

    def test_native_timing_samples_and_distinct_processes_are_diagnostic(self):
        original = profiling_trace()
        altered = copy.deepcopy(original)
        altered["pid"] = 124
        altered["loaded_images"] = ["/different-bound-product"]
        p = scenario(altered, "completed")["profiles"][0]
        p["event"]["start"] = 1.0000000001
        p["event"]["end"] = 22
        p["pprof_base64"] = base64.b64encode(b"other-samples-not-native-evidence").decode()
        self.assertEqual(oracle.compare(original, altered)["verdict"], "PASS")

    def test_late_writer_context_must_be_observed(self):
        self.assert_rejected(profiling_trace(), lambda t: scenario(t, "original-snapshot")["profiles"][0]["event"].update(
            tags_profiler="version:original-version"), "deferred-current-context")


if __name__ == "__main__":
    unittest.main()
