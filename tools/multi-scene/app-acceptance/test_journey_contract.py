import copy
import json
import unittest

import journey_contract as contract
from acceptance_common import Rejected
from test_capture_contract import payload, encode, IDENTITY, REQUEST


def uid(number):return "00000000-0000-4000-8000-" + str(number).zfill(12)

EXPECTED = dict(application_id=uid(1), session_id=uid(2), service="test-service", pid=12,
                compiled_sdk_version="3.17.0+abcdef12", backend_sdk_version="3.17.0_abcdef12", environment="validation")
CONFIGURATION = dict(pid=12, bundle_id="controlled-app", sdk_version=EXPECTED["compiled_sdk_version"], build_sdk="iphonesimulator27.1")


def event(family, number, **fields):
    value = dict(type=family, date=1000, source="ios", application={"id":uid(1)}, session={"id":uid(2), "type":"user"},
                 service=EXPECTED["service"], version="6.1.3", view={"id":uid(10)},
                 ddtags="service:test-service,version:6.1.3,sdk_version:3.17.0+abcdef12,env:validation")
    if family == "view":value.update(view=dict(id=uid(number), name="Home" if number==10 else "Detail", url="native/"+str(number), is_active=True), _dd={"document_version":1})
    else:value[family] = dict(id=uid(number))
    value.update(fields)
    return value


def mapped(value, accepted=True):return "mapper", dict(family=value["type"], accepted=accepted, event_json=json.dumps(value))


def fixture():
    home=event("view",10);stopped=copy.deepcopy(home);stopped["_dd"]["document_version"]=2;stopped["view"]["is_active"]=False
    detail=event("view",11);detail["date"]=1100
    resource=event("resource",20, resource=dict(id=uid(20),url="https://example.invalid/earlier",method="GET",status_code=200,duration=100))
    late=copy.deepcopy(stopped);late["_dd"]["document_version"]=3
    context=dict(application_id=uid(1),session_id=uid(2),view_id=uid(11),view_name="Detail",view_path="native/11",has_replay=True)
    entries=[("configured",CONFIGURATION),mapped(home),mapped(stopped),mapped(detail),mapped(resource),mapped(late),("context",context)]
    rows,_=payload(entries)
    return rows


def backend(local):
    rows=[]
    terminal={contract.event_key(value["event"]) for value in local["views"].values()}
    for key, value in local["accepted"].items():
        if key[0]=="view" and key not in terminal:continue
        event=copy.deepcopy(value["event"]);date=event.pop("date");source=event.pop("source");event.pop("ddtags");version=event.pop("version")
        event["backend_enrichment"]="preserved"
        rows.append(dict(id="opaque-"+str(len(rows)), attributes=dict(custom=event,client_time=date,source=source,
            tag=dict(sdk_version=EXPECTED["backend_sdk_version"],version=version),tags=["service:test-service","version:6.1.3","sdk_version:3.17.0_abcdef12","env:validation"])))
    rows.append(dict(id="session",attributes=dict(custom=dict(type="session",application={"id":uid(1)},session={"id":uid(2)},_dd={"origin":"reducer"}),client_time=2000,source="ios")))
    return rows


def topology():
    window=dict(id="window",owned=True,key=True,hidden=False,alpha=1,level=0,bounds=[0,0,400,600],root="root",root_attached=True)
    return dict(pid=12,app_state=0,owned_windows=["window"],scene_inventory=[dict(id="scene",activation=0,windows=[window],screen_scale=2,screen_bounds=[0,0,400,600])],
        controllers=[dict(id="root",window="window",label=None,children=[],presented="nil",bundle="App")],uikit_window_bundle="UIKit",uikit_controller_bundle="UIKit")


def display():
    return json.dumps(dict(info=dict(outcome="success",commandType="devicectl.device.info.displays",arguments=["--device","device"]),
        result=dict(displays=[dict(uniqueId=uid(99),active=True,backlightState="activeOn",pointScale=2,nativeSize=[800,1200],currentOrientation="rot0")]))).encode()


