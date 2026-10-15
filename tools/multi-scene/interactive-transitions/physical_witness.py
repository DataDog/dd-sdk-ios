"""Passive TTID evidence for copied physical fixtures; offline classification only."""
import hashlib
import math

from acceptance_common import require
from app_journey_inventory import field, identifier
from hosting_contract import sdk_milliseconds

WITNESS_SWIFT = r'''
// Passive value snapshot; returning false preserves all existing message consumers.
private struct TransitionTTIDFeature: DatadogFeature {
    static let name = "s2-transition-ttid-witness"
    let messageReceiver: FeatureMessageReceiver
}
private struct TransitionTTIDReceiver: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case .payload(let payload) = message, let message = payload as? TTIDMessage else { return false }
        var attributes: [String: Any] = [:]
        var unsupported = false
        for (key, value) in message.attributes {
            if let value = value as? String { attributes[key] = ["type": "String", "value": value] }
            else if let value = value as? [String] { attributes[key] = ["type": "[String]", "value": value] }
            else { attributes[key] = ["type": "unsupported"]; unsupported = true }
        }
        if unsupported { ObservationStore.shared.append("ttid-observer-failure", ["reason": "unsupported-attribute-type"]) }
        ObservationStore.shared.append("ttid-message", ["payload_type": "TTIDMessage", "attributes": attributes,
            "vital_id": message.ttid.id, "vital_name": message.ttid.name,
            "duration_ns": message.ttid.duration as Any? ?? NSNull(),
            "raw_date_reference_seconds": message.ttid.date.timeIntervalSinceReferenceDate,
            "raw_date_unix_seconds": message.ttid.date.timeIntervalSince1970,
            "server_time_offset_seconds": message.ttid.serverTimeOffset])
        return false
    }
}
'''
REGISTRATION = '''        do {
            try CoreRegistry.default.register(feature: TransitionTTIDFeature(messageReceiver: TransitionTTIDReceiver()))
            ObservationStore.shared.append("ttid-observer-registered", [:])
        } catch { ObservationStore.shared.append("ttid-observer-failure", ["reason": "registration"]) }
'''


def render(source, fingerprint):
    """Exact source overlay; no mapper, lifecycle or RUM API behavior is replaced."""
    require(hashlib.sha256(source).hexdigest() == fingerprint, 'TTID source fingerprint differs')
    text = source.decode()
    for old, new in [
        ('import DatadogCore\n', 'import DatadogCore\nimport DatadogInternal\n'),
        ('        var configuration = RUM.Configuration(', REGISTRATION + '        var configuration = RUM.Configuration('),
        ('        RUM.enable(with: configuration)',
         '        ObservationStore.shared.append("rum-enable", [:])\n        RUM.enable(with: configuration)')
    ]:
        require(text.count(old) == 1, 'ambiguous TTID source anchor')
        text = text.replace(old, new)
    require(text.index('Datadog.initialize(') < text.index(REGISTRATION) < text.index('        RUM.enable('),
            'TTID registration order changed')
    require('TransitionTTIDReceiver' not in source.decode() and 'import DatadogInternal' not in source.decode(),
            'TTID overlay already applied')
    return (text + WITNESS_SWIFT).encode()


