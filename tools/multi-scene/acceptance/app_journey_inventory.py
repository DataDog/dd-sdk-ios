"""Offline F08 inventory guards; no native acceptance, transport or run admission.

Inputs are decoded full RUM rows and independently captured query receipts.
The future collector must qualify that decoding and bind native phase evidence.
Available backend view revisions are retained, not treated as all mapper updates.
"""
from collections import Counter
import copy
import re
import uuid

from acceptance_common import canonical, digest, require

SWIFTUI_NAMES = {"LoginView", "ServiceList", "ServiceDetail"}
FAMILIES = {"view", "action", "resource", "error", "long_task", "vital", "operation", "session"}


def field(value, path, default=None):
    """Accept nested or flattened backend fields, rejecting ambiguous aliases."""
    values = []

    def walk(obj, parts):
        if not isinstance(obj, dict):
            return
        for size in range(1, len(parts) + 1):
            key = ".".join(parts[:size])
            if key in obj:
                if size == len(parts):
                    values.append(obj[key])
                else:
                    walk(obj[key], parts[size:])

    walk(value, path.split("."))
    require(len(values) <= 1, "ambiguous field: " + path)
    return values[0] if values else default


def identifier(value):
    try:
        valid = isinstance(value, str) and str(uuid.UUID(value)) == value.lower()
    except (ValueError, AttributeError):
        valid = False
    require(valid, "invalid RUM identifier")
    return value


def source(row):
    attributes = row["attributes"]
    outer, inner = attributes.get("source"), field(attributes["custom"], "source")
    require(outer is None or inner is None or outer == inner, "conflicting event source")
    value = outer if outer is not None else inner
    require(value in {"ios", "browser"}, "unclassified event source")
    return value


def inventory(receipt, request, *, row_limit, page_limit):
    """Preserve every row; count alone cannot replace terminal pagination."""
    require(set(request) == {"run_id", "nonce", "query", "from", "to"}, "incomplete query identity")
    require(all(isinstance(v, str) and v for v in request.values()), "invalid query identity")
    require(receipt.get("request") == request, "stale or foreign query receipt")
    require(type(row_limit) is int and row_limit > 0 and type(page_limit) is int and page_limit > 0,
            "invalid inventory bounds")
    pages = receipt.get("pages")
    require(isinstance(pages, list) and 1 <= len(pages) <= page_limit, "missing or excessive pages")
    rows = []
    for index, page in enumerate(pages):
        require(type(page.get("start_at")) is int and page["start_at"] == len(rows), "page offset differs")
        require(page.get("truncated") is False, "truncated or unqualified page")
        batch = page.get("rows")
        require(isinstance(batch, list), "missing raw rows")
        require(bool(batch) == (index < len(pages) - 1), "missing empty terminal page")
        rows.extend(batch)
        require(len(rows) <= row_limit, "inventory exceeds frozen limit")
    ids = [r.get("id") for r in rows]
    require(all(isinstance(x, str) and x for x in ids) and len(set(ids)) == len(ids), "missing or duplicate raw ID")
    require(type(receipt.get("count")) is int and receipt["count"] == len(rows), "count/inventory mismatch")
    require(all(isinstance(r.get("attributes", {}).get("custom"), dict) for r in rows), "projected or malformed raw row")
    return copy.deepcopy(rows)


def native_partition(complete, native):
    """Broad application/session rows must also contain the full native query."""
    def payload(row):
        a = row["attributes"]
        return canonical(dict(custom=a["custom"], source=source(row),
                              client_time=a.get("client_time"), sdk_version=field(a, "tag.sdk_version")))

    # Search-envelope IDs are stable only inside one response, not across queries.
    require(len({r["id"] for r in native}) == len(native), "duplicate native raw ID")
    expected = Counter(payload(r) for r in complete if source(r) == "ios")
    actual = Counter(payload(r) for r in native)
    require(expected == actual, "native/broad session inventories disagree")


def normalized_path(view, explicit_swiftui):
    path = view["url"]
    if view["id"] not in explicit_swiftui:
        return path
    name = explicit_swiftui[view["id"]]
    require(view["source"] == "ios" and view["name"] == name and name in SWIFTUI_NAMES,
            "unverified SwiftUI path normalization")
    match = re.fullmatch(re.escape(name) + r"/(0|-?[1-9][0-9]*)", path or "")
    require(match and -(2 ** 63) <= int(match[1]) < 2 ** 63, "unrecognized SwiftUI hash path")
    return name + "/<process-hash>"


