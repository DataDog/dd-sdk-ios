"""Render the bounded F08 patch from exact accepted app inputs; no in-place edits."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFINITION = json.loads((HERE / 'capture-definition.json').read_text())
OBSERVABILITY = 'Targets/Platform/DatadogObservability/'
APP = 'Targets/DatadogApp/'
DELEGATE = APP + 'UI/App/Root/Signed In Root/SignedInRootCoordinator+UINavigationControllerDelegate.swift'
DASHBOARD = APP + 'UI/App/Root/Signed In Root/Datadog Products/Dashboards/Details/DashboardDetailViewController.swift'


def replace(text, before, after):
    if text.count(before) != 1:
        raise ValueError('app capture anchor is missing or ambiguous')
    return text.replace(before, after)


def render(source):
    """Return only declared changed files, preserving the original source directory."""
    source = Path(source).resolve(strict=True)
    original = {}
    for relative, fingerprint in DEFINITION['existing_input_sources'].items():
        path = source / relative
        if path.is_symlink() or not path.resolve().is_relative_to(source):
            raise ValueError('source escapes frozen checkout')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != fingerprint:
            raise ValueError('frozen app input differs: ' + relative)
        original[relative] = data.decode()
    result = dict(original)
    path = OBSERVABILITY + 'ObservabilitySystem.swift'
    result[path] = replace(result[path], '                    RUM.enable(with: rumConfig)',
                          '#if os(iOS)\n                    ReleaseValidationCapture.configure(&rumConfig)\n#endif\n\n                    RUM.enable(with: rumConfig)')
    path = OBSERVABILITY + 'UserMonitorLive.swift'
    text = result[path]
    expression = '                    content.trackRUMView(name: name.rawValue, attributes: attributes.raw)'
    text = replace(text, expression, expression + '''
#if os(iOS)
                        .onAppear { ReleaseValidationCapture.swiftUI("appear", name: name.rawValue) }
                        .onDisappear { ReleaseValidationCapture.swiftUI("disappear", name: name.rawValue) }
#endif''')
    for operation, anchor in [
        ('startView', '                RUMMonitor.shared().startView(key: name.rawValue, attributes: attributes.raw)'),
        ('stopView', '                RUMMonitor.shared().stopView(key: name.rawValue, attributes: attributes.raw)'),
        ('addAction', '                RUMMonitor.shared().addAction(type: RUMActionType(type), name: name.rawValue, attributes: attributes.raw)'),
    ]:
        text = replace(text, anchor, '#if os(iOS)\n                ReleaseValidationCapture.manual("' + operation + '", name: name.rawValue)\n#endif\n' + anchor)
    text = replace(text, '''        else {
            return nil
        }

        var attributes = UserMonitor.Attributes.context''', '''        else {
            ReleaseValidationCapture.predicate(viewController, name: nil)
            return nil
        }

        ReleaseValidationCapture.predicate(viewController, name: viewName)
        var attributes = UserMonitor.Attributes.context''')
    result[path] = text
    path = APP + 'WindowController.swift'
    result[path] = replace(result[path], 'import AuthenticationCore', 'import AuthenticationCore\nimport DatadogObservability')
    result[path] = replace(result[path], '        window.makeKeyAndVisible()',
                          '        ReleaseValidationCapture.window(window)\n        window.makeKeyAndVisible()')
    path = APP + 'SceneDelegate.swift'
    text = replace(result[path], 'import CoreMobileDevice', 'import CoreMobileDevice\nimport DatadogObservability')
    for method in ('sceneWillResignActive', 'sceneDidEnterBackground', 'sceneDidBecomeActive'):
        short = method[5:];short = short[0].lower() + short[1:]
        anchor = '    func ' + method + '(_ scene: UIScene) {'
        text = replace(text, anchor, anchor + '\n        ReleaseValidationCapture.scene("' + short + '-enter", scene: scene)\n        defer { ReleaseValidationCapture.scene("' + short + '-exit", scene: scene) }')
    result[path] = text
    text = replace(result[DELEGATE], 'import UIKit', 'import DatadogObservability\nimport UIKit')
    for phase in ('willShow', 'didShow'):
        anchor = '    func navigationController(_ navigationController: UINavigationController, ' + phase + ' viewController: UIViewController, animated: Bool) {'
        text = replace(text, anchor, anchor + '\n        ReleaseValidationCapture.navigation("' + phase + '-enter", navigation: navigationController, controller: viewController, animated: animated)\n        defer { ReleaseValidationCapture.navigation("' + phase + '-exit", navigation: navigationController, controller: viewController, animated: animated) }')
    result[DELEGATE] = text
    text = replace(result[DASHBOARD], 'import DatadogWebViewTracking', 'import DatadogObservability\nimport DatadogWebViewTracking')
    text = replace(text, '    private func setUpWebView(_ webView: WKWebView) {',
                   '    private func setUpWebView(_ webView: WKWebView) {\n        ReleaseValidationCapture.webView(webView, controller: self)')
    anchor = '    // MARK: - View Lifecycle'
    methods = []
    for callback in ('viewDidAppear', 'viewDidDisappear'):
        methods.append('''    override func %s(_ animated: Bool) {
        ReleaseValidationCapture.controller("%s-enter", controller: self)
        super.%s(animated)
        ReleaseValidationCapture.controller("%s-exit", controller: self)
    }
''' % (callback, callback, callback, callback))
    text = replace(text, anchor, anchor + '\n\n' + '\n'.join(methods))
    result[DASHBOARD] = text
    result[OBSERVABILITY + 'ReleaseValidationCapture.swift'] = (HERE / 'ReleaseValidationCapture.swift').read_text()
    return {relative: text.encode() for relative, text in result.items()}


def stage(source, destination):
    """Stage the seven-file overlay only, without copying configs or app products."""
    files = render(source)
    destination = Path(destination)
    if destination.exists():
        raise ValueError('overlay destination already exists')
    destination.mkdir(parents=True)
    for relative, data in files.items():
        path = destination / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    receipt = dict(schema_version=1, state='OVERLAY_PREPARED_NOT_APPLIED',
                   definition_sha256=hashlib.sha256((HERE / 'capture-definition.json').read_bytes()).hexdigest(),
                   source_sha256=DEFINITION['existing_input_sources'],
                   overlay_sha256={p: hashlib.sha256(v).hexdigest() for p, v in files.items()},
                   builds=0, native_launches=0)
    (destination / 'overlay.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    arguments = parser.parse_args()
    result = stage(arguments.source, arguments.destination)
    print(json.dumps(dict(state=result['state'], files=len(result['overlay_sha256']))))
