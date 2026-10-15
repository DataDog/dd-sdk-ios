# Evaluation telemetry control

Enable the local context control when creating a Flags client:

```swift
Flags.enable()
let client = FlagsClient.create(
    configuration: .init(enableEvaluationTelemetryOptOutParameter: true)
)

client.setEvaluationContext(
    FlagsEvaluationContext(
        targetingKey: "user-123",
        attributes: ["dd_evaluation_telemetry_opt_out": .bool(true)]
    )
)
```

The option defaults to `false`. When enabled, only a typed boolean `true` suppresses new evaluation events, evaluation counts, and automatic RUM flag annotations. Missing, false, null, numeric, and string values do not suppress them.

The SDK preserves flag values, details, exposure logging, and unrelated telemetry. It does not remove events or annotations recorded before the update.

When enabled, the SDK consumes the reserved attribute locally and excludes it from assignment requests. Changes to only this attribute take effect immediately. They do not request assignments, change readiness, or clear cached assignments. Genuine targeting changes still use the normal assignment refresh behavior. Repeating the same complete context still requests a refresh.

Each client keeps its own configuration and current policy. If a client name already exists, `create` returns that client and keeps its original configuration.

This option controls evaluation telemetry only. Exposure events can still contain subject data. It does not replace the SDK tracking-consent API.
