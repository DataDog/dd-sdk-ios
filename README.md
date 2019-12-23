# Datadog SDK for iOS

> A client-side iOS library to interact with Datadog.

## Getting Started 

_TBD_

## Usage

_TBD_

## Example Application

This repository contains example application demonstrating SDK features. To send real logs, you must create `examples/dd-config.plist` file with your own secret obtained on Datadog website. The file must have following structure:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>clientToken</key>
	<string>generate client token on Datadog website and paste it here</string>
</dict>
</plist>

```

You can also use `./tools/kickoff.sh` tool to have the file template generated for you. See more in `CONTRIBUTING.md`.

## Contributing

_TBD_

## License

_TBD_
