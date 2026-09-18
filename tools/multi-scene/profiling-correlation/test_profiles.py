import copy
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import urlencode

from profile_backend import FILES, load_evidence, timestamp_ms, validate_profiles
from test_backend import backend_fixture, response

PROFILE = "continuous-profile"
LAUNCH = "launch-profile"
TTID = "00000000-0000-0000-0000-000000000099"


def envelope(data):
    return {"content": [{"type": "text", "text": "<profiling_data>" + json.dumps(data) + "</profiling_data>"}]}


def tag_response(values):
    return envelope({"data": [{"value": value, "count": count} for value, count in values.items()]})


def evidence_fixture():
    receipt, rows = backend_fixture()
    rows[8]["attributes"]["custom"]["vital"]["id"] = TTID
    rows[8]["attributes"]["custom"]["profiling"]["profile_id"] = [LAUNCH]
    operations = receipt["observations"]["operations"]
    starts = [op["vital"]["id"] for op in operations[:2]]
    session = operations[0]["sessionID"]
    query = {"run_id": receipt["runID"], "session": session,
             "rum_query": "@session.id:" + session, "profile_query": "service:ios-benchmark",
             "from": "2001-01-01T00:01:00Z", "to": "2001-01-01T00:03:00Z"}

    def flame(vital=None):
        value = {"value": 2.0, "unit": "seconds", "isPerMinute": True}
        fields = {"query": "service:ios-benchmark profile-id:" + PROFILE,
                  "profile_type": "wall-time", "start": str(timestamp_ms(query["from"])),
                  "end": str(timestamp_ms(query["to"])), "viz": "flame_graph",
                  "my_code": "enabled", "paused": "true"}
        if vital:
            fields.update(attribute="vital_id", selection=json.dumps({"incl": [vital]}))
        next_path = "/profiling/explorer?" + urlencode(fields)
        link = "https://app.datadoghq.com/api/v2/switch_to_user/org?" + urlencode({"next": next_path})
        return {"availableProfileTypes": ["wall-time"], "duration": 60e9,
                "totalMatchingValue": value, "topAttributeValues": {vital: value} if vital else {},
                "sortedStacktracesWithValues": [{"stacktrace": ["native frame"], "value": value}],
                "visualizationLink": {"url": link}}

    evidence = {
        "query": query,
        "service": tag_response({PROFILE: 1, LAUNCH: 1}),
        "session": tag_response({PROFILE: 1, LAUNCH: 1}),
        "joins": [tag_response({PROFILE: 1}), tag_response({PROFILE: 1}),
                  tag_response({"launch": 1}), tag_response({TTID: 1}),
                  tag_response({receipt["observations"]["views"][-1]["id"]: 1}),
                  tag_response({"continuous": 1}), tag_response({value: 1 for value in starts}),
                  tag_response({operations[-1]["viewID"]: 1})],
        "name": tag_response({"exp187.parallel": 2}),
        "view": tag_response({"EXP187.Finish": 1}),
        "session_label": tag_response({session: 1}),
        "profile": envelope(flame()),
        "sample_a": envelope(flame(starts[0])),
        "sample_b": envelope(flame(starts[1])),
    }
    return receipt, rows, evidence


def change_data(evidence, key, mutation):
    text = evidence[key]["content"][0]["text"]
    data = json.loads(text.removeprefix("<profiling_data>").removesuffix("</profiling_data>"))
    mutation(data)
    evidence[key] = envelope(data)


