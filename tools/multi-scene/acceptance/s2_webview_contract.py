"""S2 WebView marker checks, separate from source/build/fold/cleanup acceptance.

The caller must retain raw callback bodies and raw uploaded events. This module
never infers native ownership from the uploaded container it is checking.
"""
import hashlib
import json
import uuid
from acceptance_common import require, unique

MARKERS = ("M1", "M2", "M3", "M4")
TTL_MS = 180_000
TTL_NS = TTL_MS * 1_000_000


def identifier(value, label):
    require(isinstance(value, str), "missing " + label)
    try:
        parsed = str(uuid.UUID(value))
    except (ValueError, AttributeError):
        require(False, "invalid " + label)
    require(value == parsed, "noncanonical " + label)
    return value


def integer(value, label):
    require(type(value) is int and value >= 0, "invalid " + label)
    return value


def body(text):
    require(isinstance(text, str), "callback body missing")
    def distinct(pairs):
        out = {}
        for key, value in pairs:
            require(key not in out, "duplicate callback JSON key")
            out[key] = value
        return out
    try:
        envelope = json.loads(text, object_pairs_hook=distinct)
    except (ValueError, TypeError):
        require(False, "malformed callback JSON")
    require(isinstance(envelope, dict) and set(envelope) == {"eventType", "event"}
            and envelope["eventType"] == "view", "wrong browser envelope")
    require(isinstance(envelope["event"], dict), "missing browser event")
    return envelope["event"]


