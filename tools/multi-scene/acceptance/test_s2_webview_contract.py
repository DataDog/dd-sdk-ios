"""Offline mutations of a finite native/WebKit/writer timeline; no simulator claim."""
import copy
import hashlib
import json
import unittest
from acceptance_common import Rejected
from s2_webview_contract import evaluate_markers, sealed_evidence


def fixture(arm="B"):
    run = "10000000-0000-0000-0000-000000000001"
    app = "20000000-0000-0000-0000-000000000001"
    sid = "30000000-0000-0000-0000-000000000001"
    ids = {"NativeA": "40000000-0000-0000-0000-000000000001",
           "NativeB": "40000000-0000-0000-0000-000000000002"}
    identity = dict(run_id=run, nonce="10000000-0000-0000-0000-000000000002", arm=arm)
    expected = dict(identity=identity, application_id=app, browser_service="s2-web-fixture",
                    window="owned-window", scene="owned-scene")
    records, events = [], {}
    base = 1_790_000_000_000
    def add(kind, ms, **fields):
        row = dict(sequence=len(records) + 1, monotonic_ns=ms * 1_000_000,
                   wall_ms=base + ms, kind=kind, **fields)
        records.append(row)
        return row
    def owner(name, ms):
        add("native-start", ms, name=name)
        event = dict(type="view", date=base + ms, view=dict(id=ids[name], name=name, is_active=True),
                     session=dict(id=sid, has_replay=True), application=dict(id=app))
        mapper = add("native-view", ms + 1, event_json=json.dumps(event))
        add("native-ready", ms + 2, name=name, view_id=ids[name], session_id=sid,
            mapper_sequence=mapper["sequence"])
    def freeze(marker, ms):
        event = dict(type="view", source="browser", service="s2-web-fixture", date=base + ms,
                     application=dict(id="browser-application"),
                     session=dict(id="browser-session", has_replay=True),
                     view=dict(id="50000000-0000-0000-0000-00000000000" + marker[-1], name=marker,
                               is_active=False, action=dict(count=0), resource=dict(count=0), error=dict(count=0),
                               long_task=dict(count=0), time_spent=1_000_000, loading_type="initial_load"),
                     _dd=dict(format_version=2, document_version=1),
                     context=dict(probe=dict(run_id=run, marker=marker)))
        events[marker] = event
        add("envelope-frozen", ms, marker=marker,
            body_json=json.dumps(dict(eventType="view", event=event)))
    def emit(marker, ms):
        web = "B" if marker == "M2" else "A"
        add("emit-before", ms, marker=marker, view_id=events[marker]["view"]["id"],
            live_view_id=ids["NativeA" if marker == "M1" else "NativeB"])
        add("webkit-callback", ms + 1, marker=marker, view_id=events[marker]["view"]["id"],
            webview_identity="actual-web-" + web, document_id="fresh-document-" + web,
            window="owned-window" if marker in ("M1", "M2") else None,
            scene="owned-scene" if marker in ("M1", "M2") else None,
            body_json=json.dumps(dict(eventType="view", event=events[marker])))
    def ack(marker, ms):
        event = copy.deepcopy(events[marker]);event["application"]["id"] = app;event["session"]["id"] = sid
        owner_name = "NativeA" if marker == "M1" or (marker == "M3" and arm == "B") else "NativeB" if marker == "M2" else None
        if owner_name:event["container"] = dict(source="ios", view=dict(id=ids[owner_name]))
        attributes = dict(custom=event, client_time=event.pop("date"), source=event.pop("source"),
                          service=[event["service"]])
        raw = json.dumps(dict(id="actual-backend-row-" + marker, attributes=attributes))
        add("writer-ack", ms, marker=marker, view_id=event["view"]["id"], event_json=raw,
            event_sha256=hashlib.sha256(raw.encode()).hexdigest(), evidence_kind="datadog-mcp")
    owner("NativeA", 0)
    add("web-document-ready", 3, webview="A", document_id="fresh-document-A")
    freeze("M1", 181_003);emit("M1", 181_004);ack("M1", 181_006)
    freeze("M3", 181_007);freeze("M4", 181_008)
    add("fold-complete", 300_000, phase="open", proof_sha256="a" * 64)
    owner("NativeB", 300_010)
    inactive_event = dict(type="view", date=base, view=dict(id=ids["NativeA"], name="NativeA", is_active=False),
                          session=dict(id=sid, has_replay=True), application=dict(id=app))
    inactive_mapper = add("native-view", 300_012, event_json=json.dumps(inactive_event))
    add("native-inactive", 300_012, name="NativeA", view_id=ids["NativeA"], mapper_sequence=inactive_mapper["sequence"])
    add("web-document-ready", 300_013, webview="B", document_id="fresh-document-B")
    freeze("M2", 300_014);emit("M2", 300_015)
    add("detached", 300_017, webview="A", window=None)
    emit("M3", 300_018);ack("M2", 300_020);ack("M3", 300_021)
    add("fold-complete", 440_000, phase="closed", proof_sha256="b" * 64)
    emit("M4", 480_013);ack("M4", 480_015)
    add("tracking-disabled", 480_016, webview="A")
    add("weak-release", 480_017, webview="A", is_nil=True)
    return dict(identity=identity, records=records, persistence_failure=False, durable_sequence=len(records)), expected


