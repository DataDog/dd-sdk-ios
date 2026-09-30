"""Copy the dormant H10 native witness into one existing fixture source member.

No catalog, driver, SDK or project membership is changed. This preparation cannot
launch the H10 scenario; its arm/marker/display/cleanup composition is separate.
"""
import hashlib
import json
from pathlib import Path
import shutil

from acceptance_common import require

HERE = Path(__file__).resolve().parent
PROBE = HERE.parents[2] / 'Datadog/Example/MultiSceneProbe'
INPUT = 'Sources/Harness/ProbePhysicalTopologyAdmission.swift'
INPUT_SHA256 = '7b4ff1c0a0619c7481ca60c2b67c1021e8aca90ab7dbccd3b87d4f3ca2ebcabd'
WITNESS = HERE / 'scene_background_witness.swift'


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare(destination):
    destination = Path(destination)
    require(destination.is_absolute() and destination.resolve() == destination and not destination.exists(),
            'fresh canonical H10 fixture output required')
    require(sha(PROBE / INPUT) == INPUT_SHA256, 'unreviewed native observer source')
    files = sorted((PROBE / 'Sources').rglob('*'))
    require(not any(p.is_symlink() for p in files), 'redirected fixture input')
    original = {str(p.relative_to(PROBE)): sha(p) for p in files if p.is_file()}
    helper = sha(WITNESS)
    destination.mkdir()
    shutil.copytree(PROBE / 'Sources', destination / 'Sources')
    rendered = (PROBE / INPUT).read_bytes() + b'\n' + WITNESS.read_bytes()
    (destination / INPUT).write_bytes(rendered)
    result = {str(p.relative_to(destination)): sha(p) for p in sorted((destination / 'Sources').rglob('*'))
              if p.is_file()}
    require(original.keys() == result.keys()
            and {p for p in original if original[p] != result[p]} == {INPUT},
            'unrelated fixture source or membership changed')
    require(all(sha(PROBE / p) == digest for p, digest in original.items()) and sha(WITNESS) == helper,
            'original source or helper changed during copy')
    receipt = dict(state='DORMANT_NATIVE_WITNESS_SOURCE_ONLY', original=original, rendered=result,
                   helpers={str(Path(__file__)): sha(__file__), str(WITNESS): helper},
                   compiler_qualified=False, scenario_runnable=False, native_runs=0, gates_closed=[])
    (destination / 'source.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt
