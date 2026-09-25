import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

import signed_in_account as account
import smoke_contract as smoke
from acceptance_common import Rejected
from test_smoke_contract import native_fixture, SPEC
from test_browser_contract import EXPECTED

SPEC_SIGNED = json.loads((Path(__file__).parent/'signed-in-definition.json').read_text())
SALT = str(uuid.UUID(int=913))


def authenticated(rows):
    for row in rows:
        if row['kind']=='mapper':
            value=json.loads(row['fields']['event_json'])
            value['usr']={'id':'user-fixture','org_uuid':'organization-fixture'}
            row['fields']['event_json']=json.dumps(value)
    return rows


class SignedInControls(unittest.TestCase):
    def test_separate_contract_removes_only_login_obligations(self):
        smoke.definition(SPEC);smoke.definition(SPEC_SIGNED)
        self.assertEqual(smoke.phase_names(SPEC_SIGNED),smoke.PHASES[3:])
        for key,value in [('named_actions',SPEC['expected']['named_actions']),('minimum_resources',0),('minimum_browser_views',0)]:
            bad=copy.deepcopy(SPEC_SIGNED);bad['expected'][key]=value
            with self.subTest(key=key),self.assertRaises(Rejected):smoke.definition(bad)
        bad=copy.deepcopy(SPEC_SIGNED);bad['sequence'].pop(1)
        with self.assertRaises(Rejected):smoke.definition(bad)
        bad=copy.deepcopy(SPEC);bad['expected']['named_actions']=[]
        with self.assertRaises(Rejected):smoke.definition(bad)

    def test_eight_phases_keep_full_owner_and_lifecycle_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            rows,native=native_fixture(Path(directory));authenticated(rows)
            native['phases']={k:v for k,v in native['phases'].items() if k in smoke.phase_names(SPEC_SIGNED)}
            ready=native['phases']['service-list']
            native['account_binding']=account.subject(rows,ready,SALT)
            expected=dict(EXPECTED,account_salt=SALT)
            value=smoke.native_manifest(rows,native,expected,SPEC_SIGNED)
            self.assertEqual(len(value['phase_owners']),8)
            self.assertNotEqual(value['lifecycle']['old_view'],value['lifecycle']['new_view'])
            native['phases']['service-detail']['visible']['controller']='wrong'
            with self.assertRaises(Rejected):smoke.native_manifest(rows,native,expected,SPEC_SIGNED)

    def test_missing_changed_and_untyped_account_ids_reject(self):
        with tempfile.TemporaryDirectory() as directory:
            rows,native=native_fixture(Path(directory));authenticated(rows)
            ready=native['phases']['service-list'];binding=account.subject(rows,ready,SALT)
            self.assertNotIn('user-fixture',json.dumps(binding))
            self.assertNotIn('organization-fixture',json.dumps(binding))
            for value in [None,42,'',True]:
                with self.subTest(value=value),self.assertRaises(Rejected):
                    account.digest_subject({'usr':{'id':'user-fixture','org_uuid':value}},SALT)
            changed=copy.deepcopy(rows)
            later=next(r for r in changed if r['kind']=='mapper' and r['sequence']>binding['boundary_sequence'])
            event=json.loads(later['fields']['event_json']);event['usr']['org_uuid']='foreign'
            later['fields']['event_json']=json.dumps(event)
            with self.assertRaises(Rejected):account.verify_subject(changed,ready,SALT,binding)
            self.assertNotEqual(account.digest_subject(event,SALT),binding['digests'])
            self.assertNotEqual(account.digest_subject({'usr':{'id':'user-fixture','org_uuid':'organization-fixture'}},str(uuid.UUID(int=912))),binding['digests'])

    def test_archive_moves_only_proven_recorder_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);docs=root/'Documents';docs.mkdir()
            unrelated=docs/'user-note.txt';unrelated.write_bytes(b'keep-exactly')
            run=str(uuid.UUID(int=11));capture=docs/('rum-release-capture-'+run);capture.mkdir()
            (capture/'encoder-setup.json').write_text(json.dumps({'identity':{'run_id':run}}))
            (capture/'events.jsonl').write_text('{}\n')
            (docs/account.REQUEST).write_text(json.dumps({'run_id':run}))
            before=account.inventory(docs)
            copied=account.preserve_capture(docs,root/'archive',move=True)
            self.assertEqual(account.inventory(docs),{'user-note.txt':before['user-note.txt']})
            self.assertNotIn('user-note.txt',copied)
            self.assertEqual((root/'archive'/capture.name/'events.jsonl').read_bytes(),b'{}\n')

    def test_foreign_request_unknown_capture_files_and_symlinks_reject(self):
        for mode in ['foreign-request','foreign-file','symlink','identity']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);docs=root/'Documents';docs.mkdir();run=str(uuid.UUID(int=11))
                capture=docs/('rum-release-capture-'+run);capture.mkdir()
                (capture/'encoder-setup.json').write_text(json.dumps({'identity':{'run_id':run if mode!='identity' else str(uuid.UUID(int=12))}}))
                (capture/'events.jsonl').write_text('{}\n')
                if mode=='foreign-request':(docs/account.REQUEST).write_text(json.dumps({'run_id':str(uuid.UUID(int=12))}))
                if mode=='foreign-file':(capture/'not-a-recorder-file.txt').write_bytes(b'keep')
                if mode=='symlink':(capture/'linked').symlink_to(root)
                with self.assertRaises((Rejected,ValueError)):account.preserve_capture(docs,root/'archive',move=True)
                self.assertTrue((capture/'events.jsonl').exists())

    def test_exact_process_does_not_stop_extensions_or_replaced_main(self):
        executable='/task/DatadogApp.app/DatadogApp'
        with patch.object(account,'device_processes',return_value={9}),patch.object(account,'main_processes',return_value=[]),patch.object(account.shared,'process',return_value=''),patch.object(account.shared,'command') as command:
            self.assertFalse(account.stop_exact('device','bundle',executable,Path('/unused'),'stop',99999999999,pid=42)['stopped'])
            command.assert_not_called()
        for pid,matching,host,device in [(None,[77],executable,{77}),(42,[77],executable,{42,77}),
                                        (42,[],executable,{42}),(42,[42],'/wrong/path',{42}),
                                        (42,[42],executable,set())]:
            with self.subTest(pid=pid,matching=matching,host=host,device=device),patch.object(account,'device_processes',return_value=device),patch.object(account,'main_processes',return_value=matching),patch.object(account.shared,'process',return_value=host),patch.object(account.shared,'command') as command:
                with self.assertRaises(Rejected):account.stop_exact('device','bundle',executable,Path('/unused'),'stop',99999999999,pid=pid)
                command.assert_not_called()

    def test_termination_requires_both_device_and_host_absence(self):
        executable='/task/DatadogApp.app/DatadogApp'
        with patch.object(account,'device_processes',side_effect=[{42},set()]),patch.object(account,'main_processes',side_effect=[[42],[]]),patch.object(account.shared,'process',side_effect=[executable,'']),patch.object(account.shared,'command') as command:
            self.assertTrue(account.stop_exact('device','bundle',executable,Path('/unused'),'stop',99999999999,pid=42)['stopped'])
            self.assertEqual(command.call_args.args[0],['xcrun','simctl','terminate','device','bundle'])
        with patch.object(account,'device_processes',side_effect=[{42},set()]),patch.object(account,'main_processes',side_effect=[[42],[77]]),patch.object(account.shared,'process',side_effect=[executable,'']),patch.object(account.shared,'command'):
            with self.assertRaises(Rejected):account.stop_exact('device','bundle',executable,Path('/unused'),'stop',99999999999,pid=42)

    def test_missing_pid_cannot_yield_retention_cleanup_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory);installed=out/'DatadogApp.app';installed.mkdir()
            qualified={'identity':{'bundle_id':'bundle','executable':'DatadogApp'},'manifest':{}}
            device={'udid':'device','state':'Booted','runtime':'runtime','deviceTypeIdentifier':'Duo'}
            with patch.object(account.builds,'product'),patch.object(account.shared,'apps',return_value={'bundle':{}}),patch.object(account.shared,'devices',return_value=device),patch.object(account.shared,'command') as command:
                errors=account.retained_cleanup(out,None,'device',device,{'bundle':{}},None,None,installed,qualified,lambda:None,99999999999)
                self.assertTrue(any('unknown task PID' in e for e in errors))
                self.assertEqual(json.loads((out/'account-retention.json').read_text())['state'],'INVALID')
                command.assert_not_called()


if __name__=='__main__':unittest.main()
