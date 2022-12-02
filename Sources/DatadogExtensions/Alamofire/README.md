# Datadog Integration for Alamofire

`DatadogAlamofireExtension` enables `Alamofire.Session` auto instrumentation with Datadog SDK.
It's a counterpart of `DDURLSessionDelegate`, which is provided for native `URLSession` instrumentation.

## Getting started

### CocoaPods

To include the Datadog integration for [Alamofire][1] in your project, add the
following to your `Podfile`:
```ruby
pod 'DatadogSDKAlamofireExtension'
```
`DatadogSDKAlamofireExtension` requires Datadog SDK `1.5.0` or higher and `Alamofire 5.0` or higher.

### SPM

To include the Datadog integration for [Alamofire][1] in your project, add the
following to your `Package.swift` file:
```swift
    dependencies: [
        .package(url: "https://github.com/DataDog/dd-sdk-ios", branch: "develop"),
    ],
    targets: [
        .target(
            name: "YourTargetHere",
            dependencies: [
                .product(name: "DatadogAlamofireExtension", package: "dd-sdk-ios"),
            ])
    ],
]
```
`DatadogSDKAlamofireExtension` requires Datadog SDK `1.5.0` or later and `Alamofire 5.0` or later.

### Carthage

The Datadog [Alamofire][1] integration doesn't support [Carthage][2], however, the code needed for set up is very low. You may want to include the source files from this folder directly in your project.

### Initial setup

Follow the regular steps for initializing Datadog SDK for [Tracing][3] or [RUM][4].

Instead of using `DDURLSessionDelegate` for `URLSession`, use `DDEventMonitor` and `DDRequestInterceptor` for `Alamofire.Session`:

```swift
import DatadogAlamofireExtension
import Alamofire

let alamofireSession = Session(
   interceptor: DDRequestInterceptor(),
   eventMonitors: [DDEventMonitor()]
)
```

Using this setup makes the Datadog SDK track requests from this instance of the `Alamofire.Session`.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](../../../CONTRIBUTING.md).

## License

[Apache License, v2.0](../../../LICENSE)

[1]: https://github.com/Alamofire/Alamofire
[2]: https://github.com/Carthage/Carthage
[3]: https://docs.datadoghq.com/tracing/setup_overview/setup/ios/
[4]: https://docs.datadoghq.com/real_user_monitoring/ios