class ProfileBackendTests(unittest.TestCase):
    def test_exact_inventory_labels_and_samples_pass(self):
        receipt, rows, evidence = evidence_fixture()
        result = validate_profiles(receipt, response(rows), evidence)
        self.assertEqual(result["state"], "PASS")
        self.assertEqual(result["continuous_profile_id"], PROFILE)
        self.assertEqual(result["sample_start_id_joins"], 2)

    def test_profile_correlation_is_independent_of_rum_link_enrichment(self):
        receipt, rows, evidence = evidence_fixture()
        for row in rows[4:8]:
            row["attributes"]["custom"]["profiling"]["has_profile"] = False
        self.assertEqual(validate_profiles(receipt, response(rows), evidence)["state"], "PASS")

    def test_file_loader_preserves_exact_responses_and_hashes(self):
        receipt, rows, evidence = evidence_fixture()
        with tempfile.TemporaryDirectory() as directory:
            for key, name in FILES.items():
                (Path(directory) / name).write_text(json.dumps(evidence[key]))
            actual, hashes = load_evidence(Path(directory))
            self.assertEqual(actual, evidence)
            self.assertEqual(set(hashes), set(FILES.values()))
            self.assertTrue(all(len(value) == 64 for value in hashes.values()))
            self.assertEqual(validate_profiles(receipt, response(rows), actual)["state"], "PASS")

    def test_combined_cli_requires_complete_evidence_and_retains_physical_gate(self):
        import subprocess
        import sys
        from test_backend import COUNTS
        receipt, rows, evidence = evidence_fixture()
        for mutation in [None, "missing_count", "missing_profile"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for key, name in FILES.items():
                    (root / name).write_text(json.dumps(evidence[key]))
                (root / "receipt.json").write_text(json.dumps(receipt))
                (root / "attachment.json").write_text(json.dumps(receipt["expectedProfileVitals"]))
                (root / "rum.txt").write_text(response(rows))
                (root / "counts.txt").write_text(COUNTS)
                (root / "end.txt").write_text(response([]))
                command = [sys.executable, "-B", str(Path(__file__).with_name("validate.py")),
                           str(root / "receipt.json"), "--run-id", receipt["runID"],
                           "--source-revision", receipt["sourceRevision"],
                           "--attachment", str(root / "attachment.json"),
                           "--rum-response", str(root / "rum.txt"),
                           "--rum-end-response", str(root / "end.txt"),
                           "--profile-artifacts", str(root), "--output", str(root / "summary.json")]
                if mutation != "missing_count":
                    command += ["--rum-counts", str(root / "counts.txt")]
                if mutation == "missing_profile":
                    (root / FILES["sample_b"]).unlink()
                result = subprocess.run(command, capture_output=True, text=True)
                summary = json.loads((root / "summary.json").read_text())
                self.assertEqual(result.returncode, 1 if mutation else 0)
                self.assertEqual(summary["gate_status"], "FAIL" if mutation else "INCONCLUSIVE")
                if mutation is None:
                    self.assertEqual(summary["profile_validation"]["state"], "PASS")
                    self.assertEqual(summary["attachment_validation"], "PASS")
                    self.assertEqual(summary["remaining"], [
                        "independent supported physical capture and frozen source/build/install identity"])

    def test_stale_mismatched_partial_and_filtered_evidence_fails(self):
        mutations = [
            "run", "session", "interval", "relative_time", "inventory_filter", "rum_filter",
            "missing_profile", "extra_profile", "duplicate_profile", "repeated_profile",
            "session_inventory", "missing_join", "split_starts", "collapsed_launch",
            "wrong_launch_vital", "wrong_launch_view", "wrong_launch_profile", "wrong_mode",
            "end_id", "final_view", "final_name", "operation_name", "operation_label_count",
            "session_label", "missing_stacks", "empty_stack", "zero_samples", "nan_samples",
            "wrong_units", "wrong_sample_type", "zero_duration", "different_duration",
            "wrong_sample_id", "wrong_link_profile", "wrong_link_time", "broad_selection",
            "wrong_attribute", "unexpected_filter", "tool_error", "missing_envelope",
            "duplicate_envelope",
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                receipt, rows, e = evidence_fixture()
                op = receipt["observations"]["operations"]
                if mutation == "run": e["query"]["run_id"] += "-old"
                elif mutation == "session": e["query"]["session"] = op[0]["viewID"]
                elif mutation == "interval": e["query"]["from"] = "2002-01-01T00:00:00Z"
                elif mutation == "relative_time": e["query"]["from"] = "now-1h"
                elif mutation == "inventory_filter": e["query"]["profile_query"] += " @vital.id:any"
                elif mutation == "rum_filter": e["query"]["rum_query"] += " @type:vital"
                elif mutation == "missing_profile": e["service"] = tag_response({PROFILE: 1})
                elif mutation == "extra_profile": e["service"] = tag_response({PROFILE: 1, LAUNCH: 1, "extra": 1})
                elif mutation == "duplicate_profile":
                    e["service"] = envelope({"data": [{"value": PROFILE, "count": 1}] * 2})
                elif mutation == "repeated_profile": e["service"] = tag_response({PROFILE: 2, LAUNCH: 1})
                elif mutation == "session_inventory": e["session"] = tag_response({PROFILE: 1})
                elif mutation == "missing_join": e["joins"].pop()
                elif mutation == "split_starts": e["joins"][1] = tag_response({LAUNCH: 1})
                elif mutation == "collapsed_launch": e["joins"][2] = tag_response({"continuous": 1})
                elif mutation == "wrong_launch_vital": e["joins"][3] = tag_response({op[0]["vital"]["id"]: 1})
                elif mutation == "wrong_launch_view": e["joins"][4] = tag_response({op[-1]["viewID"]: 1})
                elif mutation == "wrong_launch_profile":
                    rows[8]["attributes"]["custom"]["profiling"]["profile_id"] = [PROFILE]
                elif mutation == "wrong_mode": e["joins"][5] = tag_response({"launch": 1})
                elif mutation == "end_id":
                    e["joins"][6] = tag_response({op[2]["vital"]["id"]: 1, op[3]["vital"]["id"]: 1})
                elif mutation == "final_view": e["joins"][7] = tag_response({op[0]["viewID"]: 1})
                elif mutation == "final_name": e["view"] = tag_response({"EXP187.StartA": 1})
                elif mutation == "operation_name": e["name"] = tag_response({"wrong": 2})
                elif mutation == "operation_label_count": e["name"] = tag_response({"exp187.parallel": 1})
                elif mutation == "session_label": e["session_label"] = tag_response({op[0]["viewID"]: 1})
                elif mutation == "missing_stacks":
                    change_data(e, "sample_a", lambda d: d.update(sortedStacktracesWithValues=[]))
                elif mutation == "empty_stack":
                    change_data(e, "sample_a", lambda d: d["sortedStacktracesWithValues"][0].update(stacktrace=[]))
                elif mutation in ["zero_samples", "nan_samples"]:
                    change_data(e, "sample_a", lambda d: d["totalMatchingValue"].update(
                        value=0 if mutation == "zero_samples" else float("nan")))
                elif mutation == "wrong_units":
                    change_data(e, "sample_a", lambda d: d["totalMatchingValue"].update(unit="bytes"))
                elif mutation == "wrong_sample_type":
                    change_data(e, "profile", lambda d: d.update(availableProfileTypes=["cpu"]))
                elif mutation == "zero_duration": change_data(e, "profile", lambda d: d.update(duration=0))
                elif mutation == "different_duration": change_data(e, "sample_b", lambda d: d.update(duration=1))
                elif mutation == "wrong_sample_id":
                    change_data(e, "sample_a", lambda d: d.update(topAttributeValues={op[1]["vital"]["id"]: d["totalMatchingValue"]}))
                elif mutation in ["wrong_link_profile", "wrong_link_time", "broad_selection", "wrong_attribute", "unexpected_filter"]:
                    def change_link(d):
                        from urllib.parse import parse_qs, urlparse
                        next_path = parse_qs(urlparse(d["visualizationLink"]["url"]).query)["next"][0]
                        fields = {k: v[0] for k, v in parse_qs(urlparse(next_path).query).items()}
                        if mutation == "wrong_link_profile": fields["query"] += "-stale"
                        elif mutation == "wrong_link_time": fields["start"] = str(int(fields["start"]) - 1000)
                        elif mutation == "broad_selection": fields["selection"] = json.dumps({"incl": [x["vital"]["id"] for x in op[:2]]})
                        elif mutation == "wrong_attribute": fields["attribute"] = "view_id"
                        else: fields["endpoint_filter"] = ".*"
                        d["visualizationLink"]["url"] = "https://app.datadoghq.com/profiling/explorer?" + urlencode(fields)
                    change_data(e, "sample_a", change_link)
                elif mutation == "tool_error": e["profile"]["isError"] = True
                elif mutation == "missing_envelope": e["profile"]["content"][0]["text"] = "empty"
                elif mutation == "duplicate_envelope":
                    e["profile"]["content"].append(copy.deepcopy(e["profile"]["content"][0]))
                with self.assertRaises(ValueError):
                    validate_profiles(receipt, response(rows), e)


if __name__ == "__main__":
    unittest.main()
