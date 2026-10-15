"""Offline fabricated controls; none of these artifacts are native qualification."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from acceptance_common import Rejected
import resource_fold_human as human
from test_s2_webview_runtime import display, DEVICE


class HumanProofControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.before,self.before_command=self.capture('before',False,1,2)
        self.after,self.after_command=self.capture('after',True,10,11)
        screenshot=self.write('ready.png',b'\x89PNG\r\n\x1a\nfixture')
        shot=self.write('shot.json',{'device':DEVICE,'display_unique_id':display()['result']['displays'][0]['uniqueId'],'returncode':0})
        self.prompt={'kind':'HUMAN_FOLD_REQUEST','request_sha256':'request-hash','device':DEVICE,'phase':'open',
            'issued_at':5000,'deadline':240100,'input_deadline':180100,'display':self.before,'screenshot':screenshot,'screenshot_command':shot}
        prompt=self.write('prompt.json',self.prompt)
        terminal=self.write('terminal.json',{'status':'HUMAN_DISPLAY_OBSERVED','automated_input_workers':0,'worker_quiescent':True,'observed_after_ms':11000})
        proof=self.write('input.json',{'terminal':terminal})
        self.request={'issued_at':100,'deadline':240100,'phase':'open','displays_before':self.before}
        self.proof={'request_sha256':'request-hash','input_kind':'HUMAN_ACTUAL_DISPLAY','human_prompt':prompt,'input_proof':proof,
            'input_started_at':5000,'input_finished_at':11000,'input_returned_at':11000,
            'human_before_display':self.before,'human_after_display':self.after,'human_before_command':self.before_command,
            'human_after_command':self.after_command,'displays':self.after}
    def write(self,name,value):
        path=self.root/name;path.write_bytes(value if isinstance(value,bytes) else json.dumps(value).encode())
        return {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    def capture(self,name,opened,start,end):
        raw=display(opened);path=self.root/(name+'.raw.json')
        argv=['device','info','displays','--device',DEVICE,'--timeout','15','--json-output',str(path)]
        raw['info']['arguments']=['devicectl',*argv]
        rawref=self.write(path.name,raw);log=self.write(name+'.log',b'actual output')
        command=self.write(name+'.json',{'command':['/Applications/Xcode_27.1.app/Contents/Developer/usr/bin/devicectl',*argv],
            'started_at':start,'finished_at':end,'returncode':0,'log_sha256':log['sha256']})
        return rawref,command
    def verify(self):human.validate_input(self.proof,self.request,DEVICE)
    def reject(self):
        with self.assertRaises(Rejected):self.verify()
    def test_actual_bound_display_and_interval(self):self.verify()
    def test_old_matching_display_observation_rejected(self):
        self.proof['human_after_display'],self.proof['human_after_command']=self.capture('old-after',True,.01,.02);self.reject()
    def test_sidebar_only_or_unchanged_display_rejected(self):
        self.proof['human_after_display'],self.proof['human_after_command']=self.capture('no-effect',False,10,11)
        self.proof['displays']=self.proof['human_after_display'];self.reject()
    def test_raw_observation_not_substituted(self):
        Path(self.after['path']).write_text('{}');self.reject()
    def test_response_output_path_must_match_actual_capture(self):
        value=json.loads(Path(self.after_command['path']).read_text());value['command'][-1]='older-matching.json'
        self.proof['human_after_command']=self.write('different-command.json',value);self.reject()
    def test_transport_reserve_cannot_be_spent_on_input(self):
        self.prompt['input_deadline']=self.request['deadline'];self.proof['human_prompt']=self.write('changed-prompt.json',self.prompt);self.reject()
    def test_expired_human_result_rejected(self):
        self.proof['input_finished_at']=self.proof['input_returned_at']=180100;self.reject()
    def test_foreign_or_reused_prompt_rejected(self):
        self.prompt['request_sha256']='previous';self.proof['human_prompt']=self.write('old-prompt.json',self.prompt);self.reject()
    def test_automated_worker_cannot_claim_human_observation(self):
        terminal=self.write('wrong-terminal.json',{'status':'HUMAN_DISPLAY_OBSERVED','automated_input_workers':1,'worker_quiescent':True,'observed_after_ms':11000})
        self.proof['input_proof']=self.write('wrong-input.json',{'terminal':terminal});self.reject()
    def test_capture_log_retained_exactly(self):
        (self.root/'after.log').write_text('substituted');self.reject()

if __name__=='__main__':unittest.main()
