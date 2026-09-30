"""Read actual H10 capture artifacts; this module never authorizes native input."""
import base64
import hashlib
import json
from pathlib import Path
import re

from acceptance_common import require
import scene_background_cycle as cycle

MAXIMUM_BYTES = 16_777_216


def final_invocation(signals):
    rows = [row for row in signals if row.get('name') == 'h10.invoke.B.after-A-foreground']
    require(len(rows) == 1 and rows[0].get('kind') == 'assertion'
            and rows[0].get('evidenceSource') == 'probe' and rows[0].get('result') == 'PASS'
            and type(rows[0].get('sequence')) is int and rows[0]['sequence'] > 0,
            'missing or ambiguous H10 final invocation')
    return rows[0]['sequence']


def read_reference(directory, reference):
    directory = Path(directory)
    require(directory.is_dir() and not directory.is_symlink(), 'redirected H10 evidence directory')
    require(set(reference) == {'name', 'sha256', 'bytes'} and type(reference['bytes']) is int
            and 0 <= reference['bytes'] <= MAXIMUM_BYTES
            and re.fullmatch(r'[a-z-]+-[a-f0-9]{64}\.json', reference['name'])
            and re.fullmatch(r'[a-f0-9]{64}', reference['sha256']), 'invalid H10 artifact reference')
    path = directory/reference['name']
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == reference['bytes'],
            'missing, redirected or incomplete H10 evidence')
    raw = path.read_bytes()
    require(len(raw) == reference['bytes'] and hashlib.sha256(raw).hexdigest() == reference['sha256'],
            'changed H10 evidence bytes')
    return raw


def decode(raw):
    require(isinstance(raw,str), 'H10 byte payload is not base64 text')
    try:
        result = base64.b64decode(raw, validate=True)
        require(base64.b64encode(result).decode() == raw, 'noncanonical H10 byte payload')
        return result
    except (ValueError, TypeError):
        require(False, 'invalid H10 byte payload')


def read_capture(directory, reference, identity):
    value = json.loads(read_reference(directory, reference))
    require(set(value) == {'identity','sequence','boundary','before','snapshot','after'}
            and value['identity'] == identity and type(value['sequence']) is int and value['sequence'] > 0
            and isinstance(value['boundary'],str), 'foreign H10 capture')
    snapshot = value['snapshot']
    require(set(snapshot) <= {'signals','terminal'} and isinstance(snapshot.get('signals'),list)
            and len(snapshot['signals']) <= 16_384, 'invalid H10 full recorder snapshot')
    raw_signals = [decode(row) for row in snapshot['signals']]
    signals = [json.loads(row) for row in raw_signals]
    require(all(row.get('schemaVersion') == 5 and type(row.get('sequence')) is int and row['sequence'] == i+1
                and row.get('runID') == identity['runID'] and row.get('scenarioID') == cycle.SCENARIO
                for i,row in enumerate(signals)), 'foreign or incomplete H10 recorder prefix')
    return dict(capture=value, raw_signals=raw_signals, signals=signals,
                before=json.loads(decode(value['before'])), after=json.loads(decode(value['after'])),
                terminal=json.loads(decode(snapshot['terminal'])) if 'terminal' in snapshot else None)


def validate_seal(directory, reference, *, identity, challenge, oracle_source_sha256):
    """Recheck both prefixes and the extension. Display/process/cleanup remain separate."""
    seal = json.loads(read_reference(directory, reference))
    require(seal.get('identity') == identity and seal.get('challenge') == challenge
            and seal.get('state') == 'SEALED_PREFIX_HOST_REVALIDATION_REQUIRED', 'foreign H10 seal')
    proof = json.loads(decode(seal['semanticProof']))
    require(proof.get('identity') == identity and proof.get('oracleSourceSHA256') == oracle_source_sha256
            and hashlib.sha256(Path(cycle.__file__).read_bytes()).hexdigest() == oracle_source_sha256
            and proof.get('captureSHA256') == seal['inspected']['sha256']
            and proof.get('displayReceiptSHA256') == seal.get('displayReceiptSHA256')
            and proof.get('consumedPhaseReplies') == challenge.get('consumedPhaseReplies')
            and proof.get('finalInvocationSequence') == challenge.get('finalInvocationSequence'), 'H10 proof binding differs')
    old = read_capture(directory,seal['inspected'],identity)
    fresh = read_capture(directory,seal['fresh'],identity)
    require(type(challenge.get('finalInvocationSequence')) is int
            and challenge['finalInvocationSequence'] == final_invocation(old['signals'])
            == final_invocation(fresh['signals']), 'H10 final invocation sequence differs')
    require(old['terminal'] is None and fresh['terminal'] is None
            and fresh['capture']['sequence'] > old['capture']['sequence']
            and fresh['raw_signals'][:len(old['raw_signals'])] == old['raw_signals'], 'changed H10 inspected prefix')
    extra = [decode(row) for row in json.loads(read_reference(directory,seal['extensionRows']))]
    require(extra == fresh['raw_signals'][len(old['raw_signals']):], 'missing or replaced H10 extension')
    sequences = [row['sequence'] for row in fresh['signals'][len(old['signals']):]]
    require(seal.get('extensionFirstSequence') == (sequences[0] if sequences else None)
            and seal.get('extensionLastSequence') == (sequences[-1] if sequences else None), 'H10 extension range differs')
    original = cycle.validate_local(old['signals'],identity['runID'],profile=cycle.PROFILE)
    require(original == json.loads(decode(proof['localResult'])), 'H10 original semantic result differs')
    current = cycle.validate_local(fresh['signals'],identity['runID'],profile=cycle.PROFILE)
    require(original == current, 'H10 extension changed semantic ownership')
    owners = original['native']['owners']; names = None; previous = []; auxiliary = set()
    arm_revision = original['native']['arm_revision']
    for signal in old['signals']:
        name = signal.get('name','')
        if not name.startswith(('h10.arm','h10.before.','h10.after.')): continue
        phase = 'before' if name == 'h10.arm' else next(p for marker,_,p in cycle.PHASES if name.endswith('.'+marker))
        _,previous,names,observed_auxiliary = cycle.capture(signal,identity['runID'],phase,owners)
        auxiliary.update(observed_auxiliary)
    for raw_witness in [old['before'],old['after'],fresh['before'],fresh['after']]:
        signal = dict(kind='assertion',evidenceSource='probe',result='PASS',reason=json.dumps(raw_witness))
        observed,events,typed,observed_auxiliary = cycle.capture(signal,identity['runID'],'foreground',owners)
        if names is not None: require(names == typed, 'changed H10 typed names')
        names = typed
        require(events[:len(previous)] == previous, 'changed H10 collection lifecycle prefix')
        previous = events
        auxiliary.update(observed_auxiliary)
        cycle.cycle(events,observed,typed,arm_revision,'foreground',auxiliary)
    return dict(state='PASS_SEALED_LOCAL_COMPONENT_ONLY',local=current,display_qualified=False,
                native_process_qualified=False,cleanup_qualified=False,gates_closed=[])
