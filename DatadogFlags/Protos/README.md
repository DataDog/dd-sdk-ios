# Rules-based configuration schema

`ufc.proto` is a copy of the Feature Flags backend schema for rules-based configuration.
The browser SDK keeps the same file in `openfeature-js-client` (`packages/core/proto/ufc.proto`).

`DatadogFlags/Sources/Rules/Generated/ufc.pb.swift` is generated from it. Do not edit the generated file.

## Regenerate

Build `protoc-gen-swift` from SwiftProtobuf at the minimum version in `Package.swift` (1.38.1), then run from the repository root:

```sh
./tools/protoc-ufc.sh --plugin-path <path to protoc-gen-swift>
```

The script generates internal types and keeps the `SwiftProtobuf` import internal, so `SwiftProtobuf` is not part of the `DatadogFlags` public interface.
