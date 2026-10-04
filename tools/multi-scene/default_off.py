"""Grade synthetic default-Off routing traces; preserve raw bytes outside this module."""
import copy
import math

SCENARIOS = {
    "navigation": 1, "retained-resource": 0,
    "rollover-stop": 0, "rollover-inactivity": 0, "rollover-maximum": 0,
    "completion": 1, "completion-mapper-drop": 1, "unknown-manual-completion": 0,
}
DURATION_FIELDS = {
    "view": {"time_spent", "loading_time", "time_to_initial_display", "time_to_full_display"},
    "action": {"loading_time"},
    "resource": {"duration"},
}
ROW_FIELDS = {"phase", "dormant_state", "events", "metadata", "callbacks",
              "pending_writer_completions", "uuid_factory_calls", "cache_clock_reads",
              "inv_factory_calls", "sessions"}

def phases(scenario):
    prefix = ["sdk-init", "start-root"]
    tail = {
        "navigation": ["action", "error", "view-mutation", "start-detail", "stop-detail"],
        "retained-resource": ["resource-start-success", "resource-start-failure", "start-detail", "start-action", "resource-success", "resource-failure", "stop-action", "stop-detail"],
        "rollover-stop": ["stop-session", "restore-action"],
        "rollover-inactivity": ["restore-action"],
        "rollover-maximum": ["keep-active-" + str(x) for x in range(600, 13801, 600)] + ["restore-action"],
        "completion": ["deferred-error", "writer-completed", "writer-completed"],
        "completion-mapper-drop": ["deferred-error"],
        "unknown-manual-completion": ["start-action", "unknown-success-1", "unknown-success-2", "unknown-failure", "stop-action"],
    }
    return prefix + tail[scenario] + ["terminal"]


def semantic_events(trace):
    """Inspect named View/context observations only; raw deltas remain the comparison oracle.

    RUMViewEvent+Update copies owner/session/DD wholesale, diffs View members,
    and replaces context wholesale when changed. Omitted members retain their
    prior observation here; this is not a general backend reconstruction.
    """
    observations, versions, result = {}, {}, []
    for row in trace["rows"]:
        for raw in row["events"]:
            event = copy.deepcopy(raw)
            if event["type"] in {"view", "view_update"}:
                key = (event["session"]["id"], event["view"]["id"])
                version = event.get("_dd", {}).get("document_version")
                require(integer(version) and version > 0, "view-version-schema")
                if key in versions:
                    require(version == versions[key] + 1, "view-version-continuity")
                else:
                    require(event["type"] == "view" and version == 1, "view-first-full-version")
                if event["type"] == "view_update":
                    require(key in observations, "view-delta-baseline-missing")
                    old = observations[key]
                    event["view"] = {**old["view"], **event["view"]}
                    if "context" not in event and "context" in old:
                        event["context"] = copy.deepcopy(old["context"])
                    event["type"] = "view"
                require(type(event["view"].get("name")) is str, "view-baseline-name")
                observations[key], versions[key] = event, version
            result.append(event)
    return result


def completion_progression(trace):
    scenario = trace["scenario"]
    if not scenario.startswith("completion"):
        return
    deferred = next(row for row in trace["rows"] if row["phase"] == "deferred-error")
    drains = [row for row in trace["rows"] if row["phase"] == "writer-completed"]
    selected = [deferred] + drains + [trace["rows"][-1]]
    actual = [(row["pending_writer_completions"], row["callbacks"]) for row in selected]
    expected = [(0, 1), (0, 1)] if scenario == "completion-mapper-drop" else [(2, 0), (1, 0), (0, 1), (0, 1)]
    require(actual == expected, "writer-completion-progression")


