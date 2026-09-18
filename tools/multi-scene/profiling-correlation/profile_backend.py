"""Validate the bounded EXP-187 saved MCP profile inventory and sample joins."""
from datetime import datetime, timezone
import hashlib
import json
import math
import re
from urllib.parse import parse_qs, urlparse

from validate import require, rum_page, uuid

FILES = {
    "query": "backend-query.json",
    "service": "backend-profileInventory.json",
    "session": "backend-sessionProfiles.json",
    "joins": "backend-profileJoins.json",
    "profile": "backend-profile.json",
    "name": "backend-name.json",
    "view": "backend-view.json",
    "session_label": "backend-sessionLabel.json",
    "sample_a": "backend-sampleA.json",
    "sample_b": "backend-sampleB.json",
}


def load_evidence(directory):
    raw = {key: (directory / name).read_bytes() for key, name in FILES.items()}
    return ({key: json.loads(value) for key, value in raw.items()},
            {FILES[key]: hashlib.sha256(value).hexdigest() for key, value in raw.items()})


def profile_data(response):
    require(isinstance(response, dict) and not response.get("isError"), "profile MCP error response")
    content = response.get("content")
    require(isinstance(content, list), "missing profile MCP content")
    text = "\n".join(item.get("text", "") for item in content if isinstance(item, dict))
    matches = re.findall(r"<profiling_data>\s*(.*?)\s*</profiling_data>", text, re.S)
    require(len(matches) == 1, "missing or repeated profile response envelope")
    value = json.loads(matches[0])
    require(isinstance(value, dict), "invalid profile response")
    return value


def tags(response):
    rows = profile_data(response)["data"]
    require(isinstance(rows, list), "invalid profile tag inventory")
    values = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get("value"), str) and row["value"],
                "invalid profile tag value")
        require(type(row.get("count")) is int and row["count"] > 0, "invalid profile tag count")
        require(row["value"] not in values, "duplicate profile tag value")
        values[row["value"]] = row["count"]
    return values


def timestamp_ms(value):
    require(isinstance(value, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value),
            "profile query needs an absolute UTC interval")
    date = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return int(date.timestamp()) * 1000


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def sample_value(value):
    require(isinstance(value, dict) and positive(value.get("value")), "empty or nonfinite profile samples")
    require(value.get("unit") in {"nanoseconds", "microseconds", "milliseconds", "seconds", "minutes", "hours"}
            and value.get("isPerMinute") is True, "unexpected wall-time sample units")


def flame(response, query, start, end, vital_id=None):
    data = profile_data(response)
    require(isinstance(data["availableProfileTypes"], list) and "wall-time" in data["availableProfileTypes"],
            "native wall-time samples unavailable")
    require(positive(data["duration"]), "invalid profile duration")
    sample_value(data["totalMatchingValue"])
    stacks = data["sortedStacktracesWithValues"]
    require(isinstance(stacks, list) and stacks, "missing native profile stacks")
    for stack in stacks:
        require(isinstance(stack["stacktrace"], list) and stack["stacktrace"]
                and all(isinstance(frame, str) and frame for frame in stack["stacktrace"]), "empty native stack")
        sample_value(stack["value"])
    link = data["visualizationLink"]["url"]
    parsed = urlparse(link)
    require(parsed.scheme == "https", "invalid profile visualization link")
    if parsed.path == "/api/v2/switch_to_user/" or "/switch_to_user/" in parsed.path:
        next_values = parse_qs(parsed.query).get("next", [])
        require(len(next_values) == 1, "ambiguous profile redirect")
        parsed = urlparse(next_values[0])
    require(parsed.path == "/profiling/explorer", "wrong profile visualization")
    fields = parse_qs(parsed.query)
    expected = {"query": query, "profile_type": "wall-time", "start": str(start), "end": str(end)}
    for key, value in expected.items():
        require(fields.get(key) == [value], "stale or broadened profile query: " + key)
    allowed = {"query", "profile_type", "start", "end", "viz", "my_code", "paused", "attribute", "selection"}
    require(set(fields) <= allowed, "unexpected profile sample filter")
    if vital_id is None:
        require(not (set(fields) & {"attribute", "selection"}), "unexpected aggregate sample selection")
    else:
        require(fields.get("attribute") == ["vital_id"], "wrong sample attribute")
        selection = fields.get("selection", [])
        require(len(selection) == 1 and json.loads(selection[0]) == {"incl": [vital_id]},
                "wrong or broadened sample selection")
        require(data["topAttributeValues"] == {vital_id: data["totalMatchingValue"]},
                "samples belong to another Operation")
    return data


