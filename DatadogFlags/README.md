# Evaluation telemetry control

Enable the evaluation telemetry control when creating a Flags client:

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

The option defaults to `false`. When enabled and the context is known, only a typed boolean `true` suppresses new evaluation events, evaluation counts, and automatic RUM flag annotations. Missing, false, null, numeric, and string values do not suppress them.

Telemetry suppression does not change flag evaluation, exposure logging, or unrelated telemetry. It does not remove events or annotations recorded before the update.

The attribute remains available in assignment requests, stored context, and exposure attributes. Applications can use it in targeting rules. Changes use the normal assignment refresh and exposure deduplication behavior. A targeting rule can therefore change an assignment when this attribute changes.

The latest requested context controls telemetry suppression immediately, including while an assignment refresh is pending or fails. Before the first context update, cached context controls suppression. When the option is enabled, evaluation telemetry is suppressed while that initial cache read is pending because its policy is not yet known. Reporting resumes if the read finds no opt-out or an explicitly supplied context allows it. The client configuration still determines whether suppression is enabled.

Each client keeps its own configuration and current policy. If a client name already exists, `create` returns that client and keeps its original configuration.

This option controls evaluation telemetry only. Exposure events can still contain subject data. It does not replace the SDK tracking-consent API.