def scenario_capture(trace):
    scenario, rows = trace["scenario"], trace["rows"]
    events = semantic_events(trace)
    grouped = {kind: [e for e in events if e["type"] == kind] for kind in ["view", "action", "resource", "error"]}
    expected = {
        "navigation": (1, 0, 1), "retained-resource": (1, 1, 1),
        "rollover-stop": (1, 0, 0), "rollover-inactivity": (1, 0, 0), "rollover-maximum": (24, 0, 0),
        "completion": (0, 0, 1), "completion-mapper-drop": (0, 0, 0), "unknown-manual-completion": (1, 0, 0),
    }
    require(tuple(len(grouped[k]) for k in ["action", "resource", "error"]) == expected[scenario], "scenario-event-inventory")
    require(bool(grouped["view"]), "scenario-view-capture")
    if scenario == "navigation":
        require({e["view"].get("name") for e in grouped["view"]} >= {"root", "detail"}, "navigation-view-capture")
        require(all(e["view"].get("name") == "root" for k in ["action", "error"] for e in grouped[k]), "navigation-owner")
        # AddViewAttributes mutates scope without writing; next navigation emits it.
        boundary = next(row for row in rows if row["phase"] == "start-detail")
        root = next(v for session in rows[1]["sessions"] for v in session["views"] if v["name"] == "root")
        require(any(e["type"] in {"view", "view_update"} and e["view"]["id"] == root["id"] and e.get("context", {}).get("fixture.mutation") == "root" for e in boundary["events"]), "view-mutation-capture")
    elif scenario == "retained-resource":
        for kind in ["resource", "error"]:
            require(grouped[kind][0]["view"].get("name") == "root", "retained-owner")
        action = grouped["action"][0]
        require(action["view"].get("name") == "detail", "action-owner")
        for kind in ["resource", "error"]:
            count = action.get("action", {}).get(kind, {}).get("count")
            require(integer(count) and count == 0, "foreign-action-counter")
    elif scenario == "unknown-manual-completion":
        action = grouped["action"][0]
        require(action["view"].get("name") == "root", "action-owner")
        for kind, expected_count in [("resource", 2), ("error", 1)]:
            count = action.get("action", {}).get(kind, {}).get("count")
            require(integer(count) and count == expected_count, "manual-action-counter")
    elif scenario.startswith("rollover"):
        initial = rows[1]["sessions"]
        final = [x for x in rows[-1]["sessions"] if x["active"]]
        require(len(initial) == len(final) == 1, "rollover-session-inventory")
        old = [v for v in initial[0]["views"] if v["active"] and v["name"] == "root"]
        new = [v for v in final[0]["views"] if v["active"]]
        require(len(old) == len(new) == 1 and new[0]["name"] == "root", "restored-view-capture")
        require(initial[0]["id"] != final[0]["id"] and old[0]["id"] != new[0]["id"], "rollover-identity")
        action = grouped["action"][-1]
        require(action["session"]["id"] == final[0]["id"] and action["view"]["id"] == new[0]["id"], "restored-action-owner")


class Fault(ValueError):
    pass

def require(condition, fault):
    if not condition:
        raise Fault(fault)

def integer(value):
    return type(value) is int and value >= 0

def storage(value, expected_present):
    require(type(value) is dict and set(value) == {"present", "allocated"}, "state-storage-schema")
    require(type(value["present"]) is bool and type(value["allocated"]) is bool, "state-storage-type")
    require(value["present"] == expected_present, "state-storage-presence")
    require(value["allocated"] is False, "off-state-allocation")

