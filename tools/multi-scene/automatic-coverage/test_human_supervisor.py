"""Real subprocess controls, with no app, simulator, backend or UI input."""
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import human_build
import human_supervisor as supervisor
from acceptance_common import Rejected


class SupervisorControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.log=Path(self.tmp.name)/'child.log'
    def argv(self,code):return [sys.executable,'-u','-c',code]
    def test_output_is_preserved_before_message_publication(self):
        rows=[]
        def read(row):
            self.assertIn(b'"instruction"',self.log.read_bytes());rows.append(row)
        code=supervisor.supervise(self.argv('print(\'{"human_input":{"instruction":"Once"}}\')'),self.log,read,time.time()+2,time.time()+3)
        self.assertEqual(code,0);self.assertEqual(len(rows),1)
    def test_unavailable_log_stops_before_child_creation(self):
        self.log.write_text('prior')
        with patch.object(supervisor.subprocess,'Popen') as spawn,self.assertRaises(FileExistsError):
            supervisor.supervise(self.argv('raise RuntimeError()'),self.log,lambda _:None,time.time()+1,time.time()+2)
        spawn.assert_not_called()
    def test_hung_child_enters_cleanup_at_original_execution_limit(self):
        code='import signal,time,json\ndef stop(*args):\n print(json.dumps({"human_status":{"instruction":"Cleanup"}}));raise SystemExit(0)\nsignal.signal(signal.SIGTERM,stop)\nprint("ready")\ntime.sleep(10)'
        start=time.time();rows=[]
        with self.assertRaises(Rejected):supervisor.supervise(self.argv(code),self.log,rows.append,start+.3,start+1.5)
        self.assertLess(time.time()-start,2);self.assertEqual(rows[-1]['human_status']['instruction'],'Cleanup')
    def test_normal_cleanup_can_use_its_reserved_clock(self):
        start=time.time();native=start+.3;end=start+2
        code=f'import json,time\nprint(json.dumps({{"cell_phase":{{"phase":"cleanup","at":time.time(),"execution_deadline":{native},"cleanup_deadline":{end}}}}}))\ntime.sleep(.5)\nprint("done")'
        self.assertEqual(supervisor.supervise(self.argv(code),self.log,lambda _:None,native,end),0)
    def test_publication_failure_keeps_cleanup_output(self):
        code='import signal,time,json\ndef stop(*args):\n print(json.dumps({"human_status":{"instruction":"Cleanup"}}));raise SystemExit(0)\nsignal.signal(signal.SIGTERM,stop)\nprint(json.dumps({"human_input":{"instruction":"Once"}}))\ntime.sleep(10)'
        def publish(row):
            if 'human_input' in row:raise ValueError('publication unavailable')
        with self.assertRaisesRegex(ValueError,'publication unavailable'):
            supervisor.supervise(self.argv(code),self.log,publish,time.time()+1,time.time()+2)
        self.assertIn(b'Cleanup',self.log.read_bytes())
    def test_foreign_cleanup_deadline_cannot_extend_the_parent(self):
        start=time.time()
        code=f'import json,time\nprint(json.dumps({{"cell_phase":{{"phase":"cleanup","at":time.time(),"execution_deadline":{start+1},"cleanup_deadline":{start+100}}}}}))'
        with self.assertRaises(Rejected):supervisor.supervise(self.argv(code),self.log,lambda _:None,start+1,start+2)

    def test_descendant_cannot_outlive_normal_cell_and_still_qualify(self):
        code='import subprocess,sys\nsubprocess.Popen([sys.executable,"-c","import time;time.sleep(10)"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\nprint("done")'
        with self.assertRaisesRegex(Rejected,'group was not absent'):
            supervisor.supervise(self.argv(code),self.log,lambda _:None,time.time()+2,time.time()+4)
        receipt=supervisor.shared.read(self.log.with_suffix('.supervisor.json'))
        self.assertTrue(receipt['before']);self.assertEqual(receipt['remaining'],[])
    def test_timeout_reaps_child_and_grandchild_as_one_owned_group(self):
        code='import subprocess,sys,time\nsubprocess.Popen([sys.executable,"-c","import time;time.sleep(10)"])\nprint("ready")\ntime.sleep(10)'
        with self.assertRaises(Rejected):
            supervisor.supervise(self.argv(code),self.log,lambda _:None,time.time()+.3,time.time()+3)
        self.assertEqual(supervisor.shared.read(self.log.with_suffix('.supervisor.json'))['remaining'],[])


    def test_native_command_adapter_keeps_descendants_in_supervised_group(self):
        import json
        source=str(Path(supervisor.__file__).parent);folder=str(self.log.parent)
        code="""import os,sys,time,json
sys.path.insert(0,SOURCE)
import human_build,human_processes
import s2_hosting_workflow as shared
from pathlib import Path
with human_processes.shared_commands(shared):
 shared.command([sys.executable,'-c','import os;print(os.getpgrp())'],Path(FOLDER),'native',deadline=time.time()+2)
 assert int((Path(FOLDER)/'native.log').read_text())==os.getpid()
 shared.save(Path(FOLDER)/'quiescent.json',human_processes.quiesce(os.getpgrp(),time.time()+2,exempt=[os.getpid()]))
print('done')
""".replace('SOURCE',repr(source)).replace('FOLDER',repr(folder))
        self.assertEqual(supervisor.supervise(self.argv(code),self.log,lambda _:None,time.time()+3,time.time()+5),0)
        receipt=supervisor.shared.read(self.log.parent/'quiescent.json')
        self.assertEqual(receipt['state'],'PASS');self.assertEqual(receipt['remaining'],[])


    def test_eof_during_cleanup_does_not_trigger_premature_hard_kill(self):
        code='import os,signal,time,json\ndef stop(*args):\n print(json.dumps({"human_status":{"instruction":"Cleanup"}}));os.close(1);os.close(2);time.sleep(.2);raise SystemExit(0)\nsignal.signal(signal.SIGTERM,stop)\nprint(json.dumps({"human_input":{"instruction":"Once"}}))\ntime.sleep(10)'
        def publish(row):
            if 'human_input' in row:raise ValueError('publication unavailable')
        with self.assertRaisesRegex(ValueError,'publication unavailable'):
            supervisor.supervise(self.argv(code),self.log,publish,time.time()+1,time.time()+2)
        self.assertEqual(supervisor.shared.read(self.log.with_suffix('.supervisor.json'))['child_exit'],0)


if __name__=='__main__':unittest.main()
