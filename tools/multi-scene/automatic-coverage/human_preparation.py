"""Prospective session clocks and terminal evidence, independent of human timing.

Operational phases are issued once. Sealed bytes remain readable after task-app
removal; this module grants neither native admission nor RUM journey credit.
"""
import hashlib
import json
from pathlib import Path
import time

from human_supported_session import require, reference, read, save


class Phases:
    ORDER = ('preparation', 'operator', 'scenario')

    def __init__(self, directory, context, budgets, reservation, *, clock=time.time):
        self.directory = Path(directory)
        self.context = dict(context)
        self.budgets = dict(budgets)
        require(set(self.budgets) == set(self.ORDER) and all(type(v) is int and v > 0 for v in self.budgets.values()),
                'invalid phase budgets')
        self.reservation = reservation
        self.clock = clock
        self.current = None
        self.consumed = []

    def begin(self, name):
        require(name in self.ORDER and name not in self.consumed and self.current is None, 'phase consumed or still active')
        require(name == self.ORDER[len(self.consumed)], 'phase order changed')
        now = self.clock()
        require(now + self.budgets[name] <= self.reservation, 'operational reservation cannot cover next phase')
        value = dict(kind='SESSION_OPERATION_PHASE', phase=name, context=self.context,
                     issued_at=now, deadline=now + self.budgets[name], seconds=self.budgets[name])
        save(self.directory / (name + '.json'), value)
        self.current = value
        return value

    def finish(self, context):
        require(self.current is not None and context == self.context, 'foreign or missing active phase')
        require(self.current['issued_at'] <= self.clock() < self.current['deadline'], 'original phase expired')
        issued = read(self.directory / (self.current['phase'] + '.json'))
        require(issued == self.current, 'issued phase replaced')
        save(self.directory / (self.current['phase'] + '-completed.json'),
             dict(context=self.context, phase=self.current['phase'], issued=reference(self.directory / (self.current['phase'] + '.json')),
                  completed_at=self.clock()))
        self.consumed.append(self.current['phase'])
        self.current = None


def seal(directory, raw, checkpoint, context, inputs):
    """Seal a real writer-committed prefix before destructive task cleanup."""
    directory = Path(directory)
    require(directory.is_dir() and not (directory / 'terminal-anchor.json').exists(), 'terminal output missing or consumed')
    require(isinstance(raw, bytes) and raw.endswith(b'\n') and raw, 'terminal bytes incomplete')
    rows = [json.loads(line) for line in raw.splitlines()]
    require(all(r['run_id'] == context['run_id'] for r in rows)
            and [r['sequence'] for r in rows] == list(range(1, len(rows) + 1)), 'foreign or incomplete terminal sequence')
    require(checkpoint['success'] is True and checkpoint['run_id'] == context['run_id']
            and checkpoint['byte_count'] == len(raw) and checkpoint['sequence'] == rows[-1]['sequence']
            and checkpoint['sha256'] == hashlib.sha256(raw).hexdigest(), 'terminal writer checkpoint differs')
    for ref in inputs.values():
        require(reference(ref['path']) == ref, 'terminal input changed before sealing')
    require('supported_end' in inputs and read(inputs['supported_end']['path'])['state'] == 'PASS', 'actual owned End required before seal')
    path = directory / 'terminal.jsonl'
    with path.open('xb') as stream:
        stream.write(raw); stream.flush(); __import__('os').fsync(stream.fileno())
    anchor = dict(kind='PREPARED_SESSION_TERMINAL', sealed_at=time.time(), context=context, terminal=reference(path), checkpoint=checkpoint, inputs=inputs)
    save(directory / 'terminal-anchor.json', anchor)
    require(path.read_bytes() == raw, 'sealed terminal publication changed')
    return reference(directory / 'terminal-anchor.json')


def saved_rows(anchor_ref, context):
    """Read saved evidence only: no simulator container or live app is accessed."""
    require(reference(anchor_ref['path']) == anchor_ref, 'terminal anchor changed')
    anchor = read(anchor_ref['path'])
    require(anchor['kind'] == 'PREPARED_SESSION_TERMINAL' and anchor['context'] == context, 'foreign terminal anchor')
    for ref in [anchor['terminal'], *anchor['inputs'].values()]:
        require(reference(ref['path']) == ref, 'sealed evidence replaced')
    raw = Path(anchor['terminal']['path']).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == anchor['checkpoint']['sha256'], 'saved terminal checksum differs')
    rows = [json.loads(line) for line in raw.splitlines()]
    require(rows and all(r['run_id'] == context['run_id'] for r in rows)
            and [r['sequence'] for r in rows] == list(range(1,len(rows)+1)), 'saved terminal sequence differs')
    return rows
