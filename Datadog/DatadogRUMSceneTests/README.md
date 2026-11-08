# SwiftUI scene regression tests

Run the shared `DatadogRUMSceneTests` scheme on an iOS 27 or newer simulator:

```sh
make test-ios SCHEME="DatadogRUMSceneTests" DEVICE="<installed iPhone simulator>"
```

The separate UIKit host supplies one connected scene and its delegate-owned window.
The tests install their content into that window and restore it afterward. The
standard Example app and existing SDK test targets keep their original host setup.

The suite covers view registration and lifetime, disappearance, ordinary tracked
views, committed navigation transitions, semantic navigation, observed destination
adapters, and native NavigationStack ownership. Tests use mock HTTP and synthetic
events. They need no client token, backend access, login, taps, or physical device.

Run the tests serially. They temporarily install main-actor testing callbacks.
The shared scheme disables parallel execution for this test bundle.

There are 32 named tests with Swift 6.4 or newer. The two observed-adapter tests
and two native-stack tests retain their compiler guards. Earlier supported
compilers discover 28 tests; that is compiler coverage, not qualification of the
four guarded tests. Each test also retains its iOS 27 availability check. An
unsupported-system skip does not count as a behavioral pass.

Files are divided by responsibility. Shared setup stays in
`DatadogRUMSceneTests.swift`; helpers shared across files are internal only to
the test module. JSON XCTest attachments contain synthetic observations to help
diagnose assertion failures.
