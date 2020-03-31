# Datadog SDK for iOS

> Swift and Objective-C libraries to interact with Datadog on iOS.

## Getting Started

See the dedicated [Datadog iOS log collection](https://docs.datadoghq.com/logs/log_collection/ios/?tab=us) documentation to learn how to send logs from your iOS application to Datadog.


## Example Projects

This repository contains example projects showing SDK features (see `examples/` folder). To send logs to Datadog, you must configure `examples/examples-secret.xcconfig` file with your own client token obtained on Datadog website. Use `make examples` tool to have the file template generated for you:

```xml
DATADOG_CLIENT_TOKEN=your-own-token-generated-on-datadog-website
```

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)
