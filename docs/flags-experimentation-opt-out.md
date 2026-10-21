# Per-subject experimentation opt-out

Enable immediate opt-out when creating the Flags client. The default is disabled.
The application owns the subject's preference and timestamp.

```swift
import DatadogFlags

// Initialize Datadog and enable Flags before creating the client.
let client = FlagsClient.create(experimentationOptOutMode: .immediate)

// Omit this attribute when the subject can participate in experimentation.
let context = FlagsEvaluationContext(
    targetingKey: "subject-123",
    attributes: [
        "dd_experimentation_opt_out_at": .string("2026-10-21T12:00:00Z")
    ]
)
client.setEvaluationContext(context) { result in
    switch result {
    case .success:
        let enabled = client.getBooleanValue(key: "new-route-planner", defaultValue: false)
        // Use the assigned ordinary feature value.
    case .failure:
        // Evaluations use the application's defaults when no valid assignments exist.
        break
    }
}
```

A valid RFC3339 string excludes the subject immediately, even if the timestamp is in the future.
The Precompute service skips experiment allocations and continues through ordinary feature allocations.
If no ordinary allocation matches, evaluation returns the application's default value.

Malformed strings, nulls, and non-string values return `invalidContext` without making a request.
The SDK does not guess the subject's preference. Disabled mode ignores the attribute.

The Precompute service must acknowledge experimentation opt-out before the client accepts its assignments.
An unsupported service cannot silently return experimental assignments. The SDK uses only cached assignments
that match the current context and opt-out policy. Otherwise it returns application defaults.

Opt-out does not disable evaluation telemetry or RUM flag annotations. Excluded experiment allocations do not produce exposures.
Immediate withdrawal can change an enrolled subject's experience. Account for that change in experiment analysis.

Client configuration is fixed for each client name. Creating an existing named client returns its original configuration.