def validate_profiles(receipt, rum_response, evidence):
    query = evidence["query"]
    operations = receipt["observations"]["operations"]
    session_id = operations[0]["sessionID"]
    starts = [operations[0]["vital"]["id"], operations[1]["vital"]["id"]]
    require(query["run_id"] == receipt["runID"] and query["session"] == session_id,
            "stale profile run/session")
    require(query["rum_query"] == "@session.id:" + session_id and
            query["profile_query"] == "service:ios-benchmark", "filtered profile inventory query")
    start, end = timestamp_ms(query["from"]), timestamp_ms(query["to"])
    require(start < end and all(start * 1_000_000 <= op["vital"]["start_ns"] < end * 1_000_000
                               for op in operations), "profile interval excludes native work")
    joins = evidence["joins"]
    require(isinstance(joins, list) and len(joins) == 8, "incomplete profile joins")
    first, second = tags(joins[0]), tags(joins[1])
    require(first == second and len(first) == 1 and list(first.values()) == [1],
            "Operation starts select different or repeated profiles")
    profile_id = next(iter(first))
    inventory = tags(evidence["service"])
    require(len(inventory) == 2 and set(inventory.values()) == {1} and profile_id in inventory,
            "unexpected complete profile inventory")
    require(tags(evidence["session"]) == inventory, "service/session profile inventory differs")
    launch_id = next(value for value in inventory if value != profile_id)
    require(tags(joins[2]) == {"launch": 1} and tags(joins[5]) == {"continuous": 1},
            "launch/continuous profiles collapsed or swapped")
    require(tags(joins[6]) == {value: 1 for value in starts}, "wrong profile start Vital IDs")
    views = {v["name"]: v["id"] for v in receipt["observations"]["views"]}
    require(tags(joins[7]) == {views["EXP187.Finish"]: 1}, "wrong final process view")
    require(tags(evidence["view"]) == {"EXP187.Finish": 1}, "wrong final process view name")
    require(tags(evidence["name"]) == {"exp187.parallel": 2}, "wrong Operation profile labels")
    require(tags(evidence["session_label"]) == {session_id: 1}, "wrong profile session label")
    _, rows = rum_page(rum_response)
    launches = [row["attributes"]["custom"] for row in rows
                if row["attributes"]["custom"]["type"] == "vital"
                and row["attributes"]["custom"]["vital"]["type"] == "app_launch"]
    require(len(launches) == 1, "missing RUM launch identity")
    launch = launches[0]
    ttid_id = uuid(launch["vital"]["id"])
    require(tags(joins[3]) == {ttid_id: 1} and tags(joins[4]) == {views["ApplicationLaunch"]: 1},
            "wrong built-in launch profile owner")
    require(launch["profiling"]["profile_id"] == [launch_id], "wrong built-in launch profile identity")
    profile_query = query["profile_query"] + " profile-id:" + profile_id
    full = flame(evidence["profile"], profile_query, start, end)
    samples = [flame(evidence[key], profile_query, start, end, vital)
               for key, vital in zip(["sample_a", "sample_b"], starts)]
    require(all(sample["duration"] == full["duration"] for sample in samples),
            "sample filters changed profile duration")
    return {"state": "PASS", "continuous_profile_id": profile_id, "launch_profile_id": launch_id,
            "profile_count": 2, "exact_start_ids": starts, "launch_vital_id": ttid_id,
            "nonempty_wall_time_stacks": True, "sample_start_id_joins": 2,
            "query_window": {"from": query["from"], "to": query["to"]},
            "visualizations": [value["visualizationLink"]["url"] for value in [full, *samples]],
            "limits": "Saved MCP inventory/sample proof; exact attachment and physical build/install evidence remain separate."}
