# Rules-based configuration schema

`ufc.proto` is a copy of the Feature Flags backend schema for rules-based configuration.
The browser SDK keeps the same file in `openfeature-js-client` (`packages/core/proto/ufc.proto`).

`DatadogFlags` decodes it with the hand-written decoder in `DatadogFlags/Sources/Rules` (`UFCReader.swift` and `UFCModels.swift`). There is no generated code.

## When the schema changes

1. Copy the new `ufc.proto` here.
2. Update `UFCModels.swift`: each message has a Swift type, and each field a `case <field number>:` in its decoder.
3. Add the new fields to `fixtures/all-fields.txtpb`, encode it again with `protoc` (see the command in the file), and check the new fields in `RulesConfigurationDecoderTests`.