def navigation_fixture(arm="B", backend=True):
    document, expected = fixture(arm)
    expected['mode'] = 'navigation-ttl'
    records = document['records']; acknowledgements = [r for r in records if r['kind']=='writer-ack']
    records[:] = [r for r in records if r['kind'] not in ['writer-ack','fold-complete']]
    first = records[0]
    records.insert(0, {'kind':'scenario','mode':'navigation-ttl','wall_ms':first['wall_ms'],'monotonic_ns':first['monotonic_ns']})
    last = records[-1]
    complete = {'kind':'behavior-complete','wall_ms':last['wall_ms']+1,'monotonic_ns':last['monotonic_ns']+1_000_000}
    records.append(complete)
    if backend:
        for i, row in enumerate(acknowledgements,1):
            # Deliberately after the inactive TTL; backend latency is not SDK consumption timing.
            row.update(wall_ms=complete['wall_ms']+i,monotonic_ns=complete['monotonic_ns']+i*1_000_000)
            records.append(row)
    mapping={r['sequence']:i for i,r in enumerate(records,1) if 'sequence' in r}
    for i,row in enumerate(records,1):
        if 'mapper_sequence' in row:row['mapper_sequence']=mapping[row['mapper_sequence']]
        row['sequence']=i
    document['durable_sequence']=len(records)
    return document,expected


class NavigationTTLControls(unittest.TestCase):
    def test_both_sources_keep_exact_owners_with_late_backend_collection(self):
        for arm in ['A','B']:
            document,expected=navigation_fixture(arm)
            result=evaluate_markers(document,expected)
            self.assertEqual(len(result['browser_markers']),4)
            self.assertNotIn('independent fold proofs',result['remaining'])
    def test_local_behavior_does_not_need_backend_receipts(self):
        document,expected=navigation_fixture(backend=False)
        result=evaluate_markers(document,expected,require_backend=False)
        self.assertEqual(len(result['browser_markers']),4)
        with self.assertRaises(Rejected):evaluate_markers(document,expected)
    def test_late_m3_callback_still_rejected(self):
        document,expected=navigation_fixture()
        row=next(r for r in document['records'] if r['kind']=='webkit-callback' and r['marker']=='M3')
        start=next(r for r in document['records'] if r['kind']=='native-start' and r['name']=='NativeB')
        row.update(wall_ms=start['wall_ms']+180001,monotonic_ns=start['monotonic_ns']+180001*1_000_000)
        with self.assertRaisesRegex(Rejected,'TTL'):evaluate_markers(document,expected)
    def test_no_implicit_conversion_of_old_fold_evidence(self):
        document,expected=fixture();expected['mode']='navigation-ttl'
        with self.assertRaises(Rejected):evaluate_markers(document,expected)
    def test_wrong_container_remains_a_failure(self):
        document,expected=navigation_fixture()
        row=next(r for r in document['records'] if r['kind']=='writer-ack' and r['marker']=='M3')
        raw=json.loads(row['event_json']);raw['attributes']['custom']['container']['view']['id']='40000000-0000-0000-0000-000000000002'
        row['event_json']=json.dumps(raw);row['event_sha256']=hashlib.sha256(row['event_json'].encode()).hexdigest()
        with self.assertRaises(Rejected):evaluate_markers(document,expected)
    def test_native_completion_requires_release(self):
        document,expected=navigation_fixture();next(r for r in document['records'] if r['kind']=='weak-release')['is_nil']=False
        with self.assertRaises(Rejected):evaluate_markers(document,expected)
    def test_no_fold_request_in_scoped_native_interval(self):
        document,expected=navigation_fixture();row=document['records'][0].copy();row.update(kind='host-request-issued',request_kind='human-fold')
        document['records'].insert(1,row)
        for i,r in enumerate(document['records'],1):r['sequence']=i
        document['durable_sequence']=len(document['records'])
        with self.assertRaises(Rejected):evaluate_markers(document,expected)


