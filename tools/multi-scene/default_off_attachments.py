"""Read declared xcresult attachment manifests; no native or release verdict."""
from pathlib import Path
import hashlib
import json
import math

METHOD_SCENARIOS = {
    "testDefaultOffPublicMonitorAndLegacyFactoryTrace": {"public-monitor-legacy-factory"},
    "testDefaultOffNavigationTrace": {"navigation"},
    "testDefaultOffRetainedResourceTrace": {"retained-resource"},
    "testDefaultOffSessionRolloverTrace": {"rollover-stop", "rollover-inactivity", "rollover-maximum"},
    "testDefaultOffCompletionTrace": {"completion", "completion-mapper-drop"},
    "testDefaultOffUnknownManualCompletionTrace": {"unknown-manual-completion"},
}
ALL_SCENARIOS = set().union(*METHOD_SCENARIOS.values())

class Invalid(ValueError):
    pass

def need(value, reason):
    if not value:
        raise Invalid(reason)

def unique_pairs(pairs):
    value = {}
    for key, item in pairs:
        need(key not in value, "duplicate-json-key")
        value[key] = item
    return value

def invalid_constant(value):
    raise Invalid("nonfinite-json")

def decode(data):
    return json.loads(data, object_pairs_hook=unique_pairs, parse_constant=invalid_constant)

def collect(folder, manifest, device_id, expected_identifiers):
    """expected_identifiers binds exact actual native test IDs to the six source methods.

    Binding that map to the finalized same-run case inventory and frozen binary,
    clean export directory and export receipt belongs to the native consumer.
    This helper never guesses filename decorations or test-identifier aliases.
    """
    try:
        need(type(expected_identifiers) is dict and len(expected_identifiers) == len(METHOD_SCENARIOS) and set(expected_identifiers.values()) == set(METHOD_SCENARIOS), "expected-case-inventory")
        need(type(manifest) is list and len(manifest) == len(METHOD_SCENARIOS), "manifest-case-inventory")
        root = Path(folder).resolve(strict=True)
        seen_cases, seen_files, seen_scenarios, records = set(), set(), set(), []
        for case in manifest:
            need(type(case) is dict and {"testIdentifier", "attachments"} <= set(case) <= {"testIdentifier", "testIdentifierURL", "attachments"}, "case-schema")
            identifier = case["testIdentifier"]
            need(type(identifier) is str and identifier in expected_identifiers and identifier not in seen_cases, "case-identity")
            if "testIdentifierURL" in case:
                need(type(case["testIdentifierURL"]) is str, "case-url-type")
            seen_cases.add(identifier)
            method = expected_identifiers[identifier]
            attachments = case["attachments"]
            need(type(attachments) is list and len(attachments) == len(METHOD_SCENARIOS[method]), "case-attachment-inventory")
            case_scenarios = set()
            for attachment in attachments:
                required = {"exportedFileName", "suggestedHumanReadableName", "isAssociatedWithFailure", "configurationName", "deviceName", "deviceId"}
                optional = {"timestamp", "repetitionNumber", "arguments"}
                need(type(attachment) is dict and required <= set(attachment) <= required | optional, "attachment-schema")
                need(all(type(attachment[key]) is str for key in required - {"isAssociatedWithFailure"}), "attachment-field-type")
                need(attachment["isAssociatedWithFailure"] is False, "failed-attachment")
                need(attachment["deviceId"] == device_id, "attachment-device")
                if "timestamp" in attachment:
                    value = attachment["timestamp"]
                    need(type(value) in {int, float} and math.isfinite(value), "timestamp-type")
                if "repetitionNumber" in attachment:
                    need(type(attachment["repetitionNumber"]) is int and attachment["repetitionNumber"] >= 0, "repetition-type")
                if "arguments" in attachment:
                    need(type(attachment["arguments"]) is list and all(type(x) is str for x in attachment["arguments"]), "arguments-schema")
                name = attachment["exportedFileName"]
                need(Path(name).name == name and name not in {".", ".."} and name not in seen_files, "attachment-path")
                seen_files.add(name)
                path = root / name
                need(not path.is_symlink() and path.resolve(strict=True) == path and path.is_file(), "attachment-path")
                data = path.read_bytes()
                need(0 < len(data) <= 2 * 1024 * 1024, "attachment-size")
                trace = decode(data)
                need(type(trace) is dict and trace.get("schema_version") == 1 and type(trace.get("schema_version")) is int and trace.get("terminal") is True, "trace-envelope")
                scenario = trace.get("scenario")
                need(scenario in METHOD_SCENARIOS[method] and scenario not in seen_scenarios, "attachment-scenario-owner")
                seen_scenarios.add(scenario)
                case_scenarios.add(scenario)
                records.append({"trace": trace, "actual_test_identifier": identifier, "actual_manifest_attachment": attachment, "raw": {"path": str(path), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}})
            need(case_scenarios == METHOD_SCENARIOS[method], "case-scenario-inventory")
        need(seen_cases == set(expected_identifiers) and seen_scenarios == ALL_SCENARIOS, "terminal-inventory")
        return {"state": "PASS_ATTACHMENT_INVENTORY_ONLY", "records": records, "gates_closed": [], "same_run_native_binding_required": True}
    except (Invalid, ValueError, KeyError, TypeError, OSError, OverflowError) as error:
        return {"state": "INCOMPLETE", "faults": [str(error) if isinstance(error, Invalid) else "malformed-input"], "gates_closed": []}
