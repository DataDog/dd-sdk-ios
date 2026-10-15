"""Observation-only hooks in isolated Debug SDK copies, applied to both arms."""
from pathlib import Path


def install(sdk):
    path = Path(sdk) / 'DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift'
    text = path.read_text()
    start = text.index('    private func presentationBinding(\n')
    end = text.index('    private func semanticPresentation(', start)
    factory = text[start:end]
    if '\n        Binding(' in factory:
        factory = factory.replace('\n        Binding(', '\n        let binding: Binding<Presentation?> = Binding(', 1)
    else:
        assert '\n        navigationState.presentationBinding(' in factory
        factory = factory.replace('\n        navigationState.presentationBinding(', '\n        let binding = navigationState.presentationBinding(', 1)
    assert factory.endswith('    }\n\n')
    factory = factory[:-7] + '        RUMPresentationFixtureHooks.onBinding?(style, binding)\n        return binding\n    }\n\n'
    text = text[:start] + factory + text[end:]
    start = text.index('private struct RUMSemanticPresentationBoundary<')
    end = text.index('internal final class RUMSemanticNavigationContainerLifetimeState', start)
    boundary = text[start:end]
    old = '        self.content = content()\n'
    assert boundary.count(old) == 1
    uses_occurrence = 'let mount: (RUMSceneIdentifier) -> Bool' in boundary
    mount = '_ = observedMount(scene)' if uses_occurrence else 'observedMount(item, scene)'
    disappear = 'observedDisappear()' if uses_occurrence else 'observedDisappear(item)'
    hook = ('        let observedMount = self.mount\n'
            '        let observedDisappear = self.disappear\n'
            '        RUMPresentationFixtureHooks.onBoundary?(self.content, .init(\n'
            '            mount: { scene in ' + mount + ' },\n'
            '            disappear: { ' + disappear + ' }\n'
            '        ))\n')
    boundary = boundary.replace(old, old + hook)
    text = text[:start] + boundary + text[end:]
    text += '''
#if DEBUG && os(iOS)
@available(iOS 27.0, *)
@MainActor
internal struct RUMPresentationFixtureCallbacks {
    let mount: (RUMSceneIdentifier) -> Void
    let disappear: () -> Void
}

@available(iOS 27.0, *)
@MainActor
internal enum RUMPresentationFixtureHooks {
    static var onBinding: ((RUMNavigationPresentationStyle, Any) -> Void)?
    static var onBoundary: ((Any, RUMPresentationFixtureCallbacks) -> Void)?
}
#endif
'''
    path.write_text(text)
    return {'purpose': 'Observe actual production Binding and boundary closures; no routing/state logic changes',
            'binding_factory_observed': True, 'boundary_callbacks_observed': True,
            'occurrence_callback_signature': uses_occurrence}
