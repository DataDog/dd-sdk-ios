"""Controls for real MCP pagination semantics; no application acceptance."""
import copy
import json
import unittest

from acceptance_common import Rejected
import app_journey_transport as transport


def response(tag, metadata, payload):
    return {"content": [{"type": "text", "text": "<METADATA>" + metadata + "</METADATA><" + tag + ">" +
                         payload + "</" + tag + ">"}]}


def page(rows, total, flag=""):
    return response("JSON_DATA", "<count>" + str(total) + "</count>" + flag,
                    json.dumps(rows) if rows else "\n\n")


def fixture():
    rows = [dict(id="event-" + str(i), attributes=dict(custom={"type": "view", "sdk_version": "3.17.0+example"}))
            for i in range(3)]
    request = dict(run_id="fresh-run", nonce="issued-request", query="scoped-query",
                   **{"from": "2026-09-21T23:00:00Z", "to": "2026-09-21T23:05:00Z"})
    receipt = dict(request=copy.deepcopy(request), count_response=response("TSV_DATA", "<total_buckets>1</total_buckets>", "events\n3"),
                   pages=[dict(start_at=0, response=page(rows[:2], 3)),
                          dict(start_at=2, response=page(rows[2:], 3)),
                          dict(start_at=3, response=page([], 3))])
    return request, receipt, rows


def collect(receipt, request):
    return transport.complete_inventory(receipt, request, row_limit=10, page_limit=4)


class TransportControls(unittest.TestCase):
    def test_query_total_on_partial_and_empty_terminal_pages(self):
        request, receipt, rows = fixture()
        self.assertEqual(collect(receipt, request), rows)
        self.assertEqual(transport.raw_page(receipt["pages"][-1]["response"]), ([], 3))

    def test_independently_empty_inventory(self):
        request, receipt, _ = fixture()
        receipt["pages"] = [dict(start_at=0, response=page([], 0))]
        receipt["count_response"] = response("TSV_DATA", "<total_buckets>0</total_buckets>", "events")
        self.assertEqual(collect(receipt, request), [])

    def test_preserves_raw_fields_including_truncation_words(self):
        request, receipt, _ = fixture()
        rows = [dict(id="raw", attributes=dict(custom={"error": {"message": "response truncated"},
                                                       "sdk_version": "3.17.0+example"}))]
        receipt["pages"] = [dict(start_at=0, response=page(rows, 1)), dict(start_at=1, response=page([], 1))]
        receipt["count_response"] = response("TSV_DATA", "<total_buckets>1</total_buckets>", "events\n1")
        self.assertEqual(collect(receipt, request), rows)

    def test_rejects_counts_offsets_missing_terminal_and_stale_receipts(self):
        request, receipt, rows = fixture()
        mutations = [
            lambda r: r["pages"][-1].update(response=page([], 0)),
            lambda r: r["pages"][0].update(response=page(rows[:2], 2)),
            lambda r: r["pages"][1].update(start_at=1),
            lambda r: r["pages"].pop(),
            lambda r: r.update(count_response=response("TSV_DATA", "<total_buckets>1</total_buckets>", "events\n4")),
            lambda r: r["request"].update(nonce="old-request"),
            lambda r: r.update(error="capture deadline"),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                changed = copy.deepcopy(receipt)
                mutate(changed)
                with self.assertRaises(Rejected):
                    collect(changed, request)

    def test_rejects_truncated_and_malformed_transport(self):
        request, receipt, rows = fixture()
        malformed = [
            page(rows[:2], 3, "<is_truncated>true</is_truncated>"),
            page(rows[:2], 3, "<is_truncated>false</is_truncated><is_truncated>false</is_truncated>"),
            response("JSON_DATA", "<count>3</count><count>3</count>", json.dumps(rows[:2])),
            response("JSON_DATA", "<count>3</count>", '[{"id":"first","id":"duplicate","attributes":{"custom":{}}}]'),
            response("JSON_DATA", "<count>3</count>", '[{"id":"projected"}]'),
            response("JSON_DATA", "<count>3</count>", '{}'),
            dict(isError=True, content=[]),
        ]
        textual = page(rows[:2], 3)
        textual["content"][0]["text"] += " Response was truncated"
        malformed.append(textual)
        for raw in malformed:
            with self.subTest(response=raw):
                changed = copy.deepcopy(receipt)
                changed["pages"][0]["response"] = raw
                with self.assertRaises(Rejected):
                    collect(changed, request)

    def test_rejects_incomplete_or_grouped_aggregate(self):
        request, receipt, _ = fixture()
        for metadata, payload in [("<total_buckets>2</total_buckets>", "events\n3"),
                                  ("<total_buckets>1</total_buckets>", "service\tevents\na\t3"),
                                  ("<total_buckets>1</total_buckets>", "events\n3.0")]:
            with self.subTest(payload=payload):
                changed = copy.deepcopy(receipt)
                changed["count_response"] = response("TSV_DATA", metadata, payload)
                with self.assertRaises(Rejected):
                    collect(changed, request)


if __name__ == "__main__":
    unittest.main()
