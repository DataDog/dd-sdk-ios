"""Join source-bound app capture to exact native and persisted RUM owners.

These pure checks do not launch an app or grant journey/release acceptance.
The runner must separately bind input, phase timing, complete queries and cleanup.
"""
import copy
import hashlib
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "acceptance"))
from acceptance_common import require
from app_journey_inventory import field, identifier, source, native_partition
from s2_webview_runtime import active_display
from capture_contract import prefix, loads, native_owner, MAPPER_FAMILIES


def one(values, label):
    require(len(values) == 1, "missing or ambiguous " + label)
    return values[0]


def event_key(event):
    family = field(event, "type")
    require(family in MAPPER_FAMILIES, "event has no qualified native mapper")
    value = identifier(field(event, family + ".id"))
    if family == "view":
        version = field(event, "_dd.document_version")
        require(type(version) is int and version > 0, "invalid mapper document version")
        return family, value, version
    return family, value


def sealed_stream(raw, checkpoint, identity, configuration, *, process_exited):
    """Retain the actual writer prefix, then validate complete post-exit file bytes."""
    require(process_exited is True, "stream not sealed by observed process exit")
    committed = prefix(raw, checkpoint, identity)
    require(raw.endswith(b"\n"), "partial native tail at process exit")
    readback = dict(schema_version=1, identity=identity, request_id=checkpoint["request_id"],
                    sequence=len(raw.splitlines()), success=True, byte_count=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest())
    full = prefix(raw, readback, identity)
    configured = one([r for r in full["rows"] if r["kind"] == "configured"], "configured process")
    require(configured["fields"] == configuration, "configured process/product differs")
    require(configuration["build_sdk"] == "iphonesimulator27.1" and
            type(configuration["pid"]) is int and configuration["pid"] > 0, "wrong runtime product")
    return dict(full, actual_writer_checkpoint=copy.deepcopy(checkpoint),
                actual_writer_prefix_sha256=committed["prefix_sha256"],
                readback_seal=readback, seal_kind="HOST_READBACK_AFTER_OBSERVED_PROCESS_EXIT")


def mapper_inventory(rows, expected):
    """Keep every mapper revision and dropped event; no last-row-as-owner shortcut."""
    accepted, dropped, views, order = {}, {}, {}, []
    for row in rows:
        if row["kind"] != "mapper":
            continue
        payload = row["fields"]
        event = loads(payload["event_json"])
        require(field(event, "type") == payload["family"], "mapper family differs")
        for path, value in [("application.id", expected["application_id"]),
                            ("session.id", expected["session_id"]), ("service", expected["service"])]:
            require(field(event, path) == value, "foreign mapper " + path)
        require(field(event, "source") == "ios" and field(event, "session.type") == "user", "wrong mapper source/session")
        require(type(event.get("date")) is int, "mapper date missing")
        key = event_key(event)
        require(key not in accepted and key not in dropped, "duplicate mapper event or revision")
        value = dict(sequence=row["sequence"], monotonic_ns=row["monotonic_ns"], event=event)
        if payload["accepted"] is not True:
            require(payload["accepted"] is False and payload["family"] != "view", "invalid mapper result")
            dropped[key] = value
            continue
        accepted[key] = value
        if key[0] != "view":
            continue
        vid, version = key[1:]
        prior = views.get(vid)
        require(version == (field(prior["event"], "_dd.document_version") + 1 if prior else 1),
                "missing local view revision")
        require(type(field(event, "view.is_active")) is bool, "view activity missing")
        if prior:
            require(all(field(prior["event"], path) == field(event, path)
                        for path in ["date", "view.id", "view.name", "view.url"]), "view occurrence identity changed")
        else:
            order.append(vid)
        views[vid] = value
    require(views, "no mapped native views")
    for value in accepted.values():
        owner = identifier(field(value["event"], "view.id"))
        require(owner in views, "mapped event has foreign occurrence owner")
    return dict(accepted=accepted, dropped=dropped, views=views, occurrence_order=order)


def snapshot_owner(rows, snapshot, expected, binding, display_raw, device, *, names):
    require(snapshot in rows and snapshot["kind"] == "snapshot", "unbound native snapshot")
    topology = snapshot["fields"]["topology"]
    require(topology["pid"] == expected["pid"], "native process changed")
    owned = native_owner(topology, binding)
    scene = topology["scene_inventory"][0]
    actual = active_display(loads(display_raw), device)
    pixels = actual["nativeSize"] if actual["currentOrientation"] in ["rot0", "rot180"] else actual["nativeSize"][::-1]
    scale = scene["screen_scale"]
    require(scale == actual["pointScale"] and
            [n * scale for n in scene["screen_bounds"][2:]] == pixels and
            [n * scale for n in owned["bounds"][2:]] == pixels, "owned geometry differs from actual display")
    prior = [row for row in rows if row["sequence"] < snapshot["sequence"]]
    inventory = mapper_inventory(prior, expected)
    active = one([value for value in inventory["views"].values()
                  if field(value["event"], "view.is_active") is True], "independently mapped active view")
    context = one([row for row in prior if row["sequence"] == snapshot["last_context_sequence"]
                   and row["kind"] == "context"], "native context reference")["fields"]
    event = active["event"]
    for key, path in [("application_id", "application.id"), ("session_id", "session.id"),
                      ("view_id", "view.id"), ("view_name", "view.name"), ("view_path", "view.url")]:
        require(context.get(key) == field(event, path), "asynchronous context not settled on mapped owner")
    require(field(event, "view.name") in names, "wrong native screen owner")
    return dict(view_id=event["view"]["id"], mapper_sequence=active["sequence"],
                context_sequence=snapshot["last_context_sequence"], snapshot_sequence=snapshot["sequence"],
                has_replay=context.get("has_replay"), native_window=owned["id"], display_id=actual["uniqueId"])


