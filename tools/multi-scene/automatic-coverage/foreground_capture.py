"""Opt-in foreground comparison with separate Home and cleanup evidence.

Historical collectors and verdicts are unchanged. The caller must freeze and
review this adapter, the evaluator, native source/product and execution plan.
"""
from contextlib import contextmanager
import copy
import hashlib
import json

from acceptance_common import require
import foreground_finalization as foreground
import human_capture
import human_release


@contextmanager
def native_contract(oracle):
    """Use the plan's frozen native validator only within this execution."""
    prior = foreground.native
    try:
        foreground.native = oracle
        yield
    finally:
        foreground.native = prior


@contextmanager
def cleanup_validator(*, bundle, framework):
    """Use native ownership and idle input without grading AX target capture."""
    prior = human_release.idle
    def validate(*args):
        return foreground.native_idle(*args, expected_bundle=bundle,
                                      expected_framework=framework)
    try:
        human_release.idle = validate
        yield
    finally:
        human_release.idle = prior


class Collector(human_capture.Collector):
    home_collection_state = 'LOCAL_FOREGROUND_COMPARISON_COLLECTED'
    home_completion_scope = dict(profile=foreground.PROFILE,
                                 home_lifecycle_qualified=False,
                                 cleanup_authorized=False)

    def __init__(self, *, expected, **kwargs):
        super().__init__(**kwargs)
        require(expected['scope'] == 'PROSPECTIVE_FOREGROUND_READINESS'
                and expected['profile'] == foreground.PROFILE
                and expected['run_id'] == self.run,
                'foreground collector requires its prospective plan binding')
        self.expected = copy.deepcopy(expected)
        self.evaluation = None

    def arm(self):
        """Bind the first qualified native owner before Home is requested."""
        require(self.binding is not None and 'binding' not in self.expected,
                'foreground owner absent or already armed')
        self.live(self.deadline)
        launch = human_capture.oracle.one([r for r in self.evidence if r['kind'] == 'launch'],
                                          'foreground launch')['payload']
        require(launch == self.expected['launch'] and launch['pid'] == self.pid
                and launch['framework'] == self.framework,
                'foreground source process or fixture differs')
        require(not any(r['kind'] == 'native_background' for r in self.evidence),
                'foreground owner must be armed before Home')
        events = [r['payload'] for r in self.evidence if r['kind'] == 'rum']
        require(events and foreground.event_identity(events[0]) == tuple(self.expected['event_identity']),
                'foreground telemetry identity differs before Home')
        self.expected['binding'] = copy.deepcopy(self.binding)

    def terminal_rows(self, raw, *, prefix):
        require(self.expected.get('binding') == self.binding and self.binding is not None,
                'foreground owner not armed before collection')
        folder = self.output / 'background.before'
        request = (folder / 'request.json').read_bytes()
        idle_path = self.documents / ('home-input-idle-' + json.loads(request)['request_id'] + '.json')
        if not idle_path.is_file():
            return None
        self.evaluation = foreground.evaluate(raw, prefix=prefix, expected=self.expected,
            home_request=request, home_idle=json.loads(idle_path.read_bytes()))
        return None if self.evaluation is None else self.evaluation['rows']

    def comparison(self, run):
        require(self.evaluation is not None, 'foreground inventory is not collected')
        receipts = copy.deepcopy(self.receipts)
        before = [r for r in receipts if r['phase'].endswith('.before')]
        require(len({r['phase'] for r in before}) == len(before),
                'duplicate foreground boundary receipt')
        snapshots = [r for r in self.evaluation['rows'] if r['kind'] == 'human_snapshot'
                     and r['payload']['phase'].endswith('.before')]
        phases = {r['payload']['phase'] for r in snapshots}
        require(len(phases) == len(snapshots)
                and {r['phase'] for r in before} <= phases,
                'foreground boundary differs from actual snapshots')
        existing = {r['phase']: r for r in before}
        for snapshot in snapshots:
            phase = snapshot['payload']['phase']
            receipt = existing.get(phase)
            if receipt is None:
                # Fold receipts use await/received labels. Its actual native
                # snapshot supplies this comparison boundary, not a new input.
                receipt = dict(run_id=snapshot['run_id'], phase=phase,
                               timestamp=snapshot['timestamp'], payload={})
                receipts.append(receipt)
            require(receipt['run_id'] == snapshot['run_id'] == self.run
                    and receipt['timestamp'] == snapshot['timestamp'],
                    'foreground receipt differs from actual boundary')
            path = self.output / phase / 'request.json'
            raw = path.read_bytes()
            receipt['payload'].update(
                boundary_source='ACTUAL_REQUEST_BOUND_NATIVE_SNAPSHOT',
                request_reference=dict(path=str(path.resolve()),
                    sha256=hashlib.sha256(raw).hexdigest()))
        return foreground.comparison_inventory(run, self.evaluation, receipts)

    def cleanup_idle(self, folder, identity, deadline):
        require(identity.get('run_id') == self.run and identity['bundle'] == self.expected['launch']['bundle'],
                'cleanup bundle differs from foreground source')
        with cleanup_validator(bundle=identity['bundle'], framework=self.framework):
            return human_release.capture_idle(self, folder, identity, deadline)