class MarkerControls(unittest.TestCase):
    def row(self, document, kind, marker=None):
        return next(r for r in document["records"] if r["kind"] == kind and
                    (marker is None or r.get("marker") == marker))

    def mutate(self, change, match):
        document, expected = fixture()
        change(document, expected)
        with self.assertRaisesRegex(Rejected, match):evaluate_markers(document, expected)

    def alter_upload(self, document, marker, change):
        row = self.row(document, "writer-ack", marker)
        event = json.loads(row["event_json"]);change(event["attributes"]["custom"])
        row["event_json"] = json.dumps(event)
        row["event_sha256"] = hashlib.sha256(row["event_json"].encode()).hexdigest()

    def test_missing_actual_a_deactivation(self):
        self.mutate(lambda d, _: self.row(d, "native-inactive").update(kind="missing"), "native-inactive")

    def test_inactive_must_be_a_not_b(self):
        self.mutate(lambda d, _: self.row(d, "native-inactive").update(view_id="40000000-0000-0000-0000-000000000002"), "inactive owner")

    def test_inactive_receipt_cannot_follow_detachment(self):
        self.mutate(lambda d, _: self.row(d, "native-inactive").update(mapper_sequence=self.row(d, "detached")["sequence"]), "not a mapper")

    def test_both_source_predicted_arms(self):
        for arm in ("A", "B"):
            with self.subTest(arm=arm):
                result = evaluate_markers(*fixture(arm))
                self.assertEqual(result["state"], "MARKERS_QUALIFIED")
                self.assertIn("complete backend inventory", result["remaining"])

    def test_missing_durable_terminal_sequence(self):
        self.mutate(lambda d, _: d.pop("durable_sequence"), "durably complete")

    def test_stale_durable_terminal_sequence(self):
        self.mutate(lambda d, _: d.update(durable_sequence=len(d["records"]) - 1), "durably complete")

    def test_native_and_browser_server_offset_same_domain(self):
        document, expected = fixture()
        for row in document["records"]:
            if row["kind"] == "native-view":
                event = json.loads(row["event_json"]);event["date"] += 600_000;row["event_json"] = json.dumps(event)
            if row["kind"] == "writer-ack":
                event = json.loads(row["event_json"]);event["attributes"]["client_time"] += 600_000
                row["event_json"] = json.dumps(event);row["event_sha256"] = hashlib.sha256(row["event_json"].encode()).hexdigest()
        self.assertEqual(evaluate_markers(document, expected)["state"], "MARKERS_QUALIFIED")

    def test_conflicting_backend_source(self):
        self.mutate(lambda d, _: self.alter_upload(d, "M1", lambda e: e.update(source="ios")), "conflicting backend source")

    def test_missing_backend_container_is_not_inferred(self):
        self.mutate(lambda d, _: self.alter_upload(d, "M3", lambda e: e.pop("container")), "container differs")

    def test_callback_body_is_not_backend_acknowledgement(self):
        self.mutate(lambda d, _: self.row(d, "writer-ack", "M3").update(evidence_kind="webkit-callback"), "raw backend evidence")

    def test_wrong_native_container(self):
        self.mutate(lambda d, _: self.alter_upload(d, "M3", lambda e: e["container"]["view"].update(id="40000000-0000-0000-0000-000000000002")), "container differs")

    def test_old_event_cannot_inherit_b_after_expiry(self):
        self.mutate(lambda d, _: self.alter_upload(d, "M4", lambda e: e.update(container={"source": "ios", "view": {"id": "40000000-0000-0000-0000-000000000002"}})), "expired native")

    def test_missing_callback(self):
        self.mutate(lambda d, _: self.row(d, "webkit-callback", "M3").update(kind="missing-callback"), "callback inventory")

    def test_stale_identity(self):
        self.mutate(lambda d, _: d.update(identity=dict(d["identity"], nonce="10000000-0000-0000-0000-000000000099")), "stale fixture")

    def test_owner_assertion_after_emission(self):
        def change(d, _):
            row=self.row(d, "emit-before", "M3");row["live_view_id"]="40000000-0000-0000-0000-000000000001"
        self.mutate(change, "pre-emission native owner")

    def test_replay_eligibility_required(self):
        def change(d, _):
            r=self.row(d, "native-view");e=json.loads(r["event_json"]);e["session"]["has_replay"]=False;r["event_json"]=json.dumps(e)
        self.mutate(change, "Replay eligible")

    def test_detach_does_not_mean_immediate_expiry(self):
        self.mutate(lambda d, _: self.alter_upload(d, "M3", lambda e: e.pop("container")), "container differs")

    def test_old_payload_cannot_be_redated(self):
        def change(d, _):
            r=self.row(d, "webkit-callback", "M3");e=json.loads(r["body_json"]);e["event"]["date"]+=1;r["body_json"]=json.dumps(e)
        self.mutate(change, "redated/replaced")

    def test_late_short_ttl_ack(self):
        def change(d, _):
            row=self.row(d, "writer-ack", "M3")
            for record in d["records"][row["sequence"]-1:]: record["wall_ms"]+=180_000
        self.mutate(change, "TTL bracket")

    def test_monotonic_ttl_cannot_substitute_for_wall_ttl(self):
        def change(d, _):
            row=self.row(d, "emit-before", "M4");row["wall_ms"]-=1_000
        self.mutate(change, "TTL bracket")

    def test_consumed_writer_ack(self):
        self.mutate(lambda d, _: self.row(d, "writer-ack", "M3").update(view_id="50000000-0000-0000-0000-000000000002"), "acknowledgement identity")

    def test_raw_writer_bytes_required(self):
        self.mutate(lambda d, _: self.row(d, "writer-ack", "M3").update(event_sha256="0"*64), "bound to raw")

    def test_webview_release_required(self):
        self.mutate(lambda d, _: self.row(d, "weak-release").update(is_nil=False), "still retained")

    def test_webkit_attachment_required(self):
        self.mutate(lambda d, _: self.row(d, "webkit-callback", "M3").update(window="owned-window"), "attachment differs")

    def test_container_source_required(self):
        self.mutate(lambda d, _: self.alter_upload(d, "M1", lambda e: e["container"].update(source="browser")), "container differs")

    def test_owner_boundary_cannot_follow_mapper(self):
        def change(d, _):
            start = self.row(d, "native-start")
            ready = self.row(d, "native-ready")
            start_fields = {k: v for k, v in start.items() if k not in ("sequence", "monotonic_ns", "wall_ms")}
            ready_fields = {k: v for k, v in ready.items() if k not in ("sequence", "monotonic_ns", "wall_ms")}
            for row, fields in ((start, ready_fields), (ready, start_fields)):
                clocks = {k: row[k] for k in ("sequence", "monotonic_ns", "wall_ms")}
                row.clear();row.update(clocks);row.update(fields)
        self.mutate(change, "after critical boundary")

    def test_extra_callback_rejected(self):
        self.mutate(lambda d, _: self.row(d, "tracking-disabled").update(kind="webkit-callback", marker="M4"), "callback inventory")

    def test_late_server_clock_correction_cannot_change_owner_expectation(self):
        def change(d, _):
            row = self.row(d, "writer-ack", "M3")
            event = json.loads(row["event_json"]);event["attributes"]["client_time"] = 1_790_000_300_050
            row["event_json"] = json.dumps(event);row["event_sha256"] = hashlib.sha256(row["event_json"].encode()).hexdigest()
        self.mutate(change, "outside A timestamp")


