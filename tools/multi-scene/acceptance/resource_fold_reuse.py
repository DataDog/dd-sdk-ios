"""Requalify unchanged Resource/Trace build artifacts without rebuilding or launching."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import time
from acceptance_common import require
import s2_hosting_workflow as shared

OWNER=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-221-duo-fold.json'


def verify():
    definition=shared.read(OWNER)['human_preparation'];root=Path(definition['original_root']);matrix=root/'matrix'
    require(all(shared.sha(root/name)==value for name,value in definition['original_inputs'].items()),'original fold inputs changed')
    plan=shared.read(matrix/'plan.json');manifest=shared.read(matrix/'helper-manifest.json')
    require(shared.sha(matrix/'helper-manifest.json')==plan['helper_manifest_sha256']
            and all(shared.sha(value['path'])==value['sha256'] for value in manifest.values()),'original helpers changed')
    spec=importlib.util.spec_from_file_location('resource_build_origin',manifest['host.py']['path'])
    origin=importlib.util.module_from_spec(spec);spec.loader.exec_module(origin)
    protected=shared.read(root/'source-contract.json')
    require(origin.protected_state(plan['protected_repository'])==protected['main_protected_state']
            and all(shared.sha(Path(plan['protected_repository'])/name)==value for name,value in protected['side_documents'].items()),'protected files changed')
    result={}
    for arm,bound in definition['reused_builds'].items():
        folder=matrix/arm;qualification=shared.read(bound['path']);build=shared.read(folder/'build-result.json')
        require(shared.sha(bound['path'])==bound['sha256'] and qualification['status']=='QUALIFIED_BUILD_ONLY'
                and qualification['arm']==arm and qualification['source_revision']==definition['source_revisions'][arm]
                and qualification['source_sha256']==plan['arms'][arm]['source_sha256'],'wrong original qualification')
        require(shared.sha(folder/'build-result.json')==qualification['build_result_sha256']
                and qualification['helper_manifest_sha256']==plan['helper_manifest_sha256'],'original build/helper identity differs')
        admission=shared.read(folder/'build-admission.json')
        require(shared.sha(folder/'build-admission.json')==qualification['build_admission_sha256']==build['build_admission_sha256']
                and admission['issued_at']<=qualification['qualification_checked_at']<admission['deadline']
                and Path(bound['path']).stat().st_mtime<admission['deadline'],'original build was not timely')
        origin.verify_source(matrix,arm)
        fixture=shared.read(matrix/'fixture-members.json')
        require(all(shared.sha(folder/'client'/name)==value for name,value in fixture.items()),'compiled fixture changed')
        derived=folder/'DerivedData';sdk=folder/'sdk';client=folder/'client';sources={};lists={}
        dependencies={path.resolve():path.name for path in (folder/'Packages/checkouts').iterdir() if path.is_dir()}
        for path in sorted((derived/'Build/Intermediates.noindex').rglob('*.SwiftFileList')):
            require(not path.is_symlink(),'compiler list symlink');members=[]
            for name in shlex.split(path.read_text()):
                source=Path(name);require(source.is_file() and not source.is_symlink(),'compiler source missing/symlinked')
                if source.is_relative_to(sdk):key='sdk/'+str(source.relative_to(sdk))
                elif source.is_relative_to(client):key='fixture/'+source.name
                elif source.is_relative_to(derived):key='generated/'+str(source.relative_to(derived))
                else:
                    owners=[(p,n) for p,n in dependencies.items() if source.is_relative_to(p)]
                    require(len(owners)==1,'foreign compiler input');base,dependency=owners[0]
                    key='dependency/'+dependency+'/'+str(source.relative_to(base))
                fingerprint=shared.sha(source);require(key not in sources or sources[key]==fingerprint,'ambiguous compiler source')
                sources[key]=fingerprint;members.append(key)
            lists[str(path.relative_to(derived))]={'sha256':shared.sha(path),'inputs':members}
        require(sources==qualification['compiler_sources'] and lists==qualification['compiler_lists'],'actual compiler members/bytes changed')
        objects={str(path.relative_to(derived)):shared.sha(path) for path in (derived/'Build/Intermediates.noindex').rglob('*.o') if path.is_file()}
        require(objects==qualification['compiler_objects'],'actual compiled objects changed')
        for name,wanted in qualification['dependency_revisions'].items():
            path=folder/'Packages/checkouts'/('KSCrash' if name=='kscrash' else name)
            actual=shared.capture(['git','rev-parse','HEAD'],cwd=path).stdout.decode().strip();require(actual==wanted,'dependency revision changed')
        product=shared.product(Path(build['app']),bundle=origin.BUNDLE)
        require(dict(product,bundle=origin.BUNDLE)==qualification['product'],'complete Resource/Trace product changed')
        result[arm]={'original_qualification':bound,'build_result_sha256':qualification['build_result_sha256'],
                     'source':qualification['source_revision'],'compiler_sources':len(sources),'compiler_lists':len(lists),
                     'objects':len(objects),'app':build['app'],'product_sha256':origin.datahash(qualification['product'])}
    require(set(result)=={'A','B'},'missing build arm')
    return {'state':'QUALIFIED_REUSE_ONLY','checked_at':time.time(),'arms':result,'original_plan_sha256':shared.sha(matrix/'plan.json'),
            'original_helpers_sha256':plan['helper_manifest_sha256'],'native_launches':0,'additional_builds':0,
            'limit':'Unchanged compiler inputs, objects and products only; no fresh native admission or behavioral gate credit.'}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    result=verify();shared.save(args.output,result,exclusive=True)
    print(json.dumps({'state':result['state'],'output':str(args.output),'sha256':shared.sha(args.output),'native_launches':0,'additional_builds':0}))
if __name__=='__main__':main()
