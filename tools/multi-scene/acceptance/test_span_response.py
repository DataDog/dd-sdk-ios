import json
from pathlib import Path
import subprocess
import unittest


class SpanResponseParserTests(unittest.TestCase):
    def parse(self, value):
        return subprocess.run(["ruby", str(Path(__file__).with_name("parse_span_response.rb")), value],
                              capture_output=True, text=True)

    def test_safe_yaml_preserves_hex_strings_and_integer_duration(self):
        result = self.parse('- trace_id: "000000000000000100000000000000ff"\n  span_id: abc\n  duration: 123456789\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(result.stdout)[0]
        self.assertEqual(row["trace_id"], "000000000000000100000000000000ff")
        self.assertEqual(row["duration"], 123456789)

    def test_objects_aliases_duplicates_and_non_array_rejected(self):
        for value in ["--- !ruby/object:Object {}", "- &a {span_id: a}\n- *a",
                      "- span_id: a\n  span_id: b", "span_id: a"]:
            result = self.parse(value)
            self.assertNotEqual(result.returncode, 0, value)

    def test_batch_preserves_independent_pages_and_exact_decimal_strings(self):
        inputs = ['- spanid: "18446744073709551615"\n  duration: 1.75398707e+08', '- spanid: "8"']
        result = subprocess.run(["ruby", str(Path(__file__).with_name("parse_span_response.rb")),
                                 "--batch-json", json.dumps(inputs)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [
            [dict(spanid="18446744073709551615", duration=175398707)], [dict(spanid="8")]])

    def test_bad_page_or_unbounded_input_rejects_entire_batch(self):
        for inputs in [[], "not-an-array", [1], ["[]"] * 101,
                       ["- spanid: good", "- spanid: a\n  spanid: b"],
                       ["- spanid: good", "--- !ruby/object:Object {}"]]:
            result = subprocess.run(["ruby", str(Path(__file__).with_name("parse_span_response.rb")),
                                     "--batch-json", json.dumps(inputs)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, inputs)
