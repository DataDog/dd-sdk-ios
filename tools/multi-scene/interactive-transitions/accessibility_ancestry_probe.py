"""Diagnostic-only overlay for an unqualified public accessibility view alias.

The original traversal and its failure remain unchanged. This overlay records
the missing physical-parent discriminator; it never produces accepted controls.
"""
import hashlib
import json

ANCHOR = '''                    return [["capture_error": "public accessibility view has missing owned ancestry",
                             "current_view": actualView(view)]]'''

DIAGNOSTIC = r'''                    var chain = [[String: Any]]()
                    var retained = [UIView]()
                    var visited = Set<ObjectIdentifier>()
                    var current: UIView? = view
                    var termination = "depth-limit"
                    var firstCached: String = "nil"
                    while let node = current, chain.count < 256 {
                        let nodeID = ObjectIdentifier(node)
                        guard visited.insert(nodeID).inserted else { termination = "cycle"; break }
                        retained.append(node)
                        let parent = node.superview
                        let siblings = parent?.subviews ?? []
                        guard siblings.count <= 4096 else { termination = "inventory-limit"; break }
                        var record = actualView(node)
                        record["parent_children"] = siblings.map { Self.identity($0) }
                        record["reciprocal_memberships"] = siblings.filter { $0 === node }.count
                        record["cached"] = visual[nodeID] != nil
                        record["owned_window"] = node === window
                        if let cached = visual[nodeID] {
                            record["cached_view"] = capturedView(cached)
                            if firstCached == "nil" { firstCached = Self.identity(node) }
                        }
                        chain.append(record)
                        if node === window { termination = "owned-window"; break }
                        guard node.window === window else { termination = "foreign-window"; break }
                        guard let parent = parent else { termination = "detached"; break }
                        current = parent
                    }
                    let cache = visual.values.map { capturedView($0) }.sorted {
                        String(describing: $0["id"] ?? "nil") < String(describing: $1["id"] ?? "nil")
                    }
                    guard let cacheBytes = try? JSONSerialization.data(withJSONObject: cache, options: [.sortedKeys]) else {
                        return [["capture_error": "ancestry diagnostic cache encoding failed"]]
                    }
                    let digest = SHA256.hash(data: cacheBytes).map { String(format: "%02x", $0) }.joined()
                    let probe: [String: Any] = ["schema_version": 1,
                        "basis": "public superview and reciprocal subviews", "bound_window": Self.identity(window),
                        "chain": chain, "termination": termination, "first_cached_ancestor": firstCached,
                        "visual_cache": cache, "visual_cache_json": String(decoding: cacheBytes, as: UTF8.self),
                        "visual_cache_sha256": digest, "scenario_credit": false]
                    withExtendedLifetime(retained) {}
                    return [["capture_error": "public accessibility view has missing owned ancestry",
                             "current_view": actualView(view), "ancestry_probe": probe]]'''


def render(raw, source_sha256):
    if hashlib.sha256(raw).hexdigest() != source_sha256:
        raise ValueError('ancestry probe source changed')
    text = raw.decode()
    if text.count(ANCHOR) != 1 or 'ancestry_probe' in text or 'import CryptoKit\n' not in text:
        raise ValueError('ancestry probe requires the exact unmodified capture branch')
    return text.replace(ANCHOR, DIAGNOSTIC, 1).encode()


def classify(failure):
    """Classify actual reciprocal membership; all outcomes remain diagnostic."""
    if failure.get('capture_error') != 'public accessibility view has missing owned ancestry':
        raise ValueError('not the admitted missing-ancestry failure')
    probe = failure['ancestry_probe']
    chain = probe['chain']; cache = probe['visual_cache']
    if (probe['schema_version'] != 1 or probe['scenario_credit'] is not False
            or not chain or len(chain) > 256 or not cache or len(cache) > 4096):
        raise ValueError('incomplete ancestry diagnostic')
    raw = probe['visual_cache_json'].encode()
    if hashlib.sha256(raw).hexdigest() != probe['visual_cache_sha256'] or json.loads(raw) != cache:
        raise ValueError('visual cache bytes differ')
    if chain[0]['id'] != failure['current_view']['id'] or len({r['id'] for r in chain}) != len(chain):
        raise ValueError('aliased or foreign chain')
    if any(chain[0][key] != value for key, value in failure['current_view'].items()):
        raise ValueError('alias observation differs from chain')
    cached = {r['id']: r for r in cache}
    if len(cached) != len(cache):
        raise ValueError('duplicate cached identity')
    first = next((r['id'] for r in chain if r['id'] in cached), 'nil')
    if probe['first_cached_ancestor'] != first:
        raise ValueError('first cached ancestor differs')
    for index, row in enumerate(chain):
        if row['cached'] != (row['id'] in cached) or (row['cached'] and row.get('cached_view') != cached[row['id']]):
            raise ValueError('cached ancestry evidence differs')
        if (type(row['reciprocal_memberships']) is not int or row['reciprocal_memberships'] not in (0, 1)
                or len(set(row['parent_children'])) != len(row['parent_children'])
                or row['reciprocal_memberships'] != row['parent_children'].count(row['id'])):
            raise ValueError('reciprocal membership differs')
        if index + 1 < len(chain) and row['parent'] != chain[index + 1]['id']:
            raise ValueError('disconnected superview chain')
    if probe['termination'] != 'owned-window':
        return 'INCONCLUSIVE_' + probe['termination'].upper().replace('-', '_')
    if (chain[-1]['id'] != probe['bound_window'] or chain[-1]['owned_window'] is not True
            or chain[-1]['parent'] != 'nil'
            or any(r['window'] != probe['bound_window'] or r['owned_window'] is not False for r in chain[:-1])):
        raise ValueError('chain does not reach the bound window')
    if any(r['reciprocal_memberships'] != 1 for r in chain[:-1]):
        return 'NONRECIPROCAL_ACCESSIBILITY_ALIAS'
    return 'RECIPROCAL_ATTACHED_ALIAS'
