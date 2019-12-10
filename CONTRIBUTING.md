# Contributing

## Installation

This project uses Swift Package Manager. To generate `Datadog.xcodeproj` simply run:
```bash
 swift package generate-xcodeproj
```

From there, you can use Xcode for development and tests. You can also run tests in command line:
```swift
swift test
```

## Coding Conventions

We use custom Xcode file templates for creating `.swift` files and unit test classes. Install them with:

```bash
cd tools/xcode-templates
./install-xcode-templates.sh 
```

💡 Note: restart of Xcode might be required.
