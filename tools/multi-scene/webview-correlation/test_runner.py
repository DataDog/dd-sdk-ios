"""Local transport/readiness controls for the emitted-payload collector."""
import gzip
import importlib.util
import json
from pathlib import Path
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import zlib

spec = importlib.util.spec_from_file_location('webview_runner', Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.collector = runner.Collector()
        self.addCleanup(self.collector.close)
        self.event = {'view': {'id': 'browser-view'}, 'container': {'view': {'id': 'native-view'}}}

    def post(self, body, encoding):
        request = Request(self.collector.endpoint + '/rum', data=body,
                          headers={'Content-Encoding': encoding}, method='POST')
        with urlopen(request, timeout=2) as response:
            return response.status

    def read(self):
        with urlopen(self.collector.endpoint + '/event/browser-view', timeout=2) as response:
            return json.load(response)

    def test_deflate_payload_retains_exact_container(self):
        self.assertEqual(self.post(zlib.compress(json.dumps(self.event).encode()), 'deflate'), 202)
        self.assertEqual(self.read(), self.event)

    def test_gzip_payload_retains_exact_container(self):
        self.assertEqual(self.post(gzip.compress(json.dumps(self.event).encode()), 'gzip'), 202)
        self.assertEqual(self.read(), self.event)

    def test_readiness_is_not_consumed_by_an_earlier_reader(self):
        self.assertEqual(self.read(), {})
        self.post(json.dumps(self.event).encode(), 'identity')
        self.assertEqual(self.read(), self.event)
        self.assertEqual(self.read(), self.event)

    def test_malformed_payload_records_failure_and_never_acknowledges(self):
        with self.assertRaises(HTTPError):
            self.post(b'not a compressed event', 'deflate')
        self.assertTrue(self.collector.errors)
        self.assertEqual(self.read(), {})


if __name__ == '__main__':
    unittest.main()
