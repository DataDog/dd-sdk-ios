"""Decode complete Datadog MCP inventories without changing raw event payloads."""
import csv
import io
import json
import re
import xml.etree.ElementTree as ET

from acceptance_common import require
from app_journey_inventory import inventory


def _unique_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def _body(response, tag):
    require(isinstance(response, dict) and not response.get("isError"), "MCP error")
    text = "\n".join(item["text"] for item in response["content"] if item["type"] == "text")
    metadata = re.findall(r"<METADATA>(.*?)</METADATA>", text, re.S)
    payloads = list(re.finditer("<" + tag + ">(.*?)</" + tag + ">", text, re.S))
    require(len(metadata) == len(payloads) == 1, "missing or ambiguous complete payload")
    payload = payloads[0]
    envelope = text[:payload.start()] + text[payload.end():]
    require(not re.search(r"(?:output|response|data)\s+(?:was\s+)?truncated|truncated\s+(?:output|response)|truncation",
                          envelope, re.I), "textual truncation")
    root = ET.fromstring("<METADATA>" + metadata[0] + "</METADATA>")
    flags = root.findall("is_truncated")
    require(len(flags) <= 1 and all((flag.text or "").strip().lower() == "false" for flag in flags),
            "truncated payload")
    return root, payload.group(1)


def _integer(root, name):
    matches = root.findall(name)
    require(len(matches) == 1 and (matches[0].text or "").strip().isdigit(), "invalid metadata " + name)
    return int(matches[0].text.strip())


def raw_page(response):
    """MCP count is the query total, including on an empty terminal page."""
    metadata, payload = _body(response, "JSON_DATA")
    rows = json.loads(payload, object_pairs_hook=_unique_keys) if payload.strip() else []
    require(isinstance(rows, list), "expected raw event list")
    require(all(isinstance(row, dict) and isinstance(row.get("id"), str) and
                isinstance(row.get("attributes", {}).get("custom"), dict) for row in rows),
            "projected or malformed raw rows")
    total = _integer(metadata, "count")
    require(total >= len(rows), "page exceeds query total")
    return rows, total


def raw_count(response):
    metadata, payload = _body(response, "TSV_DATA")
    rows = list(csv.reader(io.StringIO(payload.strip()), delimiter="\t"))
    require(len(rows) in (1, 2) and rows[0] == ["events"], "unexpected count columns")
    require(len(rows) == 1 or len(rows[1]) == 1 and rows[1][0].isdigit(), "invalid count")
    require(_integer(metadata, "total_buckets") == len(rows) - 1, "truncated aggregation")
    return int(rows[1][0]) if len(rows) == 2 else 0


def complete_inventory(receipt, request, *, row_limit, page_limit):
    """Reconcile every page total, terminal exhaustion and independent COUNT."""
    require(not receipt.get("error"), "failed collector receipt")
    count = raw_count(receipt["count_response"])
    decoded = dict(request=receipt["request"], count=count, pages=[])
    for page in receipt["pages"]:
        rows, total = raw_page(page["response"])
        require(total == count, "page total disagrees with independent count")
        decoded["pages"].append(dict(start_at=page["start_at"], rows=rows, truncated=False))
    return inventory(decoded, request, row_limit=row_limit, page_limit=page_limit)


def pollable_inventory(receipt, request, *, row_limit, page_limit, minimum_rows=0):
    """A changing count may be polled again; it never yields an accepted inventory."""
    require(not receipt.get('error'), 'failed collector receipt')
    require(set(request) == {'run_id', 'nonce', 'query', 'from', 'to'} and
            all(isinstance(v, str) and v for v in request.values()), 'incomplete query identity')
    require(receipt.get('request') == request, 'stale or foreign query receipt')
    require(type(row_limit) is int and row_limit > 0 and type(page_limit) is int and page_limit > 0,
            'invalid inventory bounds')
    count = raw_count(receipt['count_response'])
    require(count <= row_limit, 'count exceeds frozen limit')
    require(type(minimum_rows) is int and 0 <= minimum_rows <= row_limit,'invalid count readiness bound')
    if 'count_pending' in receipt:
        require(receipt['count_pending'] is True and receipt.get('pages')==[] and count < minimum_rows,'invalid count readiness receipt')
        require(False,'minimum native-derived inventory not indexed','PENDING')
    pages = receipt.get('pages')
    require(isinstance(pages, list) and 1 <= len(pages) <= page_limit, 'missing or excessive pages')
    offset = 0; ids = []; totals = []
    for index, page in enumerate(pages):
        require(type(page.get('start_at')) is int and page['start_at'] == offset, 'page offset differs')
        rows, total = raw_page(page['response'])
        require(total <= row_limit, 'page total exceeds frozen limit')
        require(bool(rows) == (index < len(pages) - 1), 'missing empty terminal page')
        offset += len(rows); require(offset <= row_limit, 'inventory exceeds frozen limit')
        ids.extend(row['id'] for row in rows); totals.append(total)
    require(all(ids) and len(ids) == len(set(ids)), 'missing or duplicate raw ID')
    require(all(total == count for total in totals), 'inventory changed during collection', 'PENDING')
    return complete_inventory(receipt, request, row_limit=row_limit, page_limit=page_limit)
