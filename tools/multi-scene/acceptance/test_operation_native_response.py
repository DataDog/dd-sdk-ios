"""Bounded native-inventory parsing controls; no device or app work."""
from pathlib import Path
import tempfile
import time
import types
import unittest

import operation_cleanup as cleanup
import operation_setup as setup
import operation_transport as t
import test_operation_setup as fixtures


class NativeResponseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.now = time.time(); self.deadline = self.now + 60
        self.value = dict(info=dict(commandType='devicectl.device.info.processes', outcome='success',
            arguments=['device','info','processes','--device','physical-device']),
            result=dict(runningProcesses=[dict(processIdentifier=n, executable='/private/system/process-'+str(n))
                                          for n in range(1, 1601)]))
        self.raw = t.encode(self.value); self.assertGreater(len(self.raw), t.MAX_BYTES)
        self.receipt = dict(started_at=self.now, finished_at=self.now, deadline=self.deadline,
            returncode=0, before=[], remaining=[], quiescence_error=None, response_sha256=t.sha(self.raw))

    def remote(self, label):
        output=self.root/'device';output.mkdir();folder=output/('00001-'+label);folder.mkdir()
        (folder/'response.json').write_bytes(self.raw);(folder/'receipt.json').write_bytes(t.encode(self.receipt))
        return types.SimpleNamespace(output=output, sequence=1, identifier='physical-device',
            command=lambda *a,**kw:(self.value,self.receipt))

    def test_large_native_inventory_keeps_all_rows(self):
        self.assertEqual(len(setup.native_response(self.raw)['result']['runningProcesses']), 1600)

    def test_channel_limit_stays_small(self):
        with self.assertRaises(ValueError): t.load(self.raw)

    def test_one_megabyte_native_limit_remains_enforced(self):
        with self.assertRaises(ValueError): setup.native_response(t.encode({'value':'x'*t.MAX_CONTEXT_BYTES}))

    def test_duplicate_keys_still_reject(self):
        with self.assertRaises(ValueError): setup.native_response(b'{"result":{},"result":{}}')

    def test_nonfinite_values_still_reject(self):
        with self.assertRaises(ValueError): setup.native_response(b'{"result":NaN}')

    def test_observed_device_preserves_large_actual_response(self):
        remote=self.remote('processes');folder=self.root/'observed';folder.mkdir()
        observer=cleanup.ObservedDevice(remote,folder,self.deadline,self.now)
        value,_=observer.command(['device','info','processes'],'processes')
        self.assertEqual(value,self.value)
        self.assertEqual((folder/'00001-processes-response.json').read_bytes(),self.raw)

    def test_substituted_large_response_still_rejects(self):
        remote=self.remote('processes');folder=self.root/'observed';folder.mkdir()
        observer=cleanup.ObservedDevice(remote,folder,self.deadline,self.now)
        self.value['result']['runningProcesses'].pop()
        with self.assertRaisesRegex(ValueError,'substituted'): observer.command(['device','info','processes'],'processes')

    def test_host_setup_uses_same_large_native_bound(self):
        remote=self.remote('operation-setup-processes');folder=self.root/'observed';folder.mkdir()
        host=object.__new__(setup.HostSetup);host.live=lambda:None;host.remote=remote;host.folder=folder
        host.channel=types.SimpleNamespace(deadline=self.deadline);host.released_at=self.now
        self.assertEqual(host.native(['device','info','processes'],'processes'),self.value)
        self.assertEqual((folder/'processes-response.json').read_bytes(),self.raw)

    def test_cleanup_preserves_large_original_process_inventory(self):
        fixture=fixtures.HostSetupTests();fixture.setUp();self.addCleanup(fixture.doCleanups)
        host=fixture.setup
        rows=[dict(processIdentifier=n+10000, executable='/private/system/process-'+str(n))
              for n in range(1600)]
        rows.append(dict(processIdentifier=123, executable='/private/Bundle/Fixture.app/Fixture'))
        value=dict(info=dict(commandType='devicectl.device.info.processes', outcome='success',
            arguments=['device','info','processes','--device',fixture.remote.identifier]),
            result=dict(runningProcesses=rows))
        raw=t.encode(value);self.assertGreater(len(raw),t.MAX_BYTES)
        (host.folder/'process-before-response.json').write_bytes(raw)
        result=cleanup.Cleanup(host, original_native_raw=None, original_terminal=None)
        self.assertEqual((result.folder/'original-process.json').read_bytes(),raw)
        self.assertEqual(result.process['processID'],123)


if __name__=='__main__': unittest.main()
