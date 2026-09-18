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
