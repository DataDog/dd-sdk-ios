"""Adversarial controls for offline app inventories, not simulated app acceptance."""
import copy
import unittest

from acceptance_common import Rejected
import app_journey_inventory as app


def uid(number):
    return f"00000000-0000-0000-0000-{number:012d}"


def fixture():
    identity = dict(application_id=uid(1), session_id=uid(2), from_ms=1000, to_ms=9000,
                    sources={"ios": dict(service="native-app", sdk_version="native-version"),
                             "browser": dict(service="dashboard-web", sdk_version="browser-version")})
    rows = []

    def row(family, number, when, source="ios", **kw):
        p = dict(type=family, application={"id": uid(1)}, session={"id": uid(2), "type": "user", "has_replay": True},
                 service=identity["sources"][source]["service"], source=source)
        p.update(kw)
        result = dict(id="opaque-" + str(number), attributes=dict(custom=p, client_time=when,
                      tag={"sdk_version": identity["sources"][source]["sdk_version"]}))
        rows.append(result)
        return result

    for number, name, url in [(10, "Services", "Services"), (11, "ServiceList", "ServiceList/-123"),
                              (12, "ServiceDetail", "ServiceDetail/456"), (13, "ServiceList", "ServiceList/-123"),
                              (14, "DashboardDetails", "DashboardDetails")]:
        row("view", number, number * 100, view=dict(id=uid(number), name=name, url=url, is_active=number == 14),
            _dd={"document_version": 3})
    row("view", 15, 2000, source="browser", view=dict(id=uid(15), name="Dashboard", url="https://example.invalid/dashboard", is_active=True),
        _dd={"document_version": 2}, container={"view": {"id": uid(14)}, "source": "ios"})
    row("action", 20, 1150, action={"id": uid(20), "type": "tap", "target": {"name": "Service cell"}},
        view={"id": uid(11)}, context={"view-name": "ServiceList"})
    row("action", 21, 1350, action={"id": uid(21), "type": "tap", "target": {"name": "Service cell"}}, view={"id": uid(13)})
    row("resource", 22, 1300, resource={"id": uid(22), "url": "https://example.invalid/api", "method": "GET"}, view={"id": uid(11)})
    r = row("session", 30, 8000, _dd={"origin": "reducer"})
    r["attributes"]["custom"]["session"].update(view={"count": 6}, action={"count": 2}, crash={"count": 0})
    explicit = {uid(11): "ServiceList", uid(12): "ServiceDetail", uid(13): "ServiceList"}
    return rows, identity, explicit


def reduce(rows=None, identity=None, explicit=None, **kwargs):
    base, defaults, names = fixture()
    return app.reduce(base if rows is None else rows, defaults if identity is None else identity,
                      explicit_swiftui=names if explicit is None else explicit, **kwargs)


def request_fixture():
    rows, _, _ = fixture()
    request = dict(run_id="fresh-run", nonce="fresh-request", query="@application.id:example @session.id:example",
                   **{"from": "2026-09-21T20:00:00Z", "to": "2026-09-21T20:05:00Z"})
    receipt = dict(request=copy.deepcopy(request), count=len(rows), pages=[
        dict(start_at=0, truncated=False, rows=rows), dict(start_at=len(rows), truncated=False, rows=[])])
    return request, receipt


