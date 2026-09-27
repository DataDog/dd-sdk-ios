"""Apply the current S2 measurement and workspace rules to a fresh fold preparation."""
import hashlib
from pathlib import Path
from acceptance_common import require
from resource_fold_variant import replace_once
import s2_hosting_workflow as shared

USER_PATHS = ['Datadog/Datadog.xcodeproj/project.pbxproj', 'xcconfigs/Datadog.local.xcconfig']
DIAGNOSTICS = ['atomic_capture_duration', 'automatic_resource_elapsed_bracket',
               'automatic_trace_elapsed_bracket', 'incidental_ttid_upper_duration']
TRANSITION = shared.REPO/'DatadogRUM/MultiSceneSupport/Results/navigation-documentation-consolidation-20260924.json'


def bound(value):
    require(isinstance(value, dict) and set(value) == {'path', 'sha256'}, 'unbound scope asset')
    path = Path(value['path'])
    require(path.is_file() and not path.is_symlink() and shared.sha(path) == value['sha256'], 'scope asset changed')
    return path


def validate(value, contract):
    require(value['schema_version'] == 1 and value['kind'] == 'S2_RESOURCE_FOLD_SEMANTICS'
            and value['gates'] == ['S2:T03', 'S2:T08'] and value['native_admitted'] is False, 'wrong scoped contract')
    require(value['source_revisions'] == contract['source_revisions']
            and value['original_root'] == contract['original_root'], 'scoped source changed')
    require(value['diagnostic_rules'] == DIAGNOSTICS and value['finite_scope'] == {
        'cells': contract['cells'], 'additional_builds': 0, 'retries': 0,
        'native_execution_this_preparation': 0, 'backend_requests_this_preparation': 0}, 'scope expanded')
    require(bound(value['documentation_transition']) == TRANSITION, 'foreign documentation authority')
    authority = shared.read(TRANSITION)['main_integration']
    require(authority['source_commit'] == '6fd89e112ee79f25a7d36f744604a4b5f6eca0d4'
            and authority['remaining_protected_paths'] == USER_PATHS, 'workspace authorization differs')
    require(bound(value['original_source_contract']) == Path(contract['original_root'])/'source-contract.json',
            'foreign original source contract')
    require(bound(value['original_document_manifest']) == Path(authority['evidence_root'])/'original-input-manifest.json',
            'foreign original documentation manifest')
    original = shared.read(value['original_source_contract']['path'])
    approved = shared.read(value['original_document_manifest']['path'])['paths']
    require(original['side_documents'] and all(approved.get(name) == sha for name, sha in original['side_documents'].items()),
            'unapproved historical protected document')
    return original


def protected():
    # This helper reads only metadata/index for the local configuration file.
    result = {}
    for name in USER_PATHS:
        path = shared.REPO/name; stat = path.stat()
        result[name] = {'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns, 'ctime_ns': stat.st_ctime_ns,
                        'inode': stat.st_ino, 'index': shared.capture(['git', 'ls-files', '--stage', '--', name]).stdout.decode()}
        if name != USER_PATHS[1]: result[name]['sha256'] = shared.sha(path)
    return result


def render_oracle(original, expected_sha256):
    require(hashlib.sha256(original).hexdigest() == expected_sha256, 'original semantic oracle changed')
    text = original.decode()
    text = replace_once(text, '    byphase={}', '    byphase={};timing_diagnostics=[]')
    text = replace_once(text,
        "                require(p['duration']<=bound,'automatic duration outside same-Date entry-to-mapper bound')",
        "                timing_diagnostics.append({'kind':'automatic_resource_elapsed_bracket','phase':phase,'duration_ns':p['duration'],'observed_bound_ns':bound})")
    text = replace_once(text,
        "        else: require(s['duration']<=r['monotonic_ns']-tasks[phase]['initial'][0]['monotonic_ns']+1_000_000,'automatic Trace duration exceeds native bound')",
        "        else: timing_diagnostics.append({'kind':'automatic_trace_elapsed_bracket','phase':phase,'duration_ns':s['duration'],'observed_bound_ns':r['monotonic_ns']-tasks[phase]['initial'][0]['monotonic_ns']+1_000_000})")
    text = replace_once(text, "'baseline_observation':baseline_observation,'inventory':",
                        "'baseline_observation':baseline_observation,'timing_diagnostics':timing_diagnostics,'inventory':")
    text = replace_once(text, "'inventory':local['inventory'],'fold':fold,",
                        "'inventory':local['inventory'],'fold':fold,'timing_diagnostics':local['timing_diagnostics'],")
    text = replace_once(text,
        "0<=duration<60_000_000_000 and duration==int(duration),'TTID outside source-supported user-launch range'",
        "0<=duration<=(1<<64)-1 and duration==int(duration),'TTID is not an exact nonnegative duration'")
    text = replace_once(text, "'startup_ttid_id':final_ttid['event_id'],",
                        "'startup_ttid_id':final_ttid['event_id'],'startup_ttid_duration_ns':final_ttid['duration'],")
    text = replace_once(text, "set(req)=={'request_id','run_id','nonce','kind','query','from','to'}",
                        "set(req)=={'request_id','run_id','nonce','kind','query','from','to','gather_started_ms'}")
    text = replace_once(text, "    require(deadline-started==exchange_budget_ms(kind)",
                        "    require(integer(req['gather_started_ms'],'request backend start',1)==started,'backend request clock changed','INVALID')\n    require(deadline-started==exchange_budget_ms(kind)")
    compile(text, 'scoped_oracle.py', 'exec')
    return text.encode()


def render_fold(original_projection):
    text = original_projection.decode()
    text = replace_once(text,
        "    require(record['capture_finished_ns']-record['capture_started_ns']<1_000_000_000,'stalled atomic capture')\n", '')
    text = replace_once(text, "return {'phases':2,'poses':'Closed -> Open -> Closed',",
        "return {'capture_durations_ns':[r['capture_finished_ns']-r['capture_started_ns'] for r in extra if 'capture_started_ns' in r],'phases':2,'poses':'Closed -> Open -> Closed',")
    compile(text, 'fold_oracle.py', 'exec')
    return text.encode()
