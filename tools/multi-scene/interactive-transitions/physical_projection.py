"""Offline mapper/search projection assessment; never a runtime acceptance adapter.

Keep the production join strict. This classifier exposes every remaining mismatch
without rewriting the actual rows or substituting submitted values into responses.
"""
import copy
import hashlib
import json
from pathlib import Path

import backend
from acceptance_common import require
from capture_io import bounded_read

contract = backend.contract
EMPTY_VIEW_OBJECTS = {"_dd.replay_stats", "feature_flags", "view.custom_timings"}
# The session reducer is a separate witness, not a source of default view values.
SESSION_FIELDS = {"_dd.session.session_precondition": str, "session.is_active": bool,
                  "session.has_replay": bool}
# RUM schema enum and documented indexed device value; no general case folding.
DEVICE_TYPES = {"tablet": "Tablet"}


def saved_inventory(path):
    """Reassess a completed immutable exchange, without reviving its expired clock."""
    path = Path(path)
    bound, folder = backend.transport.binding(path)
    publication = json.loads((folder / "publication.json").read_bytes())
    response_path = path.with_name(path.name.replace(".request.json", ".response.json"))
    raw = bounded_read(response_path, backend.transport.MAX_RESPONSE * backend.transport.PAGE_LIMIT)
    require(publication["state"] == "COMPLETE_INVENTORY" and
            publication["request_sha256"] == hashlib.sha256(path.read_bytes()).hexdigest() and
            publication["response_sha256"] == hashlib.sha256(raw).hexdigest() and
            publication["deadline"] == bound["deadline"] and
            bound["issued_at"] <= publication["published_at"] < bound["deadline"],
            "original inventory publication was incomplete, changed or late")
    rows = backend.transport.pollable_inventory(json.loads(raw), bound["request"],
        row_limit=bound["row_limit"], page_limit=bound["page_limit"], minimum_rows=bound["minimum_rows"])
    require(type(publication["rows"]) is int and publication["rows"] == len(rows), "published inventory count differs")
    return rows


def differences(actual, submitted, *, view, path="", reducer=None):
    """Finite source-bound omissions only; retain types, presence and raw values."""
    result = []
    if isinstance(submitted, dict) and isinstance(actual, dict):
        for key, value in submitted.items():
            name = path + key
            if key not in actual:
                allowed = view and name in EMPTY_VIEW_OBJECTS and type(value) is dict and value == {}
                change = dict(path=name, disposition="EMPTY_OPTIONAL_OBJECT_OMITTED" if allowed else "UNRESOLVED_OMISSION",
                              submitted=copy.deepcopy(value), actual_present=False)
                if view and name in SESSION_FIELDS and reducer is not None:
                    observed = contract.field(reducer, name)
                    if type(value) is SESSION_FIELDS[name] and type(observed) is type(value) and observed == value:
                        change.update(disposition="SESSION_REDUCER_MATCHED", reducer_actual=copy.deepcopy(observed))
                result.append(change)
            else:
                result.extend(differences(actual[key], value, view=view, path=name + ".", reducer=reducer))
    elif type(actual) is not type(submitted) or actual != submitted:
        name = path.rstrip(".")
        revisions = view and name == "_dd.document_version" and type(actual) is int and type(submitted) is int and min(actual, submitted) > 0
        device = view and name == "device.type" and type(submitted) is str and type(actual) is str and DEVICE_TYPES.get(submitted) == actual
        disposition = "INDEPENDENT_REDUCER_REVISION" if revisions else "SOURCE_DEVICE_ENUM" if device else "UNRESOLVED_VALUE"
        result.append(dict(path=name, disposition=disposition,
                           submitted=copy.deepcopy(submitted), actual_present=True, actual=copy.deepcopy(actual)))
    return result


def tags(row, submitted, expected):
    """Preserve the generic join's exact compiled/indexed tag contract."""
    version, raw = submitted.pop("version", None), submitted.pop("ddtags", None)
    if version is not None:
        require(contract.field(row["attributes"], "tag.version") == version, "app version tag differs")
    if raw:
        require(isinstance(raw, str), "invalid submitted tags")
        values = {}
        for item in raw.split(","):
            key, colon, value = item.partition(":")
            require(colon and key and value and key not in values, "ambiguous submitted tags")
            values[key] = value
        wanted = dict(service=expected["service"], version=version,
                      sdk_version=expected["compiled_sdk_version"], env=expected["environment"])
        if expected.get("variant") is not None: wanted["variant"] = expected["variant"]
        require(values == wanted, "submitted source tags differ")
        indexed = row["attributes"].get("tags")
        require(isinstance(indexed, list), "indexed tags unavailable")
        wanted["sdk_version"] = expected["backend_sdk_version"]
        require(all(k + ":" + v in indexed for k, v in wanted.items()), "submitted indexed tag missing")