def submitted_fields(actual, expected, path=""):
    """All submitted leaves survive; backend-only enrichment is retained separately."""
    if isinstance(expected, dict):
        require(isinstance(actual, dict), "backend object differs at " + path)
        for key, value in expected.items():
            require(key in actual, "backend field missing at " + path + key)
            submitted_fields(actual[key], value, path + key + ".")
    else:
        require(type(actual) is type(expected) and actual == expected, "backend payload differs at " + path.rstrip("."))


def backend_event(row):
    attributes = row["attributes"]
    payload = copy.deepcopy(attributes["custom"])
    for key, value in [("date", attributes["client_time"]), ("source", source(row))]:
        require(key not in payload or payload[key] == value, "ambiguous backend " + key)
        payload[key] = value
    return payload


def mapped_backend(rows, native_rows, local, expected, *, pending=True):
    """Reconcile complete query rows with local mapper identities and payloads.

    ddtags and app version are index tags; compare their actual indexed values in
    the caller. Unknown native non-mapper families remain explicit review items.
    """
    native_partition(rows, native_rows)
    state = "PENDING" if pending else "INVALID"
    actual, incidental, browser, reducers = {}, [], [], []
    for row in rows:
        payload = backend_event(row)
        require(field(payload, "application.id") == expected["application_id"] and
                field(payload, "session.id") == expected["session_id"], "foreign persisted application/session")
        if payload["type"] == "session":
            require(field(payload, "_dd.origin") == "reducer", "unknown session event")
            reducers.append(row)
            continue
        if payload["source"] == "browser":
            browser.append(row)
            continue
        require(payload["source"] == "ios" and payload.get("service") == expected["service"] and
                field(row["attributes"], "tag.sdk_version") == expected["backend_sdk_version"], "foreign native source identity")
        require(field(payload, "error.is_crash", False) is False, "persisted crash")
        if payload["type"] not in MAPPER_FAMILIES:
            require(payload["type"] in {"vital", "operation"} and
                    field(payload, "view.id") in local["views"], "unclassified incidental native owner")
            incidental.append(row)
            continue
        key = event_key(payload)
        require(key not in actual and key not in local["dropped"], "duplicate or dropped event persisted")
        require(key in local["accepted"], "backend event absent from complete mapper stream")
        submitted = copy.deepcopy(local["accepted"][key]["event"])
        tags = submitted.pop("ddtags", None)
        version = submitted.pop("version", None)
        if version is not None:
            require(field(row["attributes"], "tag.version") == version, "app version tag differs")
        if tags:
            require(isinstance(tags, str), "invalid submitted tags")
            parsed = {}
            for tag in tags.split(","):
                tag_name, colon, tag_value = tag.partition(":")
                require(colon and tag_name and tag_value and tag_name not in parsed, "ambiguous submitted tags")
                parsed[tag_name] = tag_value
            wanted = dict(service=expected["service"], version=version,
                          sdk_version=expected["compiled_sdk_version"], env=expected["environment"])
            if expected.get("variant") is not None:
                wanted["variant"] = expected["variant"]
            require(parsed == wanted, "submitted tags differ from frozen source configuration")
            indexed = row["attributes"].get("tags")
            require(isinstance(indexed, list), "indexed tags unavailable")
            # Only this source-bound SDK version translation was qualified by
            # the saved F08 transport receipt; no general URL/name normalization.
            wanted["sdk_version"] = expected["backend_sdk_version"]
            require(all(key + ":" + value in indexed for key, value in wanted.items()),
                    "submitted tag missing from backend")
        submitted_fields(payload, submitted)
        actual[key] = row
    require(set(local["accepted"]) - set(actual) <= {key for key in local["accepted"] if key[0] == "view"},
            "accepted non-view mapper inventory incomplete", state)
    for vid, terminal in local["views"].items():
        key = event_key(terminal["event"])
        require(key in actual, "terminal view revision not indexed", state)
    require(len(reducers) <= 1, "ambiguous session reducer")
    require(len(reducers) == 1, "session reducer not indexed", state)
    return dict(state="MAPPER_BACKEND_JOINED_INCIDENTAL_AND_BROWSER_REVIEW_REQUIRED", native_mapped_rows=len(actual),
                available_view_versions={vid:sorted(k[2] for k in actual if k[0] == "view" and k[1] == vid)
                                         for vid in local["views"]},
                accepted_non_view_events=len([k for k in actual if k[0] != "view"]),
                dropped_events=len(local["dropped"]), incidental=incidental, browser=browser, reducer=reducers[0],
                runtime_acceptance=False)
