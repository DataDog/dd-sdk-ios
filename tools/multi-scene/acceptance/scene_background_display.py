"""Four H10 pixel anchors. This checker never grants native/session admission.

Actual supported-tool source identity remains a separate prerequisite. Decoded
markers prove visible payload pixels, not whole-window visibility or usability.
"""
import json
from pathlib import Path

import operation_display as media
import operation_transport as t
import scene_background_capture as capture
import scene_background_cycle as cycle
import scene_background_protocol as protocol


def read(reference, maximum=capture.MAXIMUM_BYTES):
    return media.verified_ref(reference, maximum)


def native(raw, run_id, phase, owners=None):
    return cycle.capture(dict(kind='assertion', evidenceSource='probe', result='PASS',
                              reason=raw.decode()), run_id, phase, owners)


def descriptor(raw, request_raw, witness_raw, expected_identity, consumed):
    value = t.load(raw, maximum=capture.MAXIMUM_BYTES)
    t.require(isinstance(value, dict) and set(value) == {'schemaVersion','request','witness','token','owners',
        'contextSHA256','requiredScenes','payloads'} and type(value['schemaVersion']) is int
        and value['schemaVersion'] == 1 and t.encode(value) == raw, 'H10 display descriptor shape differs')
    t.require(capture.decode(value['request']) == request_raw and capture.decode(value['witness']) == witness_raw,
              'H10 display request or native witness was replaced')
    request = t.load(request_raw); phase = request['challenge']; index = phase['phase']
    protocol.challenge(t.encode(phase), expected_identity, index, consumed[:index])
    rebuilt = protocol.request(phase, request['sequence'], 'inspect', request['previousReplySHA256'],
                               command_id=request['commandID'])
    t.require(rebuilt == request_raw, 'H10 display is not bound to the exact inspect request')
    t.require(t.identifier(value['token']) and value['token'] == request['commandID'],
              'H10 marker token differs from its one-use host command')
    native_phase = ['before','background','foreground','foreground'][index]
    owners, events, names, auxiliary = native(witness_raw, expected_identity['runID'], native_phase)
    ordered = [owners[scene] for scene in cycle.SCENES]
    t.require(t.encode(value['owners']) == t.encode(ordered), 'H10 display owner binding differs')
    context = dict(requestSHA256=t.sha(request_raw), witnessSHA256=t.sha(witness_raw),
                   ownersSHA256=t.sha(t.encode(ordered)), token=value['token'])
    digest = t.sha(t.encode(context))
    required = ['scene-B'] if index == 1 else cycle.SCENES
    payloads = {}
    for scene in required:
        prefix = '|'.join(['DDH10','1',digest,scene,t.sha(t.encode(owners[scene]))])
        payloads[scene] = dict(owner=prefix+'|OWNER', phase=prefix+'|'+phase['name'])
    t.require(value['contextSHA256'] == digest and value['requiredScenes'] == required
              and value['payloads'] == payloads, 'H10 decoded marker context differs')
    return dict(descriptor=value, request=request, owners=owners, events=events,
                names=names, auxiliary=auxiliary, native_phase=native_phase)


def pixels(frame, value, old_a=None):
    """Geometry comes from the decoder's enclosing-pixel checks, never equality."""
    t.require(frame.get('geometryValid') is True and isinstance(frame.get('observations'), list),
              'H10 marker geometry or observations are invalid')
    expected = {payload for pair in value['payloads'].values() for payload in pair.values()}
    ignored_a = set(old_a.values()) if old_a is not None else set()
    observed = []
    for row in frame['observations']:
        payload = row.get('payload')
        if isinstance(payload, str) and payload.startswith('DDH10'):
            t.require(payload in expected | ignored_a, 'H10 foreign, malformed or stale marker')
            observed.append(payload)
    t.require(len(observed) == len(set(observed)) and expected.issubset(observed),
              'H10 fresh marker missing or duplicated')
    return dict(required_payloads=sorted(expected), retained_old_a=sorted(set(observed) & ignored_a),
                whole_window_visibility_qualified=False, input_usability_qualified=False)