def validate(trace, role):
    require(role in {"parent", "current"}, "role")
    require(type(trace) is dict, "trace-schema")
    require(trace.get("terminal") is True, "terminal-inventory-missing")
    require(set(trace) == {"schema_version", "scenario", "terminal", "resolved_mode", "rows"}, "trace-schema")
    require(type(trace["schema_version"]) is int and trace["schema_version"] == 1, "schema-version")
    require(trace["scenario"] in SCENARIOS, "unknown-scenario")
    require(trace["terminal"] is True, "terminal-inventory-missing")
    require(trace["resolved_mode"] is False, "not-resolved-off")
    rows = trace["rows"]
    require(type(rows) is list and len(rows) >= 2, "rows-missing")
    require(rows[-1].get("phase") == "terminal" and sum(row.get("phase") == "terminal" for row in rows) == 1, "terminal-boundary")
    require([row.get("phase") for row in rows] == phases(trace["scenario"]), "scenario-phase-inventory")
    known_sessions, known_views = set(), {}
    prior_callbacks = 0
    event_count = 0
    for row in rows:
        require(type(row) is dict and set(row) == ROW_FIELDS, "row-schema")
        require(type(row["phase"]) is str and row["phase"], "phase")
        for name in ("callbacks", "pending_writer_completions", "uuid_factory_calls", "cache_clock_reads", "inv_factory_calls"):
            require(integer(row[name]), "counter-type")
        require(row["callbacks"] >= prior_callbacks, "callback-count-regressed")
        prior_callbacks = row["callbacks"]
        if trace["scenario"].startswith("completion") and row["phase"] == "deferred-error":
            require(row["callbacks"] == (1 if trace["scenario"] == "completion-mapper-drop" else 0), "completion-boundary")
        require(type(row["events"]) is list and type(row["metadata"]) is list and len(row["events"]) == len(row["metadata"]), "writer-inventory")
        event_count += len(row["events"])
        require(type(row["sessions"]) is list, "sessions-schema")
        for session in row["sessions"]:
            require(type(session) is dict and set(session) == {"id", "active", "views"}, "session-schema")
            require(type(session["id"]) is str and session["id"] and type(session["active"]) is bool, "session-identity")
            known_sessions.add(session["id"])
            require(type(session["views"]) is list, "views-schema")
            for view in session["views"]:
                require(type(view) is dict and set(view) == {"id", "name", "active"}, "view-schema")
                require(type(view["id"]) is str and view["id"] and type(view["name"]) is str and type(view["active"]) is bool, "view-identity")
                require(view["id"] not in known_views or known_views[view["id"]] == (session["id"], view["name"]), "view-owner-changed")
                known_views[view["id"]] = (session["id"], view["name"])
        state = row["dormant_state"]
        require(type(state) is dict and set(state) == {"application", "sessions"}, "dormant-state-schema")
        storage(state["application"], role == "current")
        require(type(state["sessions"]) is list and len(state["sessions"]) == len(row["sessions"]), "state-session-inventory")
        require([x.get("id") for x in state["sessions"]] == [x["id"] for x in row["sessions"]], "state-session-identity")
        for entry in state["sessions"]:
            require(type(entry) is dict and set(entry) == {"id", "storage"}, "state-session-schema")
            storage(entry["storage"], role == "current")
    require(event_count > 0, "empty-events")
    require(rows[-1]["callbacks"] == SCENARIOS[trace["scenario"]], "completion-multiplicity")
    require(rows[-1]["pending_writer_completions"] == 0, "writer-not-settled")
    for row in rows:
        if trace["scenario"].startswith("completion") and row["phase"] == "deferred-error":
            require(row["callbacks"] == (1 if trace["scenario"] == "completion-mapper-drop" else 0), "completion-boundary")
        for event in row["events"]:
            require(type(event) is dict and event.get("type") in {"view", "view_update", "action", "resource", "error"}, "event-schema")
            require(type(event.get("view")) is dict and type(event.get("session")) is dict, "event-owner-schema")
            owner = event["view"].get("id")
            session = event["session"].get("id")
            require(session in known_sessions and owner in known_views and known_views[owner][0] == session, "event-owner")
            if "name" in event["view"]:
                require(event["view"]["name"] == known_views[owner][1], "event-view-name")
    completion_progression(trace)
    scenario_capture(trace)
    return trace

def normalized(trace):
    result = copy.deepcopy(trace)
    for row in result["rows"]:
        del row["dormant_state"]
        for event in row["events"]:
            # Fixed command timestamps and timing metrics are retained raw, diagnostic only.
            event.pop("date", None)
            for family, names in DURATION_FIELDS.items():
                value = event.get(family)
                if isinstance(value, dict):
                    for name in names:
                        value.pop(name, None)
    def numbers(value):
        if type(value) is bool:
            return ("bool", value)
        if type(value) is float:
            require(math.isfinite(value), "nonfinite-number")
            return round(value, 6)
        if isinstance(value, list):
            return [numbers(x) for x in value]
        if isinstance(value, dict):
            return {k: numbers(v) for k, v in value.items()}
        return value
    return numbers(result)

def compare(parent, current):
    try:
        validate(parent, "parent")
        validate(current, "current")
        require(parent["scenario"] == current["scenario"], "scenario-mismatch")
        require(normalized(parent) == normalized(current), "off-semantic-difference")
        return {"state": "PASS_OFF_TRACE_ONLY", "faults": [], "scenario": current["scenario"]}
    except (Fault, KeyError, TypeError, AttributeError) as error:
        fault = str(error) if isinstance(error, Fault) else "malformed-input"
        incomplete = fault in {"terminal-inventory-missing", "terminal-boundary", "rows-missing", "empty-events", "scenario-phase-inventory"}
        return {"state": "INCOMPLETE" if incomplete else "FAIL", "faults": [fault]}


