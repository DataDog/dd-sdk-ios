## Platforms

| Platform   | Supported |  Version  |
|------------|:---------:|-------:|
| **iOS**    |     ✅    |  `11+` |
| **tvOS**   |     ✅    |  `11+` |
| **iPadOS** |     ✅    |  `11+` |
| **visionOS** |   ⚠️    |  `1.0+` |
| **macOS**  |     ⚠️    |  `10.15+` |
| **watchOS**|     ❌    |  `n/a` |
| **Linux**  |     ❌    |  `n/a` |

## VisionOS

VisionOS is not officially supported by Datadog SDK. Some features may not be fully functional. Note that `CrashReporting` is not supported on VisionOS, due to lack of support on the [PLCrashReporter side](https://github.com/microsoft/plcrashreporter/issues/288).

## MacOS

MacOS is not officially supported by Datadog SDK. Some features may not be fully functional. Note that `RUM`, which heavily depends on `UIKit` does not build on macOS.

## Xcode

SDK is built using the most recent version of Xcode, but we make sure that it's backward compatible with the [lowest supported Xcode version for AppStore submission](https://developer.apple.com/news/?id=jd9wcyov).

## Dependency Managers

We currently support integration of the SDK using following dependency managers.
- [Swift Package Manager](https://docs.datadoghq.com/logs/log_collection/ios/?tab=swiftpackagemanagerspm)
- [Cocoapods](https://docs.datadoghq.com/logs/log_collection/ios/?tab=cocoapods)
- [Carthage](https://docs.datadoghq.com/logs/log_collection/ios/?tab=carthage)

## Languages

| Language        |   Version    |
|-----------------|:------------:|
| **Swift**       |     `5.*`    |
| **Objective-C** |     `2.0`    |

## UI Framework Instrumentation

| Framework       |   Automatic  | Manual |
|-----------------|:------------:|:------:|
| **UIKit**       |       ✅     |   ✅    |
| **SwiftUI**     |       ❌     |   ✅    |

## Networking Compatibility
| Framework       |   Automatic  | Manual |
|-----------------|:------------:|:------:|
| **URLSession**  |       ✅     |   ✅    |
|[**Alamofire 5+**](https://github.com/DataDog/dd-sdk-ios/tree/develop/DatadogExtensions/Alamofire) |       ❌     |   ✅    |
|  **SwiftNIO**   |       ❌     |   ❌    |

*Note: Third party networking libraries can be instrumented by implementing custom `DDURLSessionDelegate`.*

## Catalyst
We support Catalyst in build mode only, which means that macOS target will build, but functionalities for the SDK won't work for this target.

## Dependencies
The Datadog SDK depends on the following third-party library:
- [PLCrashReporter](https://github.com/microsoft/plcrashreporter) 1.11.1
