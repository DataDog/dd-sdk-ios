import copy
import unittest
from uuid import UUID

from acceptance_common import Rejected
import operation_ownership as t


def uid(value):
    return str(UUID(int=value))


def fixture():
    run = "h06-unit"
    session = uid(1)
    views = {"scene-A": uid(2), "scene-B": uid(3)}
    rows = []
    # Literal scenario expectations, independent of the validator's table.
    cases = [("cross-success", "scene-A", "scene-B", None),
             ("cross-failure", "scene-A", "scene-B", "error"),
             ("parallel-alpha", "scene-A", "scene-A", None),
             ("parallel-beta", "scene-B", "scene-B", None)]
    for index, (instance, start, end, failure) in enumerate(cases):
        key, operation_id = run + "-" + instance, uid(10 + index)
        start_id, end_id = uid(20 + index * 2), uid(21 + index * 2)
        for step, scene, vital_id in [("start", start, start_id), ("end", end, end_id)]:
            payload = dict(type="vital", session={"id": session, "type": "user"}, view={"id": views[scene]},
                           application={"id": uid(4)}, service="h06-probe",
                           context={"probe": {"run_id": run}},
                           operation={"id": operation_id},
                           vital=dict(id=vital_id, type="operation_step",
                                      name="multi_scene_probe_navigation", operation_key=key, step_type=step))
            if step == "end" and failure:
                payload["vital"]["failure_reason"] = failure
            rows.append(dict(id="event-" + str(len(rows)), attributes={"custom": payload, "service": "h06-probe", "source": "ios"}))
        payload = dict(type="operation", session={"id": session, "type": "user"},
                       application={"id": uid(4)}, service="h06-probe",
                           context={"probe": {"run_id": run}}, vital={"id": start_id},
                       operation=dict(id=operation_id, name="multi_scene_probe_navigation", operation_key=key,
                                      status="failure" if failure else "success",
                                      start_view={"id": views[start]}, end_view={"id": views[end]}))
        if failure:
            payload["operation"]["failure_reason"] = failure
        rows.append(dict(id="event-" + str(len(rows)), attributes={"custom": payload, "service": "h06-probe", "source": "ios"}))
    return rows, dict(run_id=run, session_id=session, scene_views=views, count=12, application_id=uid(4), service="h06-probe")


def payload(rows, index):
    return rows[index]["attributes"]["custom"]


class OperationOwnershipTests(unittest.TestCase):
    def test_exact_raw_steps_and_reduced_owners_join(self):
        rows, args = fixture()
        result = t.validate(rows, **args)
        self.assertEqual((result["raw_steps"], result["reduced_operations"]), (8, 4))
        self.assertFalse(result["release_acceptance"])
        self.assertTrue(result["physical_topology_required"])

    def test_wrong_raw_and_reduced_owners_reject(self):
        for index, field in [(0, "view"), (1, "view"), (2, "start_view"), (2, "end_view"),
                             (8, "end_view"), (11, "start_view")]:
            with self.subTest(index=index, field=field):
                rows, args = fixture()
                owner = payload(rows, index) if field == "view" else payload(rows, index)["operation"]
                owner[field]["id"] = uid(99)
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_missing_extra_duplicate_rows_reject(self):
        for change in ["missing", "extra", "repeated-row", "duplicate-step", "duplicate-operation"]:
            with self.subTest(change=change):
                rows, args = fixture()
                if change == "missing":
                    rows.pop()
                elif change == "extra":
                    rows.append(copy.deepcopy(rows[0]))
                else:
                    target, source = (1, 0) if change != "duplicate-operation" else (5, 2)
                    rows[target] = copy.deepcopy(rows[source])
                    if change != "repeated-row":
                        rows[target]["id"] = "new-event"
                args["count"] = len(rows)
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_raw_and_reduced_identity_links_reject_substitution(self):
        for index, family in [(0, "vital"), (1, "vital"), (1, "operation"),
                              (2, "vital"), (2, "operation"), (5, "operation")]:
            with self.subTest(index=index, family=family):
                rows, args = fixture()
                # Reusing another raw vital must not collapse two steps.
                payload(rows, index)[family]["id"] = uid(20) if index == 1 and family == "vital" else uid(99)
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_foreign_run_session_and_aliased_owners_reject(self):
        for change in ["run", "session", "alias", "missing-owner", "malformed-owner", "count"]:
            with self.subTest(change=change):
                rows, args = fixture()
                if change == "run":
                    payload(rows, 0)["context"]["probe"]["run_id"] = "old"
                elif change == "session":
                    payload(rows, 0)["session"]["id"] = uid(99)
                elif change == "alias":
                    args["scene_views"]["scene-B"] = args["scene_views"]["scene-A"]
                elif change == "missing-owner":
                    del args["scene_views"]["scene-B"]
                elif change == "malformed-owner":
                    args["scene_views"]["scene-B"] = "unknown"
                else:
                    args["count"] = True
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_application_service_source_and_session_type_are_bound(self):
        for field in ["application", "service", "indexed-service", "source", "missing-source", "session-type"]:
            with self.subTest(field=field):
                rows, args = fixture()
                p = payload(rows, 0)
                if field == "application":
                    p["application"]["id"] = uid(99)
                elif field == "service":
                    p["service"] = "foreign"
                elif field == "indexed-service":
                    rows[0]["attributes"]["service"] = "foreign"
                elif field == "source":
                    rows[0]["attributes"]["source"] = "browser"
                elif field == "missing-source":
                    del rows[0]["attributes"]["source"]
                else:
                    p["session"]["type"] = "synthetics"
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_failure_reason_and_status_remain_exact(self):
        for index, family, field, value in [(4, "vital", "failure_reason", None),
                                         (0, "vital", "failure_reason", "error"),
                                         (5, "operation", "failure_reason", "timeout"),
                                         (2, "operation", "status", "failure")]:
            with self.subTest(index=index, field=field):
                rows, args = fixture()
                payload(rows, index)[family][field] = value
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_name_key_and_step_cannot_change(self):
        for index, family, field, value in [(0, "vital", "name", "other"),
                                         (0, "vital", "operation_key", "other"),
                                         (0, "vital", "step_type", "update"),
                                         (0, "vital", "type", "app_launch"),
                                         (2, "operation", "name", "other"),
                                         (2, "operation", "operation_key", "other")]:
            with self.subTest(index=index, field=field):
                rows, args = fixture()
                payload(rows, index)[family][field] = value
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)

    def test_completed_custom_context_cannot_replace_raw_view_owner(self):
        rows, args = fixture()
        for row in rows:
            row["attributes"]["custom"]["context"]["probe"].update(
                operation_step="succeed-operation", source_scene="scene-B", scene_session_id="later-scene")
        self.assertEqual(t.validate(rows, **args)["raw_steps"], 8)
        payload(rows, 0)["view"]["id"] = args["scene_views"]["scene-B"]
        with self.assertRaises(Rejected):
            t.validate(rows, **args)

    def test_backend_order_and_duration_do_not_gate_ownership(self):
        rows, args = fixture()
        rows.reverse()
        for row in rows:
            row["timestamp"] = "delayed-indexing"
            row["attributes"]["custom"]["operation"]["duration"] = 999999999
        self.assertEqual(t.validate(rows, **args)["reduced_operations"], 4)

    def test_malformed_payloads_fail_closed(self):
        for field in ["session", "context", "vital", "operation", "view"]:
            with self.subTest(field=field):
                rows, args = fixture()
                payload(rows, 0)[field] = None
                with self.assertRaises(Rejected):
                    t.validate(rows, **args)


if __name__ == "__main__":
    unittest.main()
