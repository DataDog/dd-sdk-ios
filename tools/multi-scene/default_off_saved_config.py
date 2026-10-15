"""Saved-only reconciliation of the actual Off fixture compilation condition.

The original grader and its INCOMPLETE receipt stay immutable. No native effect.
"""
import json
from pathlib import Path
import sys
import default_off_native as native


def absent_testing_define(original):
    def condition(command):
        return not original(command)
    return condition


def analyze(root, contract):
    # Contract validation precedes any imported helper execution.
    assert native.ref(root/'definition.json') in contract['definitions']
    assert contract['testing_define_expected'] is False
    definition=json.loads((root/'definition.json').read_text())
    assert definition['compiler_sdk']==contract['original_declared_sdk'], 'unreviewed compiler condition'
    native.load(contract['proposal_review'])
    native.load(contract['original_incomplete'])
    native.load_bytes(contract['fixture'])
    for binding in contract['consumer_bindings'].values():native.load_bytes(binding)
    for row in contract['guarded_source']:native.load_bytes(row['source'])
    sdk=native.load(contract['sdk_metadata'])
    assert sdk['CanonicalName']==contract['sdk_name'] and sdk['Version']==contract['sdk_version']
    assert Path(contract['actual_compiler_sdk']).resolve()==Path(contract['sdk_metadata']['path']).parent
    original=native.helper
    def selected(d):
        assert d['compiler_sdk']==contract['original_declared_sdk'], 'unreviewed compiler condition'
        d['compiler_sdk']=contract['actual_compiler_sdk']
        h=original(d)
        h['has_testing_define']=absent_testing_define(h['has_testing_define'])
        return h
    native.helper=selected
    try:report=native.grade(root)
    finally:native.helper=original
    report['original_consumer']=report['consumer']
    report['consumer']=native.ref(__file__)
    report['compilation_condition']='DD_SDK_COMPILED_FOR_TESTING absent; enable-testing remains required'
    report['original_planned_sdk']=contract['original_declared_sdk']
    report['actual_compiler_sdk']=contract['actual_compiler_sdk']
    report['sdk_metadata']=contract['sdk_metadata']
    report['original_incomplete']=contract['original_incomplete']
    report['limitations']=['Saved Monitor/legacy-factory component only','No universal Off footprint, integration or release-gate credit']
    return report


def publish(root, contract_ref, review_ref):
    contract=native.load(contract_ref);review=native.load(review_ref)
    assert review['verdict']=='PASS_SAVED_COMPILER_CONDITION_RECONCILIATION' and review['reviewer']=='/root/rum_runtime_reviewer'
    assert review['contract']==contract_ref and review['adapter']==native.ref(__file__)
    report=analyze(root,contract)
    report['supplemental_review']=review_ref
    def join():
        assert native.load(contract_ref)==contract and native.load(review_ref)==review
        current=analyze(root,contract);current['supplemental_review']=review_ref
        assert current==report
    return native.write(root/'saved-config-qualification.json',report,join)


if __name__=='__main__':
    folder,contract_path,review_path=sys.argv[1:]
    print(json.dumps(publish(Path(folder).resolve(),native.ref(contract_path),native.ref(review_path))))
