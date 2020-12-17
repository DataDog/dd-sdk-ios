# Datadog Integration for Alamofire

`DatadogAlamofireExtension` enables `Alamofire.Session` auto instrumentation with Datadog SDK.
It's a counterpart of `DDURLSessionDelegate` which we provide for native `URLSession` instrumentation.

## Getting Started

### CocoaPods

To include the Datadog integration for [Alamofire][1] in your project, add the
following to your `Podfile`.
```ruby
pod 'DatadogSDKAlamofireExtension'
```
`DatadogSDKAlamofireExtension` requires Datadog SDK `1.4.0` (or higher).

### Carthage and SPM

Although our [Alamofire][1] integration doesn't currently support [Carthage][2] nor [SPM][3], the number of code needed to set it up is very low and you may want to just include the source files from this folder directly in your project.

### Initial setup

Follow the regular steps for initializing Datadog SDK for [Tracing][4] or [RUM][5].

Instead of using `DDURLSessionDelegate` for `URLSession`, use `DDEventMonitor` and `DDRequestInterceptor` for `Alamofire.Session`:

```swift
import DatadogAlamofireExtension
import Alamofire

let alamofireSession = Session(
   interceptor: DDRequestInterceptor(),
   eventMonitors: [DDEventMonitor()]
)
```

This will make the Datadog SDK track requests sent from this instance of the `Alamofire.Session`.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](../../../CONTRIBUTING.md).

## License

[Apache License, v2.0](../../../LICENSE)

[1]: https://github.com/Alamofire/Alamofire
[2]: https://github.com/Carthage/Carthage
[3]: https://swift.org/package-manager/
[4]: https://docs.datadoghq.com/tracing/setup/ios/
[5]: https://docs.datadoghq.com/real_user_monitoring/ios
