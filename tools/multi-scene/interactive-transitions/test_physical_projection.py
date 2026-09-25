"""Offline projection controls retain terminal and ownership discriminators."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import physical_projection as projection
import test_journey_transport as transport_fixtures
from capture_io import encoded
from acceptance_common import Rejected
import test_runtime_contract as fixtures


class Projection(unittest.TestCase):
    def setUp(self):
        self.local = fixtures.o.inventory(fixtures.stream(), fixtures.IDENTITY)
        for value in self.local["accepted"].values():
            event = value["event"]
            if event["type"] == "view":
                event["view"]["time_spent"] = 100 if event["view"]["is_active"] else 1000
                event["view"]["custom_timings"] = {}
                event["feature_flags"] = {}
                event["_dd"]["replay_stats"] = {}
        self.rows = fixtures.backend_rows(self.local)
        self.view = next(r for r in self.rows if r["attributes"]["custom"]["type"] == "view")

    def assess(self, rows=None):
        rows = self.rows if rows is None else rows
        return projection.assess(rows, rows, self.local, fixtures.EXPECTED)

    def test_exact_projection_has_no_runtime_or_release_authority(self):
        result = self.assess()
        self.assertEqual(result["qualification"], "OFFLINE_ONLY")
        self.assertFalse(result["runtime_acceptance"])
        self.assertFalse(result["release_acceptance"])
        self.assertEqual(result["gate_closures"], [])

    def test_only_three_named_empty_objects_and_independent_revisions_are_classified(self):
        payload = self.view["attributes"]["custom"]
        del payload["_dd"]["replay_stats"], payload["feature_flags"], payload["view"]["custom_timings"]
        payload["_dd"]["document_version"] = 7
        original = copy.deepcopy(self.rows)
        result = self.assess()
        self.assertEqual(result["qualification"], "OFFLINE_ONLY")
        changes = next(r["differences"] for r in result["comparisons"] if r["event"][0] == "view")
        self.assertEqual({v["path"] for v in changes}, projection.EMPTY_VIEW_OBJECTS | {"_dd.document_version"})
        self.assertEqual(self.rows, original)
        with self.assertRaises(Rejected): fixtures.b.join(self.rows, self.rows, self.local, fixtures.EXPECTED)

    def test_nonempty_empty_null_and_foreign_omissions_remain_unqualified(self):
        submitted = {"_dd": {"replay_stats": {"records_count": 1}}, "custom": {}}
        result = projection.differences({}, submitted, view=True)
        self.assertTrue(all(v["disposition"] == "UNRESOLVED_OMISSION" for v in result))
        for value in [None, [], False, 0]:
            with self.subTest(value=value):
                result = projection.differences({"_dd": {"replay_stats": value}}, {"_dd": {"replay_stats": {}}}, view=True)
                self.assertEqual(result[0]["disposition"], "UNRESOLVED_VALUE")
        nonempty = projection.differences({"_dd": {}}, {"_dd": {"replay_stats": {"records_count": 1}}}, view=True)
        self.assertEqual(nonempty[0]["disposition"], "UNRESOLVED_OMISSION")
        changes = projection.differences({"_dd": {}}, {"_dd": {"replay_stats": {}}}, view=False)
        self.assertEqual(changes[0]["disposition"], "UNRESOLVED_OMISSION")

    def test_stale_terminal_cannot_be_rescued_by_omission_projection(self):
        payload = self.view["attributes"]["custom"]
        del payload["_dd"]["replay_stats"]
        payload["view"].update(is_active=True, time_spent=1)
        result = self.assess()
        self.assertEqual(result["qualification"], "UNQUALIFIED")
        self.assertEqual({v["path"] for v in result["terminal_failures"]}, {"view.is_active", "view.time_spent"})

    def test_same_shape_wrong_name_duration_date_count_or_tags_never_passes(self):
        for path, value in [("view.name", "foreign"), ("view.time_spent", 1001), ("view.action.count", 0)]:
            rows = copy.deepcopy(self.rows)
            view = next(r for r in rows if r["attributes"]["custom"]["type"] == "view")
            target = view["attributes"]["custom"]
            for key in path.split(".")[:-1]: target = target[key]
            target[path.split(".")[-1]] = value
            with self.subTest(path=path): self.assertEqual(self.assess(rows)["qualification"], "UNQUALIFIED")
        rows = copy.deepcopy(self.rows); rows[0]["attributes"]["client_time"] += 1
        self.assertEqual(self.assess(rows)["qualification"], "UNQUALIFIED")
        rows = copy.deepcopy(self.rows); rows[0]["attributes"]["tags"] = []
        with self.assertRaises(Rejected): self.assess(rows)

    def test_unsupported_session_flags_and_brightness_are_not_defaulted(self):
        for value in self.local["views"].values():
            value["event"]["session"].update(has_replay=False, is_active=True)
            value["event"]["device"] = dict(type="tablet", brightness_level=.5)
        self.view["attributes"]["custom"]["device"] = dict(type="Tablet", brightness_level=.6)
        result = self.assess()
        self.assertEqual(result["qualification"], "UNQUALIFIED")
        self.assertTrue({"session.has_replay", "session.is_active", "device.brightness_level"}
                        <= {v["path"] for v in result["unresolved"]})

    def session_projection(self):
        for value in self.local["views"].values():
            value["event"]["session"].update(has_replay=False, is_active=True)
            value["event"]["_dd"]["session"] = dict(session_precondition="user_app_launch")
        payload = self.view["attributes"]["custom"]
        payload["_dd"]["session"] = {}
        reducer = self.rows[-1]["attributes"]["custom"]
        reducer["session"].update(has_replay=False, is_active=True)
        reducer["_dd"]["session"] = dict(session_precondition="user_app_launch")
        return reducer

    def test_session_omissions_require_exact_reducer_and_preserve_raw_rows(self):
        self.session_projection()
        before = copy.deepcopy(self.rows)
        result = self.assess()
        self.assertEqual(result["qualification"], "OFFLINE_ONLY")
        row = next(c for c in result["comparisons"] if c["event"][0] == "view")
        self.assertEqual(row["session_reducer_raw_id"], "session")
        changes = [c for c in row["differences"] if c["disposition"] == "SESSION_REDUCER_MATCHED"]
        self.assertEqual({c["path"] for c in changes}, set(projection.SESSION_FIELDS))
        self.assertTrue(all(c["actual_present"] is False and type(c["reducer_actual"]) is type(c["submitted"])
                            and c["reducer_actual"] == c["submitted"] for c in changes))
        self.assertEqual(self.rows, before)
        with self.assertRaises(Rejected): fixtures.b.join(self.rows, self.rows, self.local, fixtures.EXPECTED)

    def test_missing_changed_or_wrong_type_session_witness_remains_unresolved(self):
        reducer = self.session_projection()
        for path, alternatives in [("session.has_replay", [None, 0, True]),
                                   ("session.is_active", [None, 1, False]),
                                   ("_dd.session.session_precondition", [None, False, "explicit_stop"])]:
            target = reducer
            for part in path.split(".")[:-1]: target = target[part]
            key = path.split(".")[-1]; original = target[key]
            for value in alternatives:
                if value is None: target.pop(key, None)
                else: target[key] = value
                with self.subTest(path=path, value=value):
                    result = self.assess()
                    self.assertEqual(result["qualification"], "UNQUALIFIED")
                    self.assertIn(path, {c["path"] for c in result["unresolved"]})
            target[key] = original
        self.assertEqual(self.assess(self.rows[:-1])["qualification"], "UNQUALIFIED")

    def test_foreign_or_duplicate_reducer_cannot_supply_omitted_values(self):
        reducer = self.session_projection()
        for part in ["session", "application"]:
            original = reducer[part]["id"]; reducer[part]["id"] = fixtures.uid(99)
            with self.subTest(part=part), self.assertRaises(Rejected): self.assess()
            reducer[part]["id"] = original
        extra = copy.deepcopy(self.rows[-1]); extra["id"] = "extra-reducer"
        with self.assertRaises(Rejected): self.assess(self.rows + [extra])

    def test_projection_does_not_hide_present_wrong_session_fields_or_apply_to_actions(self):
        reducer = self.session_projection()
        self.view["attributes"]["custom"]["session"]["is_active"] = False
        self.assertIn("session.is_active", {c["path"] for c in self.assess()["unresolved"]})
        for value in [False, 0]:
            changes = projection.differences({"session": {}}, {"session": {"has_replay": value}}, view=False, reducer=reducer)
            self.assertEqual(changes[0]["disposition"], "UNRESOLVED_OMISSION")

    def test_device_enum_is_one_documented_pair_without_casefold_or_mutation(self):
        for actual, submitted, view, disposition in [
            ("Tablet", "tablet", True, "SOURCE_DEVICE_ENUM"),
            ("TABLET", "tablet", True, "UNRESOLVED_VALUE"),
            ("Tablet", "TABLET", True, "UNRESOLVED_VALUE"),
            ("Other", "other", True, "UNRESOLVED_VALUE"),
            ("Tablet", "tablet", False, "UNRESOLVED_VALUE"),
            ("Tablet", None, True, "UNRESOLVED_VALUE")]:
            with self.subTest(actual=actual, submitted=submitted, view=view):
                change = projection.differences({"device": {"type": actual}}, {"device": {"type": submitted}}, view=view)[0]
                self.assertEqual(change["disposition"], disposition)
                self.assertEqual((change["actual"], change["submitted"]), (actual, submitted))

    def test_action_rules_do_not_apply_view_reducer_revision_or_optional_object_rules(self):
        submitted = {"context": {}, "feature_flags": {}, "session": {"is_active": True},
                     "_dd": {"document_version": 1, "replay_stats": {}}}
        actual = {"session": {}, "_dd": {"document_version": 2}}
        changes = projection.differences(actual, submitted, view=False, action=True,
                                         reducer={"session": {"is_active": True}})
        classified = {c["path"] for c in changes if not c["disposition"].startswith("UNRESOLVED")}
        self.assertEqual(classified, {"context"})
        for view in [True, False]:
            changes = projection.differences({}, {"context": {}}, view=view)
            self.assertEqual(changes[0]["disposition"], "UNRESOLVED_OMISSION")

    def test_missing_views_events_reducer_and_wrong_reducer_counts_are_unqualified(self):
        for index in range(len(self.rows)):
            with self.subTest(index=index):
                self.assertEqual(self.assess(self.rows[:index] + self.rows[index + 1:])["qualification"], "UNQUALIFIED")
        for value in [0, 2, True]:
            rows = copy.deepcopy(self.rows); rows[-1]["attributes"]["custom"]["session"]["view"]["count"] = value
            with self.subTest(value=value): self.assertEqual(self.assess(rows)["qualification"], "UNQUALIFIED")

    def test_duplicate_revisions_reducers_wrong_owner_and_partition_fail(self):
        for index in range(len(self.rows)):
            rows = copy.deepcopy(self.rows); extra = copy.deepcopy(rows[index]); extra["id"] = "other"; rows.append(extra)
            with self.subTest(index=index), self.assertRaises(Rejected): self.assess(rows)
        rows = copy.deepcopy(self.rows); rows[0]["attributes"]["custom"]["view"]["id"] = fixtures.uid(99)
        with self.assertRaises(Rejected): self.assess(rows)
        with self.assertRaises(Rejected): projection.assess(self.rows, self.rows[:-1], self.local, fixtures.EXPECTED)

    def test_wrong_source_identity_and_revision_types_fail(self):
        for path in ["application", "session"]:
            rows = copy.deepcopy(self.rows); rows[0]["attributes"]["custom"][path]["id"] = fixtures.uid(99)
            with self.subTest(path=path), self.assertRaises(Rejected): self.assess(rows)
        rows = copy.deepcopy(self.rows); rows[0]["attributes"]["tag"]["sdk_version"] = "other"
        with self.assertRaises(Rejected): self.assess(rows)
        self.view["attributes"]["custom"]["_dd"]["document_version"] = True
        with self.assertRaises(Rejected): self.assess()


class SavedExchange(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.identity = dict(fixtures.IDENTITY, os="27.0")
        native = fixtures.stream()
        native[0]["payload"].update(build_sdk="iphoneos27.1", os="27.0")
        for row in native:
            if row["kind"] == "rum" and row["payload"]["type"] == "view":
                row["payload"]["view"]["time_spent"] = 100 if row["payload"]["view"]["is_active"] else 1000
        import physical_ownership
        self.local = physical_ownership.inventory(native, self.identity)
        self.rows = fixtures.backend_rows(self.local)
        (self.root / "summary.json").write_bytes(encoded(dict(state="INVALID")))
        (self.root / "native-summary.json").write_bytes(encoded(dict(identity=self.identity, expected=fixtures.EXPECTED)))
        (self.root / "terminal-before-collection.jsonl").write_bytes(b"".join(encoded(r) for r in native))
        base = "@application.id:" + fixtures.EXPECTED["application_id"] + " @session.id:" + fixtures.EXPECTED["session_id"]
        self.broad = self.exchange("broad", base)
        self.native_path = self.exchange("native", base + " service:" + fixtures.EXPECTED["service"] + " source:ios")

    def exchange(self, name, query):
        path = self.root / (name + ".request.json"); spool = self.root / name; spool.mkdir()
        request = dict(run_id=self.identity["run_id"], nonce=fixtures.uid(91 if name == "broad" else 92),
            query=query, **{"from": "2026-09-22T20:00:00+00:00", "to": "2026-09-22T21:00:00+00:00"})
        bound = dict(schema_version=1, request=request, issued_at=100, deadline=150, row_limit=2000, page_limit=41, minimum_rows=0)
        path.write_bytes(encoded(bound))
        response = dict(request=request, count_response=transport_fixtures.count(len(self.rows)), pages=[
            dict(start_at=0, response=transport_fixtures.page(self.rows, len(self.rows))),
            dict(start_at=len(self.rows), response=transport_fixtures.page([], len(self.rows)))])
        response_path = self.root / (name + ".response.json"); response_path.write_bytes(encoded(response))
        receipt = dict(state="COMPLETE_INVENTORY", rows=len(self.rows), deadline=150, published_at=120,
                       request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                       response_sha256=hashlib.sha256(response_path.read_bytes()).hexdigest())
        (spool / "publication.json").write_bytes(encoded(receipt))
        return path

    def test_past_exchange_is_read_without_renewing_any_clock(self):
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(projection.saved_inventory(self.broad), self.rows)
        with self.assertRaises(Rejected): projection.backend.transport.wait(self.broad)
        self.assertEqual({p: p.read_bytes() for p in before}, before)

    def test_changed_response_or_late_original_publication_is_rejected(self):
        path = self.root / "broad/publication.json"; receipt = json.loads(path.read_bytes())
        for key, value in [("state", "PENDING"), ("published_at", 151), ("deadline", 151),
                           ("rows", 99), ("response_sha256", "changed"), ("request_sha256", "changed")]:
            path.write_bytes(encoded(dict(receipt, **{key: value})))
            with self.subTest(key=key), self.assertRaises(Rejected): projection.saved_inventory(self.broad)
        path.write_bytes(encoded(receipt))
        (self.root / "broad.response.json").write_bytes(b"{}")
        with self.assertRaises(Rejected): projection.saved_inventory(self.broad)

    def test_entry_point_preserves_inputs_and_cannot_overwrite_a_result(self):
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        output = self.root / "assessment.json"
        result = projection.record(self.root, self.broad, self.native_path, output)
        self.assertFalse(result["runtime_acceptance"])
        self.assertFalse(result["release_acceptance"])
        self.assertEqual({p: p.read_bytes() for p in before}, before)
        with self.assertRaises(Rejected): projection.record(self.root, self.broad, self.native_path, output)

    def test_swapped_or_foreign_queries_cannot_be_assessed(self):
        with self.assertRaises(Rejected): projection.record(self.root, self.native_path, self.broad, self.root / "swapped.json")
        self.assertFalse((self.root / "swapped.json").exists())
        with self.assertRaises(Rejected): projection.record(self.root, self.broad, self.broad, self.root / "duplicated.json")
        self.assertFalse((self.root / "duplicated.json").exists())


if __name__ == "__main__": unittest.main()
