## **Deprecated**

**Note:** The `DatadogAlamofireExtension` pod is deprecated and will no longer be maintained. Please refer to the [Integrated Libraries][6] documentation on how to instrument Alamofire with the Datadog iOS SDK.

---

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

### Carthage and SPM

The Datadog [Alamofire][1] integration doesn't support [Carthage][2] or [SPM][3], however, the code needed for set up is very low. You may want to include the source files from this folder directly in your project.

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

Using this setup makes the Datadog SDK track requests from this instance of the `Alamofire.Session`.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](../../../CONTRIBUTING.md).

## License

[Apache License, v2.0](../../../LICENSE)

[1]: https://github.com/Alamofire/Alamofire
[2]: https://github.com/Carthage/Carthage
[3]: https://swift.org/package-manager/
[4]: https://docs.datadoghq.com/tracing/setup_overview/setup/ios/
[5]: https://docs.datadoghq.com/real_user_monitoring/ios
[6]: https://docs.datadoghq.com/real_user_monitoring/mobile_and_tv_monitoring/integrated_libraries/ios
