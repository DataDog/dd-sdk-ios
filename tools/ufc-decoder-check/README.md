# ufc-decoder-check

Checks the hand-written `ufc.proto` decoder of `DatadogFlags` (`DatadogFlags/Sources/Rules`) against SwiftProtobuf.

The SDK does not depend on SwiftProtobuf. Only this development tool does.

## What it checks

- It builds rules-based configurations with SwiftProtobuf that use every message, field, oneof case and enum, decodes the same bytes with both decoders, and compares every field.
- It checks unknown fields, unpacked repeated values and invalid data (both decoders must reject it).
- It corrupts bytes at random and checks that both decoders agree.
- It compares decoding speed for 1, 100 and 1,000 flags.

`Sources/UFCDecoderCheck/HandWritten` links to the decoder files of `DatadogFlags`, so the tool always checks the current code.

## Run

From the repository root, with `protoc` and the `protoc-gen-swift` plugin of SwiftProtobuf:

```sh
./tools/ufc-decoder-check/run.sh --plugin-path <path to protoc-gen-swift>
```

Run it after every change to `DatadogFlags/Protos/ufc.proto` or to `DatadogFlags/Sources/Rules`. The script exits with an error if any check fails.