MONITOR_FIELDS = {"owner_reads", "event_context_writes", "publications", "active_view"}
MONITOR_STORAGE = {"monitor_snapshots", "execution_provider", "manual_handler", "manual_route"}
PUBLIC_SCENARIO = "public-monitor-legacy-factory"
PUBLIC_PHASES = ["factory-appear", "public-start", "public-complete", "factory-disappear", "terminal"]


def validate_monitor(trace, revision):
    """Validate the real Monitor observations before the older scope projection.

    The eight deterministic scope scenarios retain their original oracle. The
    additional public/factory scenario supplies the changed outer path. Presence
    of new optional holders differs by source revision; allocated Off state never
    does. Raw observations are preserved by the caller.
    """
    require(revision in {"pr3", "pr4", "pr5"}, "source-revision")
    require(type(trace) is dict and trace.get("terminal") is True, "terminal-inventory-missing")
    require(type(trace.get("rows")) is list and bool(trace["rows"]), "rows-missing")
    previous = []
    captured_sessions, captured_views = set(), {}
    for row in trace["rows"]:
        require(type(row) is dict and set(row) == ROW_FIELDS | MONITOR_FIELDS, "monitor-row-schema")
        for session in row["sessions"]:
            captured_sessions.add(session["id"])
            for view in session["views"]:
                captured_views[view["id"]] = (session["id"], view["name"])
        # A capture can contain SDK-init and the first real View together. The
        # completed ApplicationLaunch scope may already be removed, while its
        # actual full View row still proves the earlier published owner.
        for event in row["events"]:
            if event.get("type") == "view" and type(event.get("view", {}).get("name")) is str:
                session, view = event["session"]["id"], event["view"]["id"]
                owner = (session, event["view"]["name"])
                require(view not in captured_views or captured_views[view] == owner, "view-owner-changed")
                captured_views[view] = owner
        require(integer(row["owner_reads"]) and row["owner_reads"] == 0, "off-owner-read")
        require(integer(row["event_context_writes"]), "event-context-write-counter")
        publications = row["publications"]
        require(type(publications) is list and len(publications) == row["event_context_writes"], "context-publication-count")
        require(publications[:len(previous)] == previous and len(publications) >= len(previous), "context-publication-continuity")
        for value in publications:
            require(type(value) is dict, "context-publication-schema")
            if set(value) == {"cleared"}:
                require(value["cleared"] is True, "context-clear-value")
                continue
            require(set(value) == {"application", "session", "view", "view_name"}, "context-publication-schema")
            require(all(type(value[k]) is str and value[k] for k in ("application", "session")), "context-publication-owner")
            require(all(value[k] is None or type(value[k]) is str for k in ("view", "view_name")), "context-publication-view")
            require(value["application"] == "routing-trace" and value["session"] in captured_sessions, "published-session-owner")
            if value["view"] is not None:
                require(captured_views.get(value["view"]) == (value["session"], value["view_name"]), "published-view-owner")
        active = row["active_view"]
        require(type(active) is dict and set(active) == {"id", "name", "path"}, "active-view-schema")
        require(all(value is None or type(value) is str for value in active.values()), "active-view-value")
        if publications and set(publications[-1]) != {"cleared"}:
            require(active["id"] == publications[-1]["view"] and active["name"] == publications[-1]["view_name"], "published-active-view")
        previous = publications
        dormant = row["dormant_state"]
        require(type(dormant) is dict and set(dormant) == {"application", "sessions"} | MONITOR_STORAGE, "monitor-storage-schema")
        for key in MONITOR_STORAGE:
            storage(dormant[key], revision != "pr3")
    require(bool(previous), "context-publication-missing")
    projection = copy.deepcopy(trace)
    for row in projection["rows"]:
        for key in MONITOR_FIELDS:
            del row[key]
        for key in MONITOR_STORAGE:
            del row["dormant_state"][key]
    if trace.get("scenario") != PUBLIC_SCENARIO:
        validate(projection, "current")  # All three selected sources already have PR3 scope holders.
    else:
        require(set(projection) == {"schema_version", "scenario", "terminal", "resolved_mode", "rows"}, "trace-schema")
        require(type(projection["schema_version"]) is int and projection["schema_version"] == 1, "schema-version")
        require(projection["resolved_mode"] is False, "not-resolved-off")
        rows = projection["rows"]
        require([x["phase"] for x in rows] == PUBLIC_PHASES, "scenario-phase-inventory")
        known_views = {}
        known_sessions = set()
        previous_callbacks = 0
        for row in rows:
            for key in ["callbacks", "pending_writer_completions", "uuid_factory_calls", "cache_clock_reads", "inv_factory_calls"]:
                require(integer(row[key]), "counter-type")
            require(row["callbacks"] >= previous_callbacks, "callback-count-regressed")
            previous_callbacks = row["callbacks"]
            storage(row["dormant_state"]["application"], True)
            require(type(row["sessions"]) is list and type(row["dormant_state"]["sessions"]) is list, "sessions-schema")
            require([x["id"] for x in row["dormant_state"]["sessions"]] == [x["id"] for x in row["sessions"]], "state-session-identity")
            for session in row["dormant_state"]["sessions"]:
                require(type(session) is dict and set(session) == {"id", "storage"}, "state-session-schema")
                storage(session["storage"], True)
            for session in row["sessions"]:
                require(type(session) is dict and set(session) == {"id", "active", "views"}, "session-schema")
                require(type(session["id"]) is str and bool(session["id"]) and type(session["active"]) is bool, "session-identity")
                known_sessions.add(session["id"])
                require(type(session["views"]) is list, "views-schema")
                for view in session["views"]:
                    require(type(view) is dict and set(view) == {"id", "name", "active"}, "view-schema")
                    require(type(view["id"]) is str and bool(view["id"]) and type(view["name"]) is str and type(view["active"]) is bool, "view-identity")
                    require(view["id"] not in known_views or known_views[view["id"]] == (session["id"], view["name"]), "view-owner-changed")
                    known_views[view["id"]] = (session["id"], view["name"])
            require(type(row["events"]) is list and type(row["metadata"]) is list and len(row["events"]) == len(row["metadata"]), "writer-inventory")
        for row in rows:
            for event in row["events"]:
                if event.get("type") == "view" and type(event.get("view", {}).get("name")) is str:
                    view, session = event["view"]["id"], event["session"]["id"]
                    owner = (session, event["view"]["name"])
                    require(view not in known_views or known_views[view] == owner, "view-owner-changed")
                    known_views[view] = owner
            for event in row["events"]:
                require(type(event) is dict and event.get("type") in {"view", "view_update", "action", "resource", "error"}, "event-schema")
                require(type(event.get("session")) is dict and type(event.get("view")) is dict, "event-owner-schema")
                session, view = event["session"].get("id"), event["view"].get("id")
                require(session in known_sessions and view in known_views and known_views[view][0] == session, "event-owner")
                if "name" in event["view"]:
                    require(event["view"]["name"] == known_views[view][1], "event-view-name")
        events = semantic_events(projection)
        grouped = {kind: [e for e in events if e["type"] == kind] for kind in ["view", "action", "resource", "error"]}
        require(bool(grouped["view"]) and {e["view"].get("name") for e in grouped["view"]} >= {"root", "detail"}, "public-view-capture")
        require(all(len(grouped[kind]) == 1 for kind in ["action", "resource", "error"]), "public-event-inventory")
        require(all(grouped[kind][0]["view"].get("name") == "root" for kind in ["action", "resource", "error"]), "public-event-owner")
        require(rows[-1]["callbacks"] == 1 and rows[-1]["pending_writer_completions"] == 0, "public-completion")
    return trace


def compare_monitor(before, after, before_revision, after_revision):
    try:
        require((before_revision, after_revision) in {("pr3", "pr4"), ("pr4", "pr5")}, "comparison-source-pair")
        validate_monitor(before, before_revision)
        validate_monitor(after, after_revision)
        require(before["scenario"] == after["scenario"], "scenario-mismatch")
        require(normalized(before) == normalized(after), "off-semantic-difference")
        return {"state": "PASS_MONITOR_OFF_TRACE_ONLY", "faults": [], "scenario": after["scenario"]}
    except (Fault, KeyError, TypeError, AttributeError, IndexError) as error:
        fault = str(error) if isinstance(error, Fault) else "malformed-input"
        incomplete = fault in {"terminal-inventory-missing", "terminal-boundary", "rows-missing", "empty-events", "scenario-phase-inventory", "context-publication-missing"}
        return {"state": "INCOMPLETE" if incomplete else "FAIL", "faults": [fault]}