def dispatch(rows, identity, local, expected):
    """Decode the independently recorded typed dispatch, never mapper timing."""
    require(rows and all(type(r.get('sequence')) is int and r['sequence'] == i and
            r.get('run_id') == identity['run_id'] for i, r in enumerate(rows, 1)), 'foreign/incomplete TTID stream')
    def one(kind):
        matches = [r for r in rows if r.get('kind') == kind]
        require(len(matches) == 1, 'missing/duplicate ' + kind)
        return matches[0]
    launch, registered, enable, witness = (one(k) for k in ['launch', 'ttid-observer-registered', 'rum-enable', 'ttid-message'])
    require(not any(r.get('kind') == 'ttid-observer-failure' for r in rows), 'TTID observer failed')
    backgrounds = [r for r in rows if r.get('kind') == 'native_background']
    require(backgrounds and launch['sequence'] < registered['sequence'] < enable['sequence'] <
            witness['sequence'] < backgrounds[0]['sequence'], 'TTID witness outside registration/foreground boundary')
    payload = witness['payload']
    require(payload.get('payload_type') == 'TTIDMessage' and payload.get('vital_name') == 'time_to_initial_display',
            'wrong TTID witness type')
    attributes = payload.get('attributes')
    require(type(attributes) is dict and set(attributes) == {'application.id', 'session.id', 'view.id', 'view.name'},
            'missing/extra TTID attributes')
    values = {}
    for key, kind in [('application.id', 'String'), ('session.id', 'String'), ('view.id', '[String]'), ('view.name', '[String]')]:
        item = attributes[key]
        require(type(item) is dict and set(item) == {'type', 'value'} and item['type'] == kind, 'wrong typed TTID attribute')
        value = item['value']
        if kind == '[String]':
            require(type(value) is list and len(value) == 1, 'ambiguous TTID owner')
            value = value[0]
        require(type(value) is str and value, 'invalid TTID attribute')
        values[key] = value
    require(values['application.id'] == expected['application_id'] and
            values['session.id'] == expected['session_id'] == local['session_id'], 'foreign TTID application/session')
    owner = values['view.id']
    require(owner in local['views'], 'unmapped TTID view')
    view = local['views'][owner]['event']['view']
    require(view['name'] == values['view.name'] and type(view.get('url')) is str and view['url'], 'TTID view name/path differs')
    identifier(payload.get('vital_id'))
    require(type(payload.get('duration_ns')) is int and payload['duration_ns'] > 0, 'invalid TTID duration')
    for key in ['raw_date_reference_seconds', 'raw_date_unix_seconds', 'server_time_offset_seconds']:
        require(type(payload.get(key)) in (int, float) and math.isfinite(payload[key]), 'invalid TTID date/offset')
    require(payload['raw_date_reference_seconds'] + 978307200 == payload['raw_date_unix_seconds'], 'inconsistent raw TTID date')
    corrected = sdk_milliseconds(payload['raw_date_reference_seconds'] + payload['server_time_offset_seconds'] + 978307200)
    require(corrected > 0, 'invalid corrected TTID date')
    return dict(sequence=witness['sequence'], view_id=owner, view_name=view['name'], view_url=view['url'],
                vital_id=payload['vital_id'], duration_ns=payload['duration_ns'], corrected_date_ms=corrected,
                application_id=values['application.id'], session_id=values['session.id'])


def persisted(row, event, witness):
    """An exact dispatch join; omissions and stale/wrong values are not normalized."""
    client_date = row['attributes'].get('client_time', event.get('date'))
    require(event.get('type') == 'vital' and field(event, 'vital.type') == 'app_launch' and
            field(event, 'vital.name') == 'time_to_initial_display' and field(event, 'vital.app_launch_metric') == 'ttid' and
            field(event, 'vital.id') == witness['vital_id'] and field(event, 'application.id') == witness['application_id'] and
            field(event, 'session.id') == witness['session_id'] and field(event, 'view.id') == witness['view_id'] and
            field(event, 'view.name') == witness['view_name'] and field(event, 'view.url') == witness['view_url'] and
            type(field(event, 'vital.duration')) is int and field(event, 'vital.duration') == witness['duration_ns'] and
            type(client_date) is int and client_date == witness['corrected_date_ms'] and
            ('date' not in event or type(event['date']) is int and event['date'] == client_date),
            'persisted TTID differs from exact dispatch witness')
    return dict(raw_id=row['id'], witness_sequence=witness['sequence'], vital_id=witness['vital_id'],
                view_id=witness['view_id'], disposition='EXACT_TTID_DISPATCH_WITNESS')
