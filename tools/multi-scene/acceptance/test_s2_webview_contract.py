"""Offline mutations of a finite native/WebKit/writer timeline; no simulator claim."""
import copy
import hashlib
import json
import unittest
from acceptance_common import Rejected
from s2_webview_contract import evaluate_markers


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
        event = dict(type="view", view=dict(id=ids[name], name=name, is_active=True),
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
        raw = json.dumps(event)
        add("writer-ack", ms, marker=marker, view_id=event["view"]["id"], event_json=raw,
            event_sha256=hashlib.sha256(raw.encode()).hexdigest())
    owner("NativeA", 0)
    add("web-document-ready", 3, webview="A", document_id="fresh-document-A")
    freeze("M1", 181_003);emit("M1", 181_004);ack("M1", 181_006)
    freeze("M3", 181_007);freeze("M4", 181_008)
    add("fold-complete", 300_000, phase="open", proof_sha256="a" * 64)
    owner("NativeB", 300_010)
    add("web-document-ready", 300_013, webview="B", document_id="fresh-document-B")
    freeze("M2", 300_014);emit("M2", 300_015)
    add("detached", 300_017, webview="A", window=None)
    emit("M3", 300_018);ack("M2", 300_020);ack("M3", 300_021)
    add("fold-complete", 440_000, phase="closed", proof_sha256="b" * 64)
    emit("M4", 480_013);ack("M4", 480_015)
    add("tracking-disabled", 480_016, webview="A")
    add("weak-release", 480_017, webview="A", is_nil=True)
    return dict(identity=identity, records=records), expected


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
        event = json.loads(row["event_json"]);change(event)
        row["event_json"] = json.dumps(event)
        row["event_sha256"] = hashlib.sha256(row["event_json"].encode()).hexdigest()

    def test_both_source_predicted_arms(self):
        for arm in ("A", "B"):
            with self.subTest(arm=arm):
                result = evaluate_markers(*fixture(arm))
                self.assertEqual(result["state"], "MARKERS_QUALIFIED")
                self.assertIn("complete backend inventory", result["remaining"])

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
            row=self.row(d, "writer-ack", "M3");row["wall_ms"]+=180_000
        self.mutate(change, "TTL bracket")

    def test_monotonic_ttl_cannot_substitute_for_wall_ttl(self):
        def change(d, _):
            row=self.row(d, "emit-before", "M4");row["wall_ms"]-=180_000
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
        self.mutate(lambda d, _: self.alter_upload(d, "M3", lambda e: e.update(date=1_790_000_300_050)), "outside A timestamp")


if __name__ == "__main__":unittest.main()
