# api-surface

> A command-line utility for listing public API interface for Swift modules.

This package provides a command-line tool for listing `public` interface of a Swift module.

## Usage

```
$ api-surface spm --library-name Foo --path ./Foo
```

Check `api-surface help`  for full overview.

## What is API surface?

API surface is a list of all public APIs exposed from a module. Given following Swift file:
```swift
import Foundation

public class Car {
    public enum Manufacturer: String {
        case manufacturer1
        case manufacturer2
        case manufacturer3
    }

    private let engine = Engine()

    public init(
        manufacturer: Manufacturer
    ) {}

    public func startEngine() -> Bool { engine.start() }
    public func stopEngine() -> Bool { engine.stop() }
}

internal struct Engine {
    func start() -> Bool { true }
    func stop() -> Bool { true }
}

public extension Car {
    var price: Int { 100 }
}
```
It's API surface is:
```
public class Car
 public enum Manufacturer: String
  case manufacturer1
  case manufacturer2
  case manufacturer3
 public init(manufacturer: Manufacturer)
 public func startEngine() -> Bool
 public func stopEngine() -> Bool
public extension Car
 var price: Int
```
## License

[Apache License, v2.0](../../LICENSE)
