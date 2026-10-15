"""Create EXP-223 observation from frozen passive automatic components.

Only the copied fixture changes. Previously qualified automatic products and
source helpers stay byte-for-byte unchanged.
"""
import hashlib
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'automatic-coverage'))
import human_variant


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('transition fixture source anchor changed')
    return text.replace(old, new)


def observation(original, fingerprint):
    value = human_variant.render(original, fingerprint).decode()
    value = replace_once(value, '    private var sequence = 0', '''    private var sequence = 0
    private var latestViews: [String: [String: Any]] = [:]''')
    value = replace_once(value, '        sequence += 1\n        let row:', '''        sequence += 1
        var payload = payload
        if kind == "rum", let type = payload["type"] as? String, type == "view",
           let view = payload["view"] as? [String: Any], let id = view["id"] as? String {
            latestViews[id] = ["sequence": sequence, "view": view,
                "session": payload["session"] ?? [:], "date": payload["date"] ?? NSNull(),
                "document": payload["_dd"] ?? [:]]
        }
        if kind.hasPrefix("transition_") || kind == "human_snapshot" || kind == "native_model" {
            payload["mapper_views"] = latestViews.keys.sorted().compactMap { latestViews[$0] }
        }
        let row:''')
    value = replace_once(value, '    static let runID = value("--run-id")', '''    static let runID = value("--run-id")
    static let tracking = value("--tracking", "automatic")
    static let nonce = value("--nonce")''')
    value = replace_once(value, '"multiple_scenes": UIApplication.shared.supportsMultipleScenes])', '''"multiple_scenes": UIApplication.shared.supportsMultipleScenes,
            "tracking": Settings.tracking, "nonce": Settings.nonce,
            "source": Bundle.main.object(forInfoDictionaryKey: "TransitionSource") ?? "missing",
            "fixture": Bundle.main.object(forInfoDictionaryKey: "TransitionFixture") ?? "missing"])''')
    value = replace_once(value, '''Datadog.Configuration(clientToken: "local-fixture-no-credentials",
            env: "exp195-automatic", service: "exp195-automatic")''', '''Datadog.Configuration(clientToken: Bundle.main.object(forInfoDictionaryKey: "TransitionClientToken") as? String ?? "",
            env: "s2-transitions", service: "ios-s2-transition-validation")''')
    value = replace_once(value, 'RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000195")',
                         'RUM.Configuration(applicationID: Bundle.main.object(forInfoDictionaryKey: "TransitionApplicationID") as? String ?? "")')
    value = replace_once(value, '            configuration.swiftUIViewsPredicate = DefaultSwiftUIRUMViewsPredicate()',
                         '            if Settings.tracking == "automatic" { configuration.swiftUIViewsPredicate = DefaultSwiftUIRUMViewsPredicate() }')
    value = replace_once(value, '        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!', '''        configuration.sessionSampleRate = 100
        configuration.trackBackgroundEvents = false
        configuration.trackFrustrations = false
        configuration.longTaskThreshold = nil
        configuration.appHangThreshold = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackMemoryWarnings = false
        configuration.trackSlowFrames = false
        configuration.trackWatchdogTerminations = false''')
    value = replace_once(value, '            Task { @MainActor in captureGeometry() }\n        })', '            Task { @MainActor in TransitionObservation.shared.close(reason: \"background\"); captureGeometry() }\n        })')
    value = replace_once(value, '    static func captureGeometry() {', '''    static func disappeared(_ screen: String) {
        ObservationStore.shared.append("native_disappear", ["screen": screen,
            "request_id": HumanObservation.shared.currentRequestID ?? "nil"])
    }
    static func captureGeometry() {''')
    return value.encode()


def human(original, fingerprint):
    if hashlib.sha256(original).hexdigest() != fingerprint:
        raise ValueError('frozen human observer source changed')
    value = original.decode()
    value = replace_once(value, '    private var firstAppearance: String?', '''    private var firstAppearance: String?
    private var bundlePaths: [ObjectIdentifier: String] = [:]

    private func bundlePath(for objectType: AnyClass) -> String {
        let identifier = ObjectIdentifier(objectType)
        if let path = bundlePaths[identifier] { return path }
        let path = Bundle(for: objectType).bundleURL.path
        if bundlePaths.count < 128 { bundlePaths[identifier] = path }
        return path
    }''')
    for before, after in [
        ('Bundle(for: type(of: $0)).bundleURL.path', 'self.bundlePath(for: type(of: $0))'),
        ('Bundle(for: type(of: window)).bundleURL.path', 'self.bundlePath(for: type(of: window))'),
        ('Bundle(for: UIWindow.self).bundleURL.path', 'bundlePath(for: UIWindow.self)'),
        ('Bundle(for: UINavigationController.self).bundleURL.path', 'bundlePath(for: UINavigationController.self)'),
        ('Bundle(for: UISplitViewController.self).bundleURL.path', 'bundlePath(for: UISplitViewController.self)'),
        ('Bundle(for: UIHostingController<EmptyView>.self).bundleURL.path', 'bundlePath(for: UIHostingController<EmptyView>.self)'),
        ('Bundle(for: UIViewController.self).bundleURL.path', 'bundlePath(for: UIViewController.self)')
    ]:
        expected = 2 if before == 'Bundle(for: UIWindow.self).bundleURL.path' else 1
        if value.count(before) != expected:
            raise ValueError('immutable bundle lookup anchor changed')
        value = value.replace(before, after)
    value = replace_once(value, '        bindWindowIfReady(); observeScrolls()',
                         '        bindWindowIfReady(); observeScrolls(); TransitionObservation.shared.prepare(requestID: requestID, phase: phase)')
    value = replace_once(value, '"phase": phase, "uptime_ns": DispatchTime.now().uptimeNanoseconds, "topology":',
                         '"phase": phase, "uptime_ns": DispatchTime.now().uptimeNanoseconds, "transition": TransitionObservation.shared.snapshot(), "topology":')
    return value.encode()
