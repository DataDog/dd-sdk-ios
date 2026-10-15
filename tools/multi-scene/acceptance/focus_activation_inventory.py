"""Offline H04 backend ownership; raw events are never rewritten or discarded."""


def require(value, reason):
    if not value:
        raise ValueError(reason)


def source(attributes, payload):
    outer, inner = attributes.get("source"), payload.get("source")
    require(outer is None or inner is None or outer == inner, "conflicting event source")
    value = outer if outer is not None else inner
    require(isinstance(value, str) and value, "missing event source")
    return value


def validate(local, run_id, rows, count, *, identity, partial=False):
    """Join selected owners and source-backed infrastructure in one full inventory."""
    require(set(identity) == {"application_id", "service", "source"}, "ambiguous backend identity")
    require(all(isinstance(v, str) and v for v in identity.values()), "missing backend identity")
    require(type(count) is int and count == len(rows), "incomplete backend count")
    ids = [row.get("id") for row in rows]
    require(all(isinstance(v, str) and v for v in ids) and len(set(ids)) == len(ids), "duplicate or missing raw ID")
    views = {v["view_id"]: v for v in local["views"]}
    work = {(v["kind"], v["event_id"]): v for v in local["work"]}
    require(len(views) == len(local["views"]) == 6 and len(work) == len(local["work"]) >= 8, "foreign local H04 inventory")
    require(all(v["session_id"] == local["session_id"] for v in [*views.values(), *work.values()]), "foreign local session")
    require(sum(v["name"] == "ApplicationLaunch" for v in views.values()) == 1, "ambiguous launch view")
    seen_views, seen_work, infrastructure = set(), set(), []
    for row in rows:
        attributes = row.get("attributes", {})
        payload = attributes.get("custom", {})
        require(payload.get("application", {}).get("id") == identity["application_id"]
                and payload.get("service") == identity["service"]
                and source(attributes, payload) == identity["source"]
                and payload.get("session", {}).get("id") == local["session_id"], "foreign backend identity")
        outer_service = attributes.get("service")
        require(outer_service is None or outer_service == identity["service"]
                or outer_service == [identity["service"]], "conflicting event service")
        kind, owner = payload.get("type"), payload.get("view", {}).get("id")
        require(kind in {"view", "action", "resource", "session", "long_task", "vital"}, "unexpected backend family/error")
        context = payload.get("context", {})
        require(isinstance(context, dict), "invalid context")
        probe = context.get("probe", {})
        require(isinstance(probe, dict), "invalid probe")
        if "run_id" in probe:
            require(probe["run_id"] == run_id, "foreign explicit probe run")
        if kind != "session":
            require(owner in views, "foreign backend owner")
        if kind == "view":
            observed = dict(view_id=owner, session_id=local["session_id"], name=payload["view"].get("name"))
            require(owner not in seen_views and observed == views[owner], "duplicate/changed backend View")
            if observed["name"] == "ApplicationLaunch":
                infrastructure.append(dict(kind=kind, owner=owner, reason="exact local launch View"))
            else:
                require(probe.get("run_id") == run_id, "missing Home probe run")
            seen_views.add(owner)
        elif kind in {"action", "resource"}:
            require(probe.get("run_id") == run_id, "missing work probe run")
            key = kind, payload.get(kind, {}).get("id")
            observed = dict(kind=kind, event_id=key[1], session_id=local["session_id"], view_id=owner,
                            phase=probe.get("phase"), source_scene=probe.get("source_scene"))
            require(key not in seen_work and observed == work.get(key), "wrong work identity/owner")
            seen_work.add(key)
        elif kind == "session":
            require(owner is None, "unexpected aggregate Session view")
            infrastructure.append(dict(kind=kind, reason="exact local session aggregate"))
        elif kind == "long_task":
            require(probe.get("run_id") == run_id, "missing long-task probe run")
            infrastructure.append(dict(kind=kind, owner=owner, reason="same-run long task on exact local View"))
        else:
            vital = payload.get("vital", {})
            require(vital.get("type") == "app_launch" and vital.get("app_launch_metric") == "ttid"
                    and vital.get("name") == "time_to_initial_display", "unqualified infrastructure Vital")
            infrastructure.append(dict(kind=kind, owner=owner, reason="app_launch/ttid on exact local View"))
    complete = seen_views == set(views) and seen_work == set(work)
    require(complete or partial, "incomplete backend View/work inventory")
    return dict(state="PASS" if complete else "PENDING", raw_count=count,
                view_count=len(seen_views), work_count=len(seen_work), marker_pairs=4 if complete else 0,
                error_crash_count=0, infrastructure=infrastructure, rows_rewritten=0, rows_discarded=0)