def reduce(rows, identity, *, prior_sessions=(), explicit_swiftui=None):
    """Build exact ID edges and an occurrence comparison; never certify a run.

identity freezes application/session and a service + SDK version for each source.
Browser values are independent: the bridge does not replace them with native ones.
"""
    explicit_swiftui = explicit_swiftui or {}
    application, session = identifier(identity["application_id"]), identifier(identity["session_id"])
    require(session not in prior_sessions, "restored session")
    opaque = [row.get("id") for row in rows]
    require(len(set(opaque)) == len(opaque) and all(opaque), "duplicate raw event")
    views, events, reducers = {}, [], []
    for row in rows:
        attributes, payload = row["attributes"], row["attributes"]["custom"]
        origin, family = source(row), field(payload, "type")
        require(family in FAMILIES, "unclassified telemetry family")
        partition = identity["sources"].get(origin)
        require(partition is not None, "unfrozen source partition")
        require(field(payload, "application.id") == application and field(payload, "session.id") == session,
                "foreign application/session")
        require(field(payload, "service") == partition["service"] and
                field(attributes, "tag.sdk_version") == partition["sdk_version"], "source identity differs")
        require(field(payload, "session.type") == "user", "non-user session")
        date = attributes.get("client_time")
        require(type(date) in (int, float) and identity["from_ms"] <= date <= identity["to_ms"],
                "stale or future SDK date")
        if family == "session":
            require(field(payload, "_dd.origin") == "reducer", "unclassified session row")
            reducers.append(row)
            continue
        owner = field(payload, "view.id")
        if owner is not None:
            identifier(owner)
        if family == "view":
            identifier(owner)
            version = field(payload, "_dd.document_version")
            active = field(payload, "view.is_active")
            require(type(version) is int and version > 0 and type(active) is bool, "invalid view revision")
            name, url = field(payload, "view.name"), field(payload, "view.url")
            require(isinstance(name, str) and isinstance(url, str), "missing view identity")
            fixed = dict(id=owner, source=origin, name=name, url=url, time=date)
            view = views.setdefault(owner, dict(fixed, revisions={}))
            require(all(view[k] == v for k, v in fixed.items()), "view identity changed between revisions")
            require(version not in view["revisions"], "duplicate view revision")
            view["revisions"][version] = row
        else:
            require(family != "action" or owner is not None, "action missing its exact view owner")
            require(field(payload, "error.is_crash", False) is False, "crash reported", "FAIL")
            events.append(dict(raw_id=row["id"], family=family, source=origin, owner=owner, payload=payload))
    require(set(explicit_swiftui) <= set(views), "missing verified SwiftUI occurrence")
    resource_ids = []
    for event in events:
        require(event["owner"] is None or event["owner"] in views, "missing or foreign view owner")
        if event["owner"] is not None:
            require(views[event["owner"]]["source"] == event["source"], "event crosses native/browser owner domains")
        if event["family"] == "resource":
            resource_ids.append(identifier(field(event["payload"], "resource.id")))
    require(len(set(resource_ids)) == len(resource_ids), "duplicate Resource ID")
    require(len(reducers) == 1, "missing or ambiguous reducer")
    reducer = reducers[0]["attributes"]["custom"]
    require(type(field(reducer, "session.view.count")) is int and
            field(reducer, "session.view.count") == len(views), "unsettled view reducer count")
    actions = [e for e in events if e["family"] == "action"]
    require(type(field(reducer, "session.action.count")) is int and
            field(reducer, "session.action.count") == len(actions), "unsettled action reducer count")
    require(type(field(reducer, "session.crash.count")) is int and
            field(reducer, "session.crash.count") == 0, "session crash or missing crash count")
    ordered = sorted(views.values(), key=lambda v: v["time"])
    require(len({v["time"] for v in ordered}) == len(ordered), "ambiguous SDK occurrence order needs native evidence")
    mapping = {view["id"]: index for index, view in enumerate(ordered)}
    projection = []
    for view in ordered:
        latest = view["revisions"][max(view["revisions"])]
        projection.append(dict(source=view["source"], name=view["name"],
                               url=normalized_path(view, explicit_swiftui),
                               active=field(latest["attributes"]["custom"], "view.is_active")))
    action_graph = []
    for action in actions:
        p = action["payload"]
        identifier(field(p, "action.id"))
        name, kind = field(p, "action.target.name"), field(p, "action.type")
        require(isinstance(name, str) and isinstance(kind, str), "incomplete action identity")
        action_graph.append(dict(source=action["source"], name=name, kind=kind, owner=mapping[action["owner"]]))
    require(len({field(a["payload"], "action.id") for a in actions}) == len(actions), "duplicate action ID")
    graph = dict(views=projection, actions=sorted(action_graph, key=canonical),
                 downstream_owners=sorted([(e["family"], e["source"], mapping.get(e["owner"], -1))
                                           for e in events if e["family"] != "action"]))
    return dict(status="OFFLINE_INVENTORY_ONLY", raw_rows=copy.deepcopy(rows), raw_digest=digest(rows),
                views=views, events=events, graph=graph, family_counts=dict(Counter(field(r["attributes"]["custom"], "type") for r in rows)),
                native_callbacks_verified=False, complete_mapper_revisions_verified=False,
                remaining="Native phases/capture, account bindings, backend transport, detailed downstream semantics, browser attachment and cleanup still require qualification.")


def compare(baseline, candidate):
    require(baseline["graph"] == candidate["graph"], "occurrence/owner graph differs", "FAIL")
    return {"status": "GRAPH_MATCH_REVISION_AND_PAYLOAD_REVIEW_REQUIRED", "runtime_acceptance": False,
            "revision_comparison": "NOT_PERFORMED", "non_owner_payload_comparison": "NOT_PERFORMED",
            "limits": "Retain raw revisions and all non-owner fields for classification; this is not native or release acceptance."}


def browser_container(result, browser_id, native_id):
    """Check persisted identity only; active-at-dispatch needs separate native proof."""
    views = result["views"]
    require(browser_id != native_id and browser_id in views and native_id in views, "browser/native ID substitution")
    browser, native = views[browser_id], views[native_id]
    require(browser["source"] == "browser" and native["source"] == "ios" and
            native["name"] == "DashboardDetails", "wrong browser/native view identity")
    latest = native["revisions"][max(native["revisions"])]
    require(field(latest["attributes"]["custom"], "session.has_replay") is True,
            "Replay eligibility unavailable; container coverage unmet", "INCONCLUSIVE")
    for row in result["raw_rows"]:
        payload = row["attributes"]["custom"]
        if source(row) == "browser" and field(payload, "view.id") == browser_id:
            require(field(payload, "container.view.id") == native_id and field(payload, "container.source") == "ios",
                    "wrong or missing exact native container", "FAIL")
    return {"status": "PERSISTED_CONTAINER_MATCH_NATIVE_BOUNDARY_UNVERIFIED", "runtime_acceptance": False}