def assess(anchors, phase_replies, expected_identity, *, decoder_source_sha256, decoder_binary_sha256):
    """Join immutable descriptors, inspect exchanges, native captures and images.

    All source/transfer/admission and cleanup authority belongs to the future
    composed runner. A PASS here qualifies this component's artifact joins only.
    """
    protocol.identity(expected_identity)
    t.require(len(anchors) == 4 and len(phase_replies) == 3, 'H10 four anchors and three consumed replies required')
    t.require(decoder_source_sha256 == t.sha(Path(media.__file__).with_suffix('.swift').read_bytes())
              and t.digest(decoder_binary_sha256), 'H10 decoder identity is unbound')
    replies = [read(ref) for ref in phase_replies]
    consumed = [t.sha(raw) for raw in replies]
    t.require(len(set(consumed)) == 3, 'H10 consumed phase reply reused')
    owners = None; previous = []; names = None; auxiliary = set(); arm_revision = None
    tokens = set(); requests = set(); images = set(); captures = set(); results = []
    ordinal = 0; old_a = None; recorded_rows = []
    for index, spec in enumerate(anchors):
        request_raw, reply_raw, descriptor_raw = [read(spec[key]) for key in ['request','reply','descriptor']]
        request, reply = t.load(request_raw), t.load(reply_raw)
        t.require(request['challenge']['phase'] == index, 'H10 anchor is out of order')
        t.require(set(reply) == {'challenge','sequence','commandID','requestSHA256','operation','outcome',
            'observation','observationSHA256'} and t.encode(reply) == reply_raw
            and all(t.encode(reply[key]) == t.encode(request[key]) for key in ['challenge','sequence','commandID','operation'])
            and reply['requestSHA256'] == t.sha(request_raw) and reply['outcome'] == 'observed',
            'H10 display inspect reply differs')
        observation = capture.decode(reply['observation'])
        t.require(t.sha(observation) == reply['observationSHA256'], 'H10 inspect observation changed')
        reference = t.load(observation); protocol.artifact_reference(reference)
        actual = capture.read_capture(spec['evidence_directory'], reference, expected_identity)
        value = descriptor(descriptor_raw, request_raw, capture.decode(actual['capture']['before']),
                           expected_identity, consumed)
        marker = value['descriptor']; token = marker['token']
        t.require(actual['capture']['boundary'] == request['challenge']['name'] and actual['terminal'] is None
                  and actual['capture']['sequence'] > ordinal, 'H10 anchor capture is stale or terminal')
        t.require(actual['raw_signals'][:len(recorded_rows)] == recorded_rows,
                  'H10 anchor recorder prefix changed or was truncated')
        recorded_rows = actual['raw_signals']
        t.require(token not in tokens and t.sha(request_raw) not in requests and reference['sha256'] not in captures,
                  'H10 anchor token, request or capture reused')
        tokens.add(token); requests.add(t.sha(request_raw)); captures.add(reference['sha256'])
        ordinal = actual['capture']['sequence']
        if owners is None:
            owners = value['owners']; names = value['names']; arm_revision = len(value['events'])
        t.require(value['owners'] == owners and value['names'] == names, 'H10 anchor owner or typed names changed')
        for raw in [actual['capture']['before'], actual['capture']['after']]:
            observed, events, typed, extra = native(capture.decode(raw), expected_identity['runID'], value['native_phase'], owners)
            auxiliary.update(extra)
            t.require(typed == names and events[:len(previous)] == previous, 'H10 anchor lifecycle history changed')
            cycle.cycle(events, observed, typed, arm_revision, value['native_phase'], auxiliary)
            previous = events
        if index < 3:
            grant = t.load(replies[index])
            t.require(grant.get('challenge') == request['challenge'] and grant.get('operation') == 'permit'
                      and grant.get('outcome') == 'granted'
                      and grant.get('inspectedReplySHA256') == t.sha(reply_raw), 'H10 consumed reply joins another anchor')
        else:
            t.require(capture.final_invocation(actual['signals']) == request['challenge']['finalInvocationSequence'],
                      'H10 collection anchor does not join the fifth invocation')
            # The established oracle retains responsibility for semantic continuity.
            local = cycle.validate_local(actual['signals'], expected_identity['runID'], profile=cycle.PROFILE)
            t.require(local['native']['owners'] == owners, 'H10 collection semantics use different native owners')
        manifest = t.load(read(spec['image'], 65536))
        t.require(manifest['decoder_source']['sha256'] == decoder_source_sha256
                  and manifest['executable']['sha256'] == decoder_binary_sha256,
                  'H10 actual image decoder differs')
        frames = media.checked(spec['image'], 'IMAGE')
        t.require(manifest['raw']['sha256'] not in images, 'H10 image bytes reused')
        images.add(manifest['raw']['sha256'])
        result = pixels(frames[0], marker, old_a if index == 1 else None)
        if index == 0: old_a = marker['payloads']['scene-A']
        results.append(dict(phase=index, context_sha256=marker['contextSHA256'], capture_sha256=reference['sha256'],
                            descriptor=spec['descriptor'], request=spec['request'], reply=spec['reply'],
                            image=spec['image'], pixels=result))
    return dict(state='PASS_H10_ANCHOR_COMPONENT_ONLY', anchors=results, phase_replies=phase_replies,
                native_acceptance=False, supported_source_qualified=False, uninterrupted_visibility_qualified=False,
                lifecycle_authority='Native H10 journal and synchronous guards; QR visibility does not replace them',
                gates_closed=[])
