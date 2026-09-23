import copy
import unittest
import xml.etree.ElementTree as ET
from contract import Invalid
import test_contract as native_controls
from trace_contract import SCHEMAS, COLUMN_TYPES, decode, inventory, measure


def export(name, rows):
    root=ET.Element('trace-query-result');node=ET.SubElement(root,'node');schema=ET.SubElement(node,'schema',name=name)
    for field,kind in COLUMN_TYPES[name].items():
        col=ET.SubElement(schema,'col');ET.SubElement(col,'mnemonic').text=field;ET.SubElement(col,'engineering-type').text=kind
    for row in rows:
        element=ET.SubElement(node,'row')
        for field,kind in COLUMN_TYPES[name].items():
            cell=ET.SubElement(element,kind)
            if field not in row:
                cell.text='unused';continue
            if kind=='process':
                ET.SubElement(cell,'pid').text=str(row[field]['pid']);ET.SubElement(cell,'name').text=row[field]['name']
            elif kind=='os-log-metadata':cell.set('fmt',row[field])
            else:cell.text=str(row[field])
    return ET.tostring(root)


class TraceControls(unittest.TestCase):
    def fixture(self):
        doc,expected=native_controls.NativeScenarioControls().fixture();process=dict(pid=expected['pid'],name='UIKitImpact')
        root=ET.Element('trace-toc');run=ET.SubElement(root,'run',number='1');data=ET.SubElement(run,'data')
        for name in SCHEMAS:
            attrs={'schema':name}
            if name=='potential-hangs':attrs['hangs-threshold']='250';attrs['target-pid']='SINGLE'
            ET.SubElement(data,'table',attrs)
        rows={name:[] for name in SCHEMAS}
        rows['process-info']=[{'time':0,'pid':expected['pid'],'unique-id':42,'process':process,'process-name':'UIKitImpact'}]
        for phase in ['warmup','active','idle']:
            begin=next(r for r in doc['records'] if r['kind']=='phase-begin' and r['name']==phase)
            end=next(r for r in doc['records'] if r['kind']=='phase-end' and r['name']==phase)
            rows['os-signpost-interval'].append({'start':begin['uptime_ns']-90*10**9,'duration':end['uptime_ns']-begin['uptime_ns'],
                'name':'Workload','subsystem':'com.datadoghq.application-impact','process':process,'end-process':process,
                'start-message':expected['run_id']+' '+phase,'end-message':expected['run_id']+' '+phase})
        rows['core-animation-fps-estimate']=[{'interval':i*10**9,'period':10**9,'fps':60} for i in range(9,154)]
        device='f0e8c4cb-35ab-43da-9a20-19813f6d5b34'
        display={'info':{'outcome':'success','commandType':'devicectl.device.info.displays','arguments':['devicectl','--device',device]},
            'result':{'displays':[{'uniqueId':'118cc575-03d5-4d90-87c2-750c8f1559c3','displayId':1,'active':True,'backlightState':'activeOn',
                                  'nativeSize':[1200,2400],'pointScale':3,'currentOrientation':'rot0','bounds':[[0,0],[400,800]]}]}}
        return ET.tostring(root),rows,doc,expected,process['name'],display,copy.deepcopy(display),device

    def measure(self, values):
        toc,rows,*rest=values
        return measure(toc,{k:export(k,v) for k,v in rows.items()},*rest)

    def test_valid_empty_hitch_and_hang_tables_are_zero(self):
        result=self.measure(self.fixture());self.assertEqual(result['metrics']['fps'],60)
        self.assertEqual(result['metrics']['hitch_ratio'],0);self.assertEqual(result['metrics']['max_hang_seconds'],0)
        self.assertFalse(result['native_admitted'])

    def test_missing_and_ambiguous_table_are_invalid(self):
        for duplicate in [False,True]:
            values=list(self.fixture());toc=ET.fromstring(values[0]);data=toc.find('.//data')
            if duplicate:data.append(copy.deepcopy(data[0]))
            else:data.remove(data[0])
            values[0]=ET.tostring(toc)
            with self.subTest(duplicate=duplicate),self.assertRaises(Invalid):self.measure(values)

    def test_missing_export_is_not_empty(self):
        values=list(self.fixture());values[1].pop('potential-hangs')
        with self.assertRaises(Invalid):self.measure(values)

    def test_hang_threshold_cannot_miss_250ms(self):
        values=list(self.fixture());toc=ET.fromstring(values[0]);toc.find(".//table[@schema='potential-hangs']").set('hangs-threshold','500');values[0]=ET.tostring(toc)
        with self.assertRaises(Invalid):self.measure(values)

    def test_foreign_or_reused_process(self):
        for reused in [False,True]:
            values=list(self.fixture());row=values[1]['process-info'][0]
            if reused:
                extra=copy.deepcopy(row);extra['unique-id']+=1;values[1]['process-info'].append(extra)
            else:row['process']['pid']+=1
            with self.subTest(reused=reused),self.assertRaises(Invalid):self.measure(values)

    def test_signpost_identity_and_complete_intervals(self):
        for field,value in [('start-message','stale active'),('duration',1),('process',{'pid':123,'name':'foreign'})]:
            values=list(self.fixture());values[1]['os-signpost-interval'][1][field]=value
            with self.subTest(field=field),self.assertRaises(Invalid):self.measure(values)

    def test_clock_offset_consistency(self):
        values=list(self.fixture());values[1]['os-signpost-interval'][2]['start']+=10**9
        with self.assertRaises(Invalid):self.measure(values)

    def test_display_gaps_overlap_and_partial_coverage(self):
        for change in ['gap','overlap','partial','nan','coarse']:
            values=list(self.fixture());rows=values[1]['core-animation-fps-estimate']
            if change=='gap':del rows[20]
            elif change=='overlap':rows[20]['interval']-=1
            elif change=='partial':del rows[-3:]
            elif change=='nan':rows[20]['fps']=float('nan')
            else:rows[20]['period']=2*10**9
            with self.subTest(change=change),self.assertRaises(Invalid):self.measure(values)

    def test_changed_physical_display(self):
        values=list(self.fixture());values[6]['result']['displays'][0]['nativeSize']=[1300,2400]
        with self.assertRaises(Invalid):self.measure(values)

    def test_render_process_is_window_server_not_app(self):
        values=list(self.fixture());values[1]['hitches-render-interval']=[{'start':30*10**9,'duration':10**7,'process':{'pid':55,'name':'render-server'},'display-id':1}]
        result=self.measure(values);self.assertEqual(result['render_display_id_unjoined'],1);self.assertEqual(result['metrics']['fps'],60)

    def test_multiple_render_displays_invalid(self):
        values=list(self.fixture());values[1]['hitches-render-interval']=[{'start':30*10**9,'duration':10**7,'process':{'pid':55,'name':'server'},'display-id':i} for i in [1,2]]
        with self.assertRaises(Invalid):self.measure(values)

    def test_global_hitches_and_app_owned_hangs(self):
        values=list(self.fixture());values[1]['hitches-summary']=[{'start':30*10**9,'duration':200_000_000,'hitch-id':1},{'start':30*10**9+100_000_000,'duration':200_000_000,'hitch-id':2}]
        values[1]['potential-hangs']=[{'start':30*10**9,'duration':260_000_000,'process':{'pid':778,'name':'UIKitImpact'}},
                                    {'start':31*10**9,'duration':5*10**9,'process':{'pid':55,'name':'server'}}]
        result=self.measure(values)['metrics'];self.assertAlmostEqual(result['hitch_ratio'],.3/96)
        self.assertEqual(result['max_hitch_seconds'],.2);self.assertEqual(result['max_hang_seconds'],.26)

    def test_xml_backreference_and_wrong_reference_type(self):
        raw=export('hitches-summary',[{'start':1,'duration':2,'hitch-id':1}]*2);root=ET.fromstring(raw)
        rows=root.findall('.//row');rows[0][1].set('id','shared');rows[1][1].text=None;rows[1][1].set('ref','shared')
        self.assertEqual(decode(ET.tostring(root),'hitches-summary')[1]['duration'],2)
        rows[1][1].set('ref','absent')
        with self.assertRaises(Invalid):decode(ET.tostring(root),'hitches-summary')
        rows[1][1].set('ref','shared');rows[0][1].tag='uint64'
        with self.assertRaises(Invalid):decode(ET.tostring(root),'hitches-summary')

    def test_partial_row_and_schema_type_change(self):
        for change in ['row','type','extra']:
            root=ET.fromstring(export('hitches-summary',[{'start':1,'duration':2,'hitch-id':1}]))
            if change=='row':root.find('.//row').remove(root.find('.//row')[0])
            elif change=='type':root.find('.//engineering-type').text='string'
            else:
                col=ET.SubElement(root.find('.//schema'),'col');ET.SubElement(col,'mnemonic').text='extra';ET.SubElement(col,'engineering-type').text='string'
            with self.subTest(change=change),self.assertRaises(Invalid):decode(ET.tostring(root),'hitches-summary')

    def test_xml_entities_rejected(self):
        with self.assertRaises(Invalid):inventory(b'<!DOCTYPE trace-toc><trace-toc/>')
