"""Expired or replaced readiness must never show an actionable old screenshot."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import human_operator as operator
from acceptance_common import Rejected


class OperatorControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve();self.directory=self.root/'operator';self.directory.mkdir()
        (self.root/'cells'/'one').mkdir(parents=True);self.image=self.root/'cells/one/ready.png';self.image.write_bytes(b'\x89PNG\r\n\x1a\nactual')
        self.payload={'instruction':'Tap once','deadline':200,'screenshot':str(self.image)}
    def publish(self,**kwargs):
        with patch.object(operator.time,'time',return_value=100):return operator.publish(self.directory,self.payload,ready=True,**kwargs)
    def test_original_returned_image_is_bound_to_current_generation(self):
        row=self.publish()
        with patch.object(operator.time,'time',return_value=150):self.assertEqual(operator.image_bytes(self.directory,row['generation']),self.image.read_bytes())
    def test_old_generation_does_not_survive_next_prompt(self):
        old=self.publish();self.publish()
        with patch.object(operator.time,'time',return_value=150),self.assertRaises(Rejected):operator.image_bytes(self.directory,old['generation'])
    def test_expired_prompt_cannot_publish_or_serve_an_image(self):
        row=self.publish()
        with patch.object(operator.time,'time',return_value=201):
            with self.assertRaises(Rejected):operator.image_bytes(self.directory,row['generation'])
            with self.assertRaises(Rejected):operator.publish(self.directory,self.payload,ready=True)
    def test_observed_effect_retires_image_readiness(self):
        row=self.publish();operator.publish(self.directory,{'instruction':'Wait'})
        with self.assertRaises(Rejected):operator.image_bytes(self.directory,row['generation'])
    def test_changed_image_rejected(self):
        row=self.publish();self.image.write_bytes(b'\x89PNG\r\n\x1a\nother')
        with patch.object(operator.time,'time',return_value=150),self.assertRaises(Rejected):operator.image_bytes(self.directory,row['generation'])
    def test_foreign_or_symlinked_image_rejected(self):
        for candidate in [self.root/'foreign.png',self.root/'cells/one/link.png']:
            if candidate.name=='link.png':candidate.symlink_to(self.image)
            else:candidate.write_bytes(self.image.read_bytes())
            self.payload['screenshot']=str(candidate)
            with self.assertRaises(Rejected):self.publish()
    def test_cleanup_entry_retires_last_gesture_until_separate_restoration(self):
        old=self.publish();operator.forward(self.directory,{'cell_phase':{'phase':'cleanup'}},context='cell')
        state=operator.shared.read(self.directory/'state.json');self.assertFalse(state['ready']);self.assertFalse(state['has_image'])
        with self.assertRaises(Rejected):operator.image_bytes(self.directory,old['generation'])
        with patch.object(operator.time,'time',return_value=100):
            operator.forward(self.directory,{'human_input':{'kind':'cleanup','instruction':'Restore Closed','deadline':200}},context='cell')
        self.assertEqual(operator.shared.read(self.directory/'state.json')['instruction'],'Restore Closed')
    def test_ordinary_gesture_cannot_be_republished_after_cleanup_entry(self):
        self.publish();operator.forward(self.directory,{'cell_phase':{'phase':'cleanup'}},context='cell')
        with patch.object(operator.time,'time',return_value=100),self.assertRaises(Rejected):
            operator.forward(self.directory,{'human_input':self.payload},context='cell')
        self.assertFalse(operator.shared.read(self.directory/'state.json')['ready'])
    def test_returned_screenshot_hash_cannot_be_replaced_with_current_file(self):
        self.payload['screenshot_sha256']='0'*64
        with self.assertRaises(Rejected):self.publish()
    def test_late_browser_image_load_cannot_revive_old_generation(self):
        node=shutil.which('node');self.assertIsNotNone(node,'Node required for the operator race control')
        script=operator.PAGE.decode().split('<script>')[1].split('</script>')[0]
        harness=r'''
const vm=require('vm'),assert=require('assert');
let queued=[],state;const elements={};for(const name of ['instruction','context','clock','image','released'])elements[name]={hidden:true,removeAttribute(){}};
const sandbox={document:{getElementById:n=>elements[n]},fetch:async()=>({ok:true,json:async()=>state}),setTimeout:f=>queued.push(f),Date};
async function tick(){await new Promise(setImmediate);}
(async()=>{state={generation:'old',instruction:'Old',ready:true,has_image:true,deadline:Date.now()/1000+60};vm.runInNewContext(SCRIPT,sandbox);await tick();const stale=elements.image.onload;state={generation:'new',instruction:'New',ready:true,has_image:true,deadline:Date.now()/1000+60};queued.shift()();await tick();stale();assert.equal(elements.image.hidden,true);elements.image.onload();assert.equal(elements.image.hidden,false);state={generation:'wait',instruction:'Wait',ready:false,has_image:false};queued.shift()();await tick();stale();assert.equal(elements.image.hidden,true);})().catch(e=>{console.error(e);process.exit(1)});
'''.replace('SCRIPT',json.dumps(script))
        result=subprocess.run([node,'-e',harness],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__=='__main__':unittest.main()