class InventoryControls(unittest.TestCase):
    def test_keeps_raw_rows_and_independent_browser_identity(self):
        request, receipt = request_fixture()
        raw = app.inventory(receipt, request, row_limit=100, page_limit=3)
        result = reduce(raw)
        self.assertEqual(result["status"], "OFFLINE_INVENTORY_ONLY")
        self.assertEqual(result["raw_rows"], receipt["pages"][0]["rows"])
        self.assertFalse(result["native_callbacks_verified"])
        self.assertFalse(result["complete_mapper_revisions_verified"])
        app.native_partition(raw, [r for r in raw if app.source(r) == "ios"])
        verdict = app.browser_container(result, uid(15), uid(14))
        self.assertFalse(verdict["runtime_acceptance"])

    def test_query_and_pagination_controls(self):
        def change_request(r): r["request"].update(run_id="restored-run")
        def change_nonce(r): r["request"].update(nonce="prior-request")
        def truncate(r): r["pages"][0]["truncated"] = True
        def omit_terminal(r): r["pages"].pop()
        def wrong_offset(r): r["pages"][-1]["start_at"] = 0
        def wrong_count(r): r["count"] -= 1
        def duplicate(r):
            r["pages"][0]["rows"].append(copy.deepcopy(r["pages"][0]["rows"][0]))
            r["count"] += 1
            r["pages"][-1]["start_at"] += 1
        for mutate in [change_request, change_nonce, truncate, omit_terminal, wrong_offset, wrong_count, duplicate]:
            with self.subTest(control=mutate.__name__):
                request, receipt = request_fixture(); mutate(receipt)
                with self.assertRaises(Rejected): app.inventory(receipt, request, row_limit=100, page_limit=3)

    def test_identity_and_owner_controls(self):
        def foreign_app(r): r[0]["attributes"]["custom"]["application"]["id"] = uid(90)
        def foreign_session(r): r[0]["attributes"]["custom"]["session"]["id"] = uid(90)
        def native_version_on_browser(r): r[5]["attributes"]["tag"]["sdk_version"] = "native-version"
        def native_service_on_browser(r): r[5]["attributes"]["custom"]["service"] = "native-app"
        def wrong_owner(r): r[6]["attributes"]["custom"]["view"]["id"] = uid(90)
        def context_as_owner(r): del r[6]["attributes"]["custom"]["view"]
        def duplicate_action(r): r[7]["attributes"]["custom"]["action"]["id"] = uid(20)
        def missing_view(r): r.pop(1)
        def bool_revision(r): r[0]["attributes"]["custom"]["_dd"]["document_version"] = True
        def stale_date(r): r[0]["attributes"]["client_time"] = 1
        def alias(r): r[0]["attributes"]["custom"]["view.id"] = uid(10)
        def bad_reducer(r): r[-1]["attributes"]["custom"]["session"]["view"]["count"] = 5
        for mutate in [foreign_app, foreign_session, native_version_on_browser, native_service_on_browser,
                       wrong_owner, context_as_owner, duplicate_action, missing_view, bool_revision, stale_date, alias, bad_reducer]:
            with self.subTest(control=mutate.__name__):
                rows, _, _ = fixture(); mutate(rows)
                with self.assertRaises(Rejected): reduce(rows)
        with self.assertRaisesRegex(Rejected, "restored session"): reduce(prior_sessions=[uid(2)])

    def test_same_name_wrong_occurrence_is_a_graph_difference(self):
        baseline = reduce()
        rows, _, _ = fixture()
        rows[6]["attributes"]["custom"]["view"]["id"] = uid(13)
        with self.assertRaisesRegex(Rejected, "graph differs"): app.compare(baseline, reduce(rows))

    def test_extra_occurrence_is_not_merged_by_name(self):
        baseline = reduce()
        rows, _, _ = fixture(); extra = copy.deepcopy(rows[1])
        extra["id"] = "extra-opaque";extra["attributes"]["custom"]["view"]["id"] = uid(90)
        extra["attributes"]["client_time"] = 3000
        rows.insert(2, extra);rows[-1]["attributes"]["custom"]["session"]["view"]["count"] += 1
        names = fixture()[2]; names[uid(90)] = "ServiceList"
        with self.assertRaisesRegex(Rejected, "graph differs"): app.compare(baseline, reduce(rows, explicit=names))

    def test_new_action_target_is_not_accepted_by_owner_match(self):
        rows, _, _ = fixture();rows[6]["attributes"]["custom"]["action"]["target"]["name"] = "Unfrozen target"
        with self.assertRaisesRegex(Rejected, "graph differs"): app.compare(reduce(), reduce(rows))

    def test_only_verified_swiftui_process_hash_is_normalized(self):
        rows, _, names = fixture(); rows[1]["attributes"]["custom"]["view"]["url"] = "ServiceList/789"
        self.assertFalse(app.compare(reduce(), reduce(rows))["runtime_acceptance"])
        self.assertEqual(reduce(rows)["raw_rows"][1]["attributes"]["custom"]["view"]["url"], "ServiceList/789")
        names[uid(10)] = "Services"
        with self.assertRaisesRegex(Rejected, "unverified SwiftUI"): reduce(rows, explicit=names)
        rows[1]["attributes"]["custom"]["view"]["url"] = "https://example.invalid/ServiceList/789"
        with self.assertRaisesRegex(Rejected, "unrecognized SwiftUI"): reduce(rows)

    def test_browser_url_changes_are_retained(self):
        rows, _, _ = fixture();rows[5]["attributes"]["custom"]["view"]["url"] += "/789"
        with self.assertRaisesRegex(Rejected, "graph differs"): app.compare(reduce(), reduce(rows))

    def test_native_query_cannot_replace_broad_session_inventory(self):
        rows, _, _ = fixture(); native = [r for r in rows if app.source(r) == "ios"]
        with self.assertRaisesRegex(Rejected, "inventories disagree"): app.native_partition(rows, native[:-1])
        changed = copy.deepcopy(native); changed[0]["attributes"]["custom"]["view"]["name"] = "Other"
        with self.assertRaisesRegex(Rejected, "inventories disagree"): app.native_partition(rows, changed)
        with self.assertRaises(Rejected): app.browser_container(reduce(native), uid(15), uid(14))

    def test_cross_query_envelope_ids_are_not_semantic_identity(self):
        rows, _, _ = fixture()
        native = copy.deepcopy([r for r in rows if app.source(r) == "ios"])
        for index, row in enumerate(native): row["id"] = "other-query-" + str(index)
        app.native_partition(rows, native)

    def test_browser_downstream_containers_are_checked(self):
        rows, _, _ = fixture()
        action = copy.deepcopy(rows[6]); action["id"] = "browser-action"
        action["attributes"]["tag"]["sdk_version"] = "browser-version"
        payload = action["attributes"]["custom"]
        payload.update(source="browser", service="dashboard-web", view={"id": uid(15)},
                       action={"id": uid(50), "type": "click", "target": {"name": "Dashboard cell"}},
                       container={"view": {"id": uid(14)}, "source": "ios"})
        rows.append(action); rows[-2]["attributes"]["custom"]["session"]["action"]["count"] += 1
        self.assertFalse(app.browser_container(reduce(rows), uid(15), uid(14))["runtime_acceptance"])
        del payload["container"]
        with self.assertRaisesRegex(Rejected, "exact native container"): app.browser_container(reduce(rows), uid(15), uid(14))
        payload["view"]["id"] = uid(14)
        with self.assertRaisesRegex(Rejected, "owner domains"): reduce(rows)

    def test_browser_container_controls(self):
        with self.assertRaisesRegex(Rejected, "ID substitution"): app.browser_container(reduce(), uid(15), uid(15))
        rows, _, _ = fixture();rows[5]["attributes"]["custom"]["container"]["view"]["id"] = uid(13)
        with self.assertRaisesRegex(Rejected, "exact native container"): app.browser_container(reduce(rows), uid(15), uid(14))
        rows, _, _ = fixture();del rows[5]["attributes"]["custom"]["container"]
        with self.assertRaisesRegex(Rejected, "exact native container"): app.browser_container(reduce(rows), uid(15), uid(14))
        rows, _, _ = fixture();rows[4]["attributes"]["custom"]["session"]["has_replay"] = False
        with self.assertRaises(Rejected) as caught: app.browser_container(reduce(rows), uid(15), uid(14))
        self.assertEqual(caught.exception.state, "INCONCLUSIVE")

    def test_available_revisions_are_preserved_without_claiming_all_updates(self):
        rows, _, _ = fixture(); earlier = copy.deepcopy(rows[1]); earlier["id"] = "earlier-revision"
        earlier["attributes"]["custom"]["_dd"]["document_version"] = 1
        earlier["attributes"]["custom"]["view"]["is_active"] = True
        rows.insert(1, earlier); result = reduce(rows)
        self.assertEqual(set(result["views"][uid(11)]["revisions"]), {1, 3})
        self.assertFalse(result["complete_mapper_revisions_verified"])
        comparison = app.compare(reduce(), result)
        self.assertFalse(comparison["runtime_acceptance"])
        self.assertEqual(comparison["revision_comparison"], "NOT_PERFORMED")
        self.assertEqual(comparison["non_owner_payload_comparison"], "NOT_PERFORMED")
        duplicate = copy.deepcopy(earlier);duplicate["id"] = "duplicate-version";rows.append(duplicate)
        with self.assertRaisesRegex(Rejected, "duplicate view revision"): reduce(rows)

    def test_equal_sdk_dates_need_native_order_evidence(self):
        rows, _, _ = fixture();rows[1]["attributes"]["client_time"] = rows[0]["attributes"]["client_time"]
        with self.assertRaisesRegex(Rejected, "ambiguous SDK occurrence order"): reduce(rows)


if __name__ == "__main__":
    unittest.main()