class PersistenceControls(unittest.TestCase):
    def test_backward_date_rejects(self):
        document, expected = fixture("B")
        document["records"][1]["wall_ms"] = document["records"][0]["wall_ms"] - 1
        with self.assertRaisesRegex(Rejected, "backward"): evaluate_markers(document, expected)
    def test_persistence_failure_rejects(self):
        document, expected = fixture("B")
        document["persistence_failure"] = True
        with self.assertRaisesRegex(Rejected, "persistence"): evaluate_markers(document, expected)
    def test_missing_persistence_receipt_rejects(self):
        document, expected = fixture("B")
        document.pop("persistence_failure")
        with self.assertRaisesRegex(Rejected, "persistence"): evaluate_markers(document, expected)
if __name__ == "__main__":unittest.main()


class TerminalControls(unittest.TestCase):
    def prepared(self):
        identity = {"run_id": "controlled"}
        rows = [{"kind": "terminal", "sequence": 1, "observation_closed": True, "state": "PASS"}]
        document = dict(identity=identity, records=rows, closed_sequence=1, durable_sequence=1, persistence_failure=False)
        raw = json.dumps(document).encode()
        terminal = dict(state="PASS", identity=identity, closed_sequence=1, evidence_sha256=hashlib.sha256(raw).hexdigest())
        return document, raw, terminal, identity

    def test_sealed_snapshot(self):
        document, raw, terminal, identity = self.prepared()
        self.assertEqual(sealed_evidence(raw, terminal, identity), document)

    def test_late_actual_callback_changes_hash(self):
        document, raw, terminal, identity = self.prepared()
        document["records"].append({"kind": "native-view", "after_cutoff": True})
        with self.assertRaisesRegex(Rejected, "changed after terminal"):
            sealed_evidence(json.dumps(document).encode(), terminal, identity)

    def test_late_callback_before_receipt_is_also_rejected(self):
        document, raw, terminal, identity = self.prepared()
        document["records"].append({"kind": "native-view", "after_cutoff": True})
        document["durable_sequence"] = 2
        raw = json.dumps(document).encode(); terminal["evidence_sha256"] = hashlib.sha256(raw).hexdigest()
        with self.assertRaisesRegex(Rejected, "late or incomplete"):
            sealed_evidence(raw, terminal, identity)
