import base64
import copy
import json
from pathlib import Path
import plistlib
import struct
import unittest
import platform_context as p


class PlatformContextTests(unittest.TestCase):
    def fixture(self):
        return json.loads((Path(__file__).parent/'fixtures/platform-macos-output.json').read_text())

    def scan(self,fixture):
        return p.scan_compilers(fixture['lines'],[r['target'] for r in fixture['lists']],fixture['lists'],'macos',
            read_bytes=lambda path:base64.b64decode(fixture['source_bytes'][path]))

    def test_actual_macos_driver_alias_and_forwarded_clang_defines(self):
        report=self.scan(self.fixture());self.assertEqual(report['issues'],[])
        self.assertEqual(set(report['rows']),{'DatadogInternal','DatadogCore','DatadogRUM'})

    def test_all_independent_parser_failures_are_reported_together(self):
        f=self.fixture();f['lines']=[line.replace('arm64-apple-macos12.0','arm64-apple-ios15.0').replace('arm64-apple-macosx12.0','arm64-apple-ios15.0')
            .replace('MacOSX27.0.sdk','Foreign.sdk').replace('-DDEBUG','-DFOREIGN') for line in f['lines']]
        faults=self.scan(f)['issues']
        for suffix in ('compiler target differs','compiler SDK differs','shipping compilation conditions differ'):
            self.assertEqual(sum(suffix in row for row in faults),3)

    def test_source_substitution_and_missing_actual_module_reject(self):
        f=self.fixture();name=f['lists'][0]['list']['path'];f['source_bytes'][name]=base64.b64encode(b'foreign source').decode()
        self.assertTrue(any('source response bytes changed' in row for row in self.scan(f)['issues']))
        f=self.fixture();f['lines']=f['lines'][1:]
        self.assertTrue(any('no actual compiler driver' in row for row in self.scan(f)['issues']))

    def test_actual_macos_binary_context_and_wrong_platform_reject(self):
        f=self.fixture();raw=base64.b64decode(f['binary_load_commands']);info=plistlib.loads(base64.b64decode(f['info_plist']))
        observed=p.binary_context(raw,info,'macos');self.assertEqual(observed['build_version']['minimum'],0xc0000)
        with self.assertRaisesRegex(ValueError,'platform/minimum'):p.binary_context(raw,info,'visionos')

    def test_watchos_nominal_nine_does_not_imply_binary_nine(self):
        raw=struct.pack('<8I',0xfeedfacf,0x100000c,0,6,1,24,0,0)+struct.pack('<6I',0x32,24,4,0x1a0000,0x1b0000,0)
        info=dict(CFBundlePackageType='FMWK',DTPlatformName='watchos',MinimumOSVersion='9.0')
        result=p.binary_context(raw,info,'watchos')
        self.assertEqual(result['nominal_minimum'],'9.0');self.assertEqual(result['build_version']['minimum'],0x1a0000)
        self.assertIn('no watchOS9',result['distribution_limit'])
        changed=bytearray(raw);struct.pack_into('<I',changed,44,0x90000)
        with self.assertRaisesRegex(ValueError,'platform/minimum'):p.binary_context(bytes(changed),info,'watchos')


if __name__=='__main__':unittest.main()
