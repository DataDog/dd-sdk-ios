"""Backend-only ownership check for the existing H06 inferred Operation fixture.

Call sites and marker mappers cannot observe Operation vitals. Join the indexed
raw steps to reduced Operations using vital/operation IDs and independently
captured scene view IDs. Custom context can be enriched with completion values;
it is not the start-owner oracle. Native call order, topology, release and full
session acceptance remain separate.
"""
from uuid import UUID

from acceptance_common import require

NAME = "multi_scene_probe_navigation"
OWNERS = {
    "cross-success": ("scene-A", "scene-B", None),
    "cross-failure": ("scene-A", "scene-B", "error"),
    "parallel-alpha": ("scene-A", "scene-A", None),
    "parallel-beta": ("scene-B", "scene-B", None),
}


def object_value(value, label):
    require(isinstance(value, dict), label + " must be an object")
    return value


def identifier(value, label):
    require(isinstance(value, str), label + " must be a UUID")
    try:
        valid = str(UUID(value)) == value
    except ValueError:
        valid = False
    require(valid, label + " must be a canonical UUID")
    return value


def validate(rows, *, run_id, session_id, scene_views, count, application_id, service):
    """Validate the complete query slice: operation + operation_step only."""
    require(isinstance(run_id, str) and run_id, "run ID missing")
    identifier(session_id, "session")
    identifier(application_id, "application")
    require(isinstance(service, str) and service, "service missing")
    require(isinstance(scene_views, dict) and set(scene_views) == {"scene-A", "scene-B"},
            "two independent scene view owners required")
    views = {scene: identifier(view, "scene view") for scene, view in scene_views.items()}
    require(len(set(views.values())) == 2, "scene views alias")
    require(isinstance(rows, list) and type(count) is int and count == len(rows) == 12,
            "incomplete Operation slice")
    event_ids, vital_ids, operation_ids = set(), set(), set()
    steps, operations = {}, {}
    keys = {run_id + "-" + instance: instance for instance in OWNERS}
    for row in rows:
        row = object_value(row, "backend row")
        event_id = row.get("id")
        require(isinstance(event_id, str) and event_id and event_id not in event_ids,
                "missing or duplicate backend event")
        event_ids.add(event_id)
        attributes = object_value(row.get("attributes"), "backend attributes")
        payload = object_value(attributes.get("custom"), "backend payload")
        session = object_value(payload.get("session"), "session")
        require(session.get("id") == session_id and session.get("type") == "user",
                "foreign Operation session or session type")
        require(object_value(payload.get("application"), "application").get("id") == application_id
                and payload.get("service") == attributes.get("service") == service
                and attributes.get("source") == "ios", "foreign Operation application, service or source")
        context = object_value(payload.get("context"), "context")
        require(object_value(context.get("probe"), "probe").get("run_id") == run_id,
                "foreign Operation run")
        vital = object_value(payload.get("vital"), "vital")
        operation = object_value(payload.get("operation"), "operation")
        vital_id = identifier(vital.get("id"), "vital ID")
        operation_id = identifier(operation.get("id"), "operation ID")
        kind = payload.get("type")
        if kind == "vital":
            require(vital.get("type") == "operation_step" and vital.get("name") == NAME,
                    "foreign vital family or name")
            key, step = vital.get("operation_key"), vital.get("step_type")
            require(isinstance(key, str) and key in keys and step in ("start", "end"),
                    "unknown Operation key or step")
            pair = (key, step)
            require(pair not in steps and vital_id not in vital_ids,
                    "duplicate raw Operation step or vital")
            vital_ids.add(vital_id)
            instance = keys[key]
            start, end, failure = OWNERS[instance]
            view = object_value(payload.get("view"), "raw step view").get("id")
            require(view == views[start if step == "start" else end],
                    "wrong raw Operation step owner", "FAIL")
            require(vital.get("failure_reason") == (failure if step == "end" else None),
                    "wrong raw Operation failure reason", "FAIL")
            steps[pair] = (vital_id, operation_id)
        elif kind == "operation":
            key = operation.get("operation_key")
            require(isinstance(key, str) and key in keys and key not in operations
                    and operation_id not in operation_ids, "duplicate or unknown reduced Operation")
            operation_ids.add(operation_id)
            start, end, failure = OWNERS[keys[key]]
            require(operation.get("name") == NAME
                    and operation.get("status") == ("failure" if failure else "success")
                    and operation.get("failure_reason") == failure,
                    "wrong reduced Operation name, status or failure", "FAIL")
            require(object_value(operation.get("start_view"), "start view").get("id") == views[start]
                    and object_value(operation.get("end_view"), "end view").get("id") == views[end],
                    "wrong reduced Operation endpoint owner", "FAIL")
            operations[key] = (vital_id, operation_id)
        else:
            require(False, "unexpected event in the Operation query slice")

    expected_steps = {(key, step) for key in keys for step in ("start", "end")}
    require(set(steps) == expected_steps and set(operations) == set(keys),
            "missing raw or reduced Operation")
    for key, reduced in operations.items():
        require(reduced == steps[(key, "start")]
                and reduced[1] == steps[(key, "end")][1],
                "raw/reduced Operation identity join differs", "FAIL")
    return {
        "state": "PASS", "scope": "backend Operation ownership only",
        "raw_steps": 8, "reduced_operations": 4,
        "session_id": session_id, "scene_views": views,
        "application_id": application_id, "service": service, "source": "ios",
        "operation_ids": sorted(operation_ids), "vital_ids": sorted(vital_ids),
        "native_call_order_required": True, "physical_topology_required": True,
        "release_acceptance": False,
    }