def evaluate_markers(document, expected):
    """Return marker evidence only; no build, topology, backend-inventory or gate claim."""
    require(document.get("identity") == expected["identity"], "stale fixture identity")
    identity = expected["identity"]
    run = identifier(identity.get("run_id"), "run ID")
    identifier(identity.get("nonce"), "nonce")
    require(identity.get("arm") in ("A", "B"), "unqualified arm")
    records = document.get("records")
    require(isinstance(records, list) and records, "missing marker evidence")
    for index, record in enumerate(records, 1):
        require(isinstance(record, dict) and record.get("sequence") == index,
                "missing, repeated or reordered evidence")
        integer(record.get("monotonic_ns"), "native monotonic timestamp")
        integer(record.get("wall_ms"), "native wall timestamp")
        if index > 1:
            require(records[index - 2]["monotonic_ns"] <= record["monotonic_ns"],
                    "reversed native monotonic evidence")
    def one(kind, **fields):
        return unique([r for r in records if r.get("kind") == kind
                       and all(r.get(k) == v for k, v in fields.items())], kind + str(fields))
    def before(a, b):
        require(a["sequence"] < b["sequence"], "assertion after critical boundary")
    def elapsed(later, earlier, greater):
        mono = later["monotonic_ns"] - earlier["monotonic_ns"]
        wall = later["wall_ms"] - earlier["wall_ms"]
        require((mono > TTL_NS and wall > TTL_MS) if greater else
                (0 <= mono < TTL_NS and 0 <= wall < TTL_MS), "inactive/active TTL bracket failed")

    owner = {}
    session = None
    for name in ("NativeA", "NativeB"):
        start = one("native-start", name=name)
        ready = one("native-ready", name=name)
        mapper = unique([r for r in records if r.get("sequence") == ready.get("mapper_sequence")],
                        "independent native mapper")
        require(mapper.get("kind") == "native-view", "readiness is not a mapper observation")
        event = json.loads(mapper.get("event_json", "null"))
        require(isinstance(event, dict) and event.get("type") == "view", "missing actual native view")
        view, current_session = event.get("view", {}), event.get("session", {})
        vid = identifier(view.get("id"), "native view ID")
        sid = identifier(current_session.get("id"), "native session ID")
        require(view.get("name") == name and view.get("is_active") is True
                and current_session.get("has_replay") is True, "native owner not active/Replay eligible")
        require(event.get("application", {}).get("id") == expected["application_id"],
                "foreign native application")
        require(ready.get("view_id") == vid and ready.get("session_id") == sid,
                "call-site owner differs from mapper")
        require(session is None or session == sid, "native session changed")
        session = sid
        before(start, mapper)
        before(mapper, ready)
        owner[name] = {"start": start, "ready": ready, "id": vid}
    require(owner["NativeA"]["id"] != owner["NativeB"]["id"], "native occurrences alias")
    a, b = owner["NativeA"], owner["NativeB"]
    open_pose, closed_pose = one("fold-complete", phase="open"), one("fold-complete", phase="closed")
    before(a["ready"], open_pose)
    before(open_pose, b["start"])
    before(b["ready"], closed_pose)
    # These references must be independently checked by the existing fold runner.
    for pose in (open_pose, closed_pose):
        require(isinstance(pose.get("proof_sha256"), str) and len(pose["proof_sha256"]) == 64,
                "missing separately retained fold proof")
    frozen = {m: one("envelope-frozen", marker=m) for m in MARKERS}
    detached = one("detached", webview="A")
    require(detached.get("window") is None, "WebView A remains attached")
    before(b["ready"], detached)
    callbacks = [r for r in records if r.get("kind") == "webkit-callback"]
    require([r.get("marker") for r in callbacks] == list(MARKERS), "callback inventory differs")
    browser, webviews = [], {}
    for marker, callback in zip(MARKERS, callbacks):
        emission, ack = one("emit-before", marker=marker), one("writer-ack", marker=marker)
        before(emission, callback)
        before(callback, ack)
        event = body(callback.get("body_json"))
        before(frozen[marker], emission)
        require(callback["body_json"] == frozen[marker].get("body_json"), "payload was redated/replaced")
        date = integer(event.get("date"), "Browser event date")
        require(date == frozen[marker]["wall_ms"], "Browser date is not its captured generation time")
        require(event.get("type") == "view" and event.get("session", {}).get("has_replay") is True,
                "wrong Browser event/Replay type")
        view = event.get("view", {})
        require(view.get("name") == marker and view.get("is_active") is False,
                "Browser marker/activity differs")
        require(type(view.get("time_spent")) is int and view["time_spent"] == 1_000_000
                and view.get("loading_type") == "initial_load"
                and event.get("_dd") == {"format_version": 2, "document_version": 1},
                "Browser duration/loading/version differs")
        require(all(type(view.get(family, {}).get("count")) is int
                    and view[family]["count"] == 0
                    for family in ("action", "resource", "error", "long_task")),
                "Browser marker counters differ")
        vid = identifier(event.get("view", {}).get("id"), "Browser view ID")
        require(callback.get("view_id") == emission.get("view_id") == ack.get("view_id") == vid,
                "callback/emission/acknowledgement identity differs")
        require(event.get("context", {}).get("probe") == {"run_id": run, "marker": marker},
                "stale callback run/marker")
        require(event.get("source") == "browser" and event.get("service") == expected["browser_service"],
                "Browser source/service changed")
        require(event.get("application", {}).get("id") == "browser-application"
                and event.get("session", {}).get("id") == "browser-session", "missing replacement discriminator")
        webview = "B" if marker == "M2" else "A"
        pointer = callback.get("webview_identity")
        require(isinstance(pointer, str) and pointer, "missing actual WKWebView identity")
        require(webview not in webviews or webviews[webview] == pointer, "retained WebView instance changed")
        webviews[webview] = pointer
        document_ready = one("web-document-ready", webview=webview)
        before(document_ready, emission)
        require(callback.get("document_id") == document_ready.get("document_id"), "restored WebKit document")
        attached = marker in ("M1", "M2")
        require((callback.get("window") == expected["window"] if attached else callback.get("window") is None)
                and callback.get("scene") == (expected["scene"] if attached else None), "actual attachment differs")
        live = a if marker == "M1" else b
        before(live["ready"], emission)
        require(emission.get("live_view_id") == live["id"], "pre-emission native owner changed")
        if marker == "M1":
            elapsed(frozen[marker], a["ready"], greater=True)
            before(ack, open_pose)
        elif marker == "M2":
            before(b["ready"], frozen[marker])
            before(callback, detached)
        else:
            before(a["ready"], frozen[marker])
            before(frozen[marker], open_pose)
            before(frozen[marker], b["start"])
            before(detached, emission)
            if marker == "M3":
                elapsed(ack, b["start"], greater=False)
                before(ack, closed_pose)
            else:
                before(closed_pose, emission)
                elapsed(emission, b["ready"], greater=True)
        raw = ack.get("event_json")
        require(isinstance(raw, str) and hashlib.sha256(raw.encode()).hexdigest() == ack.get("event_sha256"),
                "writer acknowledgement is not bound to raw event")
        uploaded = json.loads(raw)
        require(uploaded.get("view", {}).get("id") == vid
                and uploaded.get("application", {}).get("id") == expected["application_id"]
                and uploaded.get("session", {}).get("id") == session, "uploaded identity replacement failed")
        require(uploaded.get("source") == "browser" and uploaded.get("service") == expected["browser_service"],
                "Browser output identity changed")
        require(uploaded.get("context", {}).get("probe") == event["context"]["probe"], "writer acknowledgement reused")
        require(uploaded.get("view") == event.get("view") and uploaded.get("_dd") == event.get("_dd")
                and uploaded.get("session", {}).get("has_replay") is True, "Browser payload fields changed")
        corrected_date = integer(uploaded.get("date"), "corrected Browser date")
        if marker in ("M1", "M3", "M4"):
            require(a["ready"]["wall_ms"] < corrected_date < b["start"]["wall_ms"],
                    "corrected old event is outside A timestamp bracket")
        else:
            require(corrected_date > b["ready"]["wall_ms"], "fresh B event predates B ownership")
        wanted = a["id"] if marker == "M1" or (marker == "M3" and identity["arm"] == "B") else b["id"] if marker == "M2" else None
        container = uploaded.get("container")
        if wanted is None:
            require(container is None, "expired native owner retained or B inherited", "FAIL")
        else:
            require(container == {"source": "ios", "view": {"id": wanted}}, "exact native container differs", "FAIL")
        browser.append({"marker": marker, "view_id": vid, "container_id": wanted,
                        "raw_event_sha256": ack["event_sha256"]})
    require(len(set(webviews.values())) == 2, "native WebViews alias")
    require(len({r["view_id"] for r in browser}) == 4
            and not ({r["view_id"] for r in browser} & {a["id"], b["id"]}), "browser/native IDs alias")
    disabled, released = one("tracking-disabled", webview="A"), one("weak-release", webview="A")
    before(one("writer-ack", marker="M4"), disabled)
    before(disabled, released)
    require(released.get("is_nil") is True, "detached WebView still retained", "FAIL")
    return {"state": "MARKERS_QUALIFIED", "session_id": session, "native_owners": {k: v["id"] for k, v in owner.items()},
            "browser_markers": browser, "remaining": ["source/build binding", "independent fold proofs", "complete backend inventory", "cleanup"]}