class JourneyContractTests(unittest.TestCase):
    def test_latest_inactive_mapper_does_not_replace_current_owner(self):
        entries=[(r["kind"],r["fields"]) for r in fixture() if r["kind"]!="observer_cost"]
        entries.append(("snapshot",dict(topology=topology())))
        rows,_=payload(entries);snapshot=rows[-2]
        bound=dict(scene="scene",window="window",root="root",owned_labels=[])
        proof=contract.snapshot_owner(rows,snapshot,EXPECTED,bound,display(),"device",names=["Detail"])
        self.assertEqual(proof["view_id"],uid(11))
        self.assertNotEqual(proof["mapper_sequence"],snapshot["last_view_sequence"])
        rows[-4]["fields"]["view_id"]=uid(10)
        with self.assertRaisesRegex(Rejected,"context not settled"):
            contract.snapshot_owner(rows,snapshot,EXPECTED,bound,display(),"device",names=["Detail"])

    def test_actual_display_or_process_mismatch_is_invalid(self):
        entries=[(r["kind"],r["fields"]) for r in fixture() if r["kind"]!="observer_cost"]
        entries.append(("snapshot",dict(topology=topology())))
        rows,_=payload(entries);snapshot=rows[-2];bound=dict(scene="scene",window="window",root="root",owned_labels=[])
        for changed in [dict(EXPECTED,pid=99),EXPECTED]:
            raw=json.loads(display());raw["result"]["displays"][0]["nativeSize"]=[1600,1200]
            with self.assertRaises(Rejected):contract.snapshot_owner(rows,snapshot,changed,bound,json.dumps(raw).encode(),"device",names=["Detail"])

    def test_mapper_revisions_and_same_name_occurrences_remain_exact(self):
        rows=fixture();local=contract.mapper_inventory(rows,EXPECTED)
        self.assertEqual(local["occurrence_order"],[uid(10),uid(11)])
        self.assertEqual(len(local["accepted"]),5)
        changed=copy.deepcopy(rows);entry=next(r for r in changed if r["kind"]=="mapper")
        event=json.loads(entry["fields"]["event_json"]);event["_dd"]["document_version"]=2;entry["fields"]["event_json"]=json.dumps(event)
        with self.assertRaisesRegex(Rejected,"missing local view revision"):contract.mapper_inventory(changed,EXPECTED)

    def test_mapper_duplicate_foreign_session_and_owner_are_rejected(self):
        for mode in ["duplicate","session","owner"]:
            rows=fixture()
            if mode=="duplicate":rows.append(copy.deepcopy(rows[2]))
            else:
                row=next(r for r in rows if r["kind"]=="mapper" and r["fields"]["family"]=="resource")
                value=json.loads(row["fields"]["event_json"]);value["session" if mode=="session" else "view"]["id"]=uid(90);row["fields"]["event_json"]=json.dumps(value)
            with self.subTest(mode=mode),self.assertRaises(Rejected):contract.mapper_inventory(rows,EXPECTED)

    def test_backend_latest_revisions_join_without_inventing_missing_history(self):
        local=contract.mapper_inventory(fixture(),EXPECTED);rows=backend(local)
        joined=contract.mapped_backend(rows,rows,local,EXPECTED)
        self.assertEqual(joined["available_view_versions"],{uid(10):[3],uid(11):[1]})
        self.assertEqual(joined["accepted_non_view_events"],1)
        self.assertFalse(joined["runtime_acceptance"])

    def test_wrong_resource_owner_or_non_owner_payload_cannot_pass(self):
        local=contract.mapper_inventory(fixture(),EXPECTED)
        for part,key,value in [("view","id",uid(11)),("resource","method","POST"),("resource","status_code",500),("resource","duration",101)]:
            rows=backend(local);row=next(r for r in rows if r["attributes"]["custom"]["type"]=="resource")
            row["attributes"]["custom"][part][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(Rejected,"backend payload differs"):
                contract.mapped_backend(rows,rows,local,EXPECTED)

    def test_missing_terminal_or_nonview_remains_pending_until_fixed_deadline(self):
        local=contract.mapper_inventory(fixture(),EXPECTED)
        for index in [0,1,2]:
            rows=backend(local);rows.pop(index)
            with self.subTest(index=index),self.assertRaises(Rejected) as caught:contract.mapped_backend(rows,rows,local,EXPECTED)
            self.assertEqual(caught.exception.state,"PENDING")
            with self.assertRaises(Rejected) as caught:contract.mapped_backend(rows,rows,local,EXPECTED,pending=False)
            self.assertEqual(caught.exception.state,"INVALID")

    def test_extra_backend_revision_or_dropped_error_fails(self):
        rows=fixture();drop=event("error",30,error=dict(id=uid(30),is_crash=False))
        extra,_=payload([mapped(drop,False)]);rows.extend(extra)
        local=contract.mapper_inventory(rows,EXPECTED);raw=backend(local)
        value=copy.deepcopy(raw[0]);value["id"]="unexpected";value["attributes"]["custom"]["_dd"]["document_version"]=4
        with self.assertRaisesRegex(Rejected,"absent from complete mapper"):contract.mapped_backend(raw+[value],raw+[value],local,EXPECTED)
        value["attributes"]["custom"]=dict(drop);value["attributes"]["custom"].pop("source");value["attributes"]["custom"].pop("date")
        with self.assertRaisesRegex(Rejected,"dropped event"):contract.mapped_backend(raw+[value],raw+[value],local,EXPECTED)

    def test_source_version_and_independent_partition_cannot_be_substituted(self):
        local=contract.mapper_inventory(fixture(),EXPECTED);rows=backend(local)
        with self.assertRaisesRegex(Rejected,"inventories disagree"):contract.mapped_backend(rows,rows[:-1],local,EXPECTED)
        rows[0]["attributes"]["tag"]["sdk_version"]="candidate-version"
        with self.assertRaisesRegex(Rejected,"source identity"):contract.mapped_backend(rows,rows,local,EXPECTED)

    def test_raw_sdk_version_tag_uses_only_frozen_index_translation(self):
        local=contract.mapper_inventory(fixture(),EXPECTED);rows=backend(local)
        rows[0]["attributes"]["tags"].remove("sdk_version:3.17.0_abcdef12")
        rows[0]["attributes"]["tags"].append("sdk_version:3.17.0+abcdef12")
        with self.assertRaisesRegex(Rejected,"tag missing"):contract.mapped_backend(rows,rows,local,EXPECTED)

    def test_seal_retains_actual_checkpoint_and_requires_complete_exited_stream(self):
        rows=fixture();raw,checkpoint=encode(rows)
        result=contract.sealed_stream(raw,checkpoint,IDENTITY,CONFIGURATION,process_exited=True)
        self.assertEqual(result["actual_writer_checkpoint"],checkpoint)
        self.assertEqual(result["readback_seal"]["sha256"],checkpoint["sha256"])
        for exited,data,configuration in [(False,raw,CONFIGURATION),(True,raw+b"partial",CONFIGURATION),(True,raw,dict(CONFIGURATION,pid=99))]:
            with self.subTest(exited=exited),self.assertRaises((Rejected,ValueError)):
                contract.sealed_stream(data,checkpoint,IDENTITY,configuration,process_exited=exited)


if __name__ == "__main__":unittest.main()