def assess(rows, native_rows, local, expected, *, native_evidence=None):
    contract.native_partition(rows, native_rows)
    require(len({r["id"] for r in rows}) == len(rows), "duplicate broad raw ID")
    import physical_witness
    witness = physical_witness.dispatch(*native_evidence, local, expected) if native_evidence is not None else None
    views, events, reducers, incidental, matched_ttid = {}, {}, [], [], []
    for row in rows:
        payload = contract.backend_event(row)
        require(contract.field(payload, "application.id") == expected["application_id"] and
                contract.field(payload, "session.id") == expected["session_id"] and payload["source"] == "ios",
                "foreign persisted application/session/source")
        family = payload["type"]
        if family == "session":
            require(contract.field(payload, "_dd.origin") == "reducer", "unknown session event")
            reducers.append(row)
            continue
        require(payload.get("service") == expected["service"] and
                contract.field(row["attributes"], "tag.sdk_version") == expected["backend_sdk_version"],
                "foreign persisted service/SDK")
        require(contract.field(payload, "error.is_crash", False) is False, "persisted crash")
        require(contract.field(payload, "view.id") in local["views"], "foreign persisted view owner")
        if family not in contract.MAPPER_FAMILIES:
            require(family in {"vital", "operation"}, "unclassified native family")
            if family == "vital" and witness is not None:
                require(not matched_ttid, "duplicate witnessed TTID")
                matched_ttid.append(physical_witness.persisted(row, payload, witness))
            else:
                incidental.append(row)
            continue
        key = contract.event_key(payload)
        if family == "view":
            require(key not in views, "duplicate backend view revision")
            views[key] = row
        else:
            require(key in local["accepted"] and key not in local["dropped"] and key not in events,
                    "unknown, duplicate or dropped persisted event")
            events[key] = row
    require(len(reducers) <= 1, "ambiguous session reducer")
    reducer = contract.backend_event(reducers[0]) if reducers else None
    mismatches, comparisons, terminal_failures = [], [], []
    expected_events = {k for k in local["accepted"] if k[0] != "view"}
    for key in sorted(expected_events - set(events)):
        terminal_failures.append(dict(kind="MISSING_ACCEPTED_EVENT", event=list(key)))
    selected = [(key, row, local["accepted"][key]["event"]) for key, row in events.items()]
    for vid, value in local["views"].items():
        submitted = value["event"]
        require(submitted["view"]["is_active"] is False, "local terminal view is active")
        options = [key for key in views if key[1] == vid]
        if not options:
            terminal_failures.append(dict(kind="MISSING_TERMINAL_VIEW", view_id=vid))
            continue
        require(len(options) == 1, "multiple backend rows for one reduced view require classification")
        key = options[0]
        selected.append((key, views[key], submitted))
        actual = contract.backend_event(views[key])
        for field in ["view.is_active", "view.time_spent"]:
            wanted, observed = contract.field(submitted, field), contract.field(actual, field)
            require(wanted is not None, "local terminal predicate missing")
            if type(wanted) is not type(observed) or wanted != observed:
                terminal_failures.append(dict(kind="TERMINAL_VIEW_NOT_SETTLED", view_id=vid, path=field,
                                              submitted=wanted, actual=observed))
    for key, row, event in selected:
        submitted = copy.deepcopy(event)
        tags(row, submitted, expected)
        changes = differences(contract.backend_event(row), submitted, view=key[0] == "view", reducer=reducer)
        record = dict(event=list(key), raw_id=row["id"], differences=changes)
        if any(c["disposition"] == "SESSION_REDUCER_MATCHED" for c in changes):
            record["session_reducer_raw_id"] = reducers[0]["id"]
        comparisons.append(record)
        mismatches.extend(dict(event=list(key), **change) for change in changes if change["disposition"].startswith("UNRESOLVED"))
    wanted_counts = dict(view=len(local["views"]), action=sum(k[0] == "action" for k in local["accepted"]), crash=0)
    if not reducers:
        terminal_failures.append(dict(kind="MISSING_SESSION_REDUCER"))
    else:
        payload = contract.backend_event(reducers[0])
        for family, wanted in wanted_counts.items():
            observed = contract.field(payload, "session." + family + ".count")
            if type(observed) is not int or observed != wanted:
                terminal_failures.append(dict(kind="SESSION_COUNT_DIFFERS", family=family, submitted=wanted, actual=observed))
    if witness is not None and not matched_ttid:
        terminal_failures.append(dict(kind="MISSING_WITNESSED_TTID"))
    unresolved = bool(mismatches or terminal_failures or incidental)
    return dict(state="SOURCE_CLASSIFICATION_REQUIRED" if unresolved else "OFFLINE_PROJECTION_MATCHED",
                qualification="UNQUALIFIED" if unresolved else "OFFLINE_ONLY", runtime_acceptance=False,
                release_acceptance=False, raw_rows=len(rows), raw_ids=[r["id"] for r in rows],
                comparisons=comparisons, unresolved=mismatches, terminal_failures=terminal_failures,
                matched_ttid=matched_ttid,
                incidental_source_classification_required=[r["id"] for r in incidental],
                expected_session_counts=wanted_counts, gate_closures=[])


