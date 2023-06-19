# Datadog SDK for iOS and tvOS

> Swift and Objective-C libraries to interact with Datadog on iOS and tvOS.

## Getting Started

### Log Collection

See the dedicated [Datadog iOS Log Collection](https://docs.datadoghq.com/logs/log_collection/ios) documentation to
learn how to send logs from your iOS application to Datadog.

![Datadog iOS Log Collection](docs/images/logging.png)

### Trace Collection

See [Datadog iOS Trace Collection](https://docs.datadoghq.com/tracing/setup_overview/setup/ios) documentation to try it
out.

![Datadog iOS Log Collection](docs/images/tracing.png)

### RUM Events Collection

See [Datadog iOS RUM Collection](https://docs.datadoghq.com/real_user_monitoring/ios) documentation to try it out.

![Datadog iOS RUM Collection](docs/images/rum.png)

## Supported Operating Systems

Typically, the Datadog iOS SDK supports operating system versions that are supported by the latest Xcode version. For
example, if the latest Xcode version supports building targets for iOS 11.0, then the Datadog iOS SDK supports iOS 11.0
and above.

| OS | Supported | Version | Notes |
| --- | --- | --- | --- |
| iOS | ✅ | 11.0+ | |
| tvOS | ✅ | 11.0+ | |
| catalyst | ✅ | 11.0+ | |
| macOS | ❌ | n/a | |
| watchOS | ❌ | n/a | |
| Linux | ❌ | n/a | |
| Windows | ❌ | n/a | |

## Integrations

### Alamofire

If you use [Alamofire](https://github.com/Alamofire/Alamofire), review the [`DatadogAlamofireExtension`
library](Sources/DatadogExtensions/Alamofire/) to learn how to automatically instrument requests with the Datadog iOS
SDK.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the
[Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)
