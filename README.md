# Datadog iOS/macOS SDK

> Swift library to interact with Datadog.

⚠️ This is an **alpha version** of the SDK and source breaking changes might be introduced in `1.0.0`. 

## Getting Started

TBD

## Example Projects

This repository contains example projects showing SDK features (see `examples/` folder). To send logs to Datadog, you must create `examples/examples-secret.xcconfig` file with your own client token obtained on Datadog website. The file must have following structure:

```xml
DATADOG_CLIENT_TOKEN=your-own-token-generated-on-datadog-website

```

You can use `./tools/kickoff.sh` tool to have the file template generated for you. See more in `CONTRIBUTING.md`.

## Contributing

Pull requests are welcome. First, open an issue to discuss what you would like to change. For more information, read the [Contributing Guide](CONTRIBUTING.md).

## License

[Apache License, v2.0](LICENSE)