def record(cell, broad_path, native_path, output, *, require_ttid_witness=False):
    """Publish one offline assessment from the exact two completed exchanges."""
    import physical_ownership
    from capture_io import atomic, encoded
    cell, output = Path(cell).resolve(strict=True), Path(output).resolve()
    require(not output.exists() and output.parent.is_dir(), "offline output already consumed or unprepared")
    inputs = [Path(value).resolve(strict=True) for value in [broad_path, native_path]]
    require(all(p.parent == cell for p in inputs) and len(set(inputs)) == 2, "foreign/duplicate saved inventory")
    source = json.loads((cell / "native-summary.json").read_bytes())
    identity, expected = source["identity"], source["expected"]
    evidence = backend.capture.rows((cell / "terminal-before-collection.jsonl").read_bytes(), identity["run_id"])
    local = physical_ownership.inventory(evidence, identity)
    require(type(require_ttid_witness) is bool, "invalid TTID witness option")
    base = "@application.id:" + expected["application_id"] + " @session.id:" + expected["session_id"]
    bounds = [backend.transport.binding(p)[0] for p in inputs]
    require([b["request"]["query"] for b in bounds] == [base, base + " service:" + expected["service"] + " source:ios"] and
            all(b["request"]["run_id"] == identity["run_id"] for b in bounds) and
            all(bounds[0]["request"][k] == bounds[1]["request"][k] for k in ["from", "to"]), "saved query scope differs")
    inventories = [saved_inventory(p) for p in inputs]
    result = assess(*inventories, local, expected, native_evidence=(evidence, identity) if require_ttid_witness else None)
    try:
        strict = backend.join(*inventories, local, expected, pending=False)
        strict_result = dict(state="JOINED_SOURCE_CLASSIFICATION_REQUIRED", release_acceptance=strict["release_acceptance"])
    except backend.Rejected as error:
        strict_result = dict(state=error.state, reason=str(error))
    paths = [cell / name for name in ["summary.json", "native-summary.json", "terminal-before-collection.jsonl"]]
    for path in inputs:
        paths.extend([path, path.with_name(path.name.replace(".request.json", ".response.json")),
                      path.with_name(path.name.removesuffix(".request.json")) / "publication.json"])
    result.update(original_summary_sha256=hashlib.sha256((cell / "summary.json").read_bytes()).hexdigest(),
                  strict_join_unchanged=strict_result,
                  inputs=[dict(path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths])
    atomic(output, encoded(result))
    return result


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["cell", "broad", "native", "output"]: parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--ttid-witness", action="store_true", help="Require an independently recorded typed TTID dispatch")
    args = parser.parse_args()
    value = record(args.cell, args.broad, args.native, args.output, require_ttid_witness=args.ttid_witness)
    print(json.dumps({k: value[k] for k in ["state", "qualification", "raw_rows", "release_acceptance", "gate_closures"]}))
