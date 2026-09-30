"""Compile dormant H10 display components in an isolated existing-member copy."""
import json
from pathlib import Path

import scene_background_session_fixture as session
from scene_background_fixture import sha

HERE = Path(__file__).resolve().parent
MEMBERS = ['scene_background_display_contract.swift', 'scene_background_display.swift']


def prepare(destination):
    destination = Path(destination)
    receipt = session.prepare(destination)
    app = destination/session.focus.APP
    app.write_bytes(app.read_bytes()+b'\n'+b'\n'.join((HERE/name).read_bytes() for name in MEMBERS))
    receipt['rendered'][session.focus.APP] = sha(app)
    receipt['helpers'].update({str(HERE/name):sha(HERE/name) for name in [*MEMBERS, Path(__file__).name]})
    receipt.update(state='DORMANT_DISPLAY_COMPONENT_SOURCE_ONLY', native_admitted=False,
                   scope='Marker renderer is compiled but not instantiated; session/display admission remains unqualified')
    (destination/'source.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt
