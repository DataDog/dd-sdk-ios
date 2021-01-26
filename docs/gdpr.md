# Tracking Consent

### Tracking consent values

To be compliant with the GDPR regulation, the SDK requires the tracking consent value at initialization.
The `trackingConsent` can be one of the following values:

1. `TrackingConsent.pending` - the SDK starts collecting and batching the data but does not send it to Datadog. The SDK waits for the new tracking consent value to decide what to do with the batched data.
2. `TrackingConsent.granted` - the SDK starts collecting the data and sends it to Datadog.
3. `TrackingConsent.notGranted` - the SDK does not collect any data: logs, traces, and RUM events are not sent to Datadog.
   
### Updating the tracking consent at runtime

To change the tracking consent value after the SDK is initialized, use the `Datadog.set(trackingConsent:)` API call.
The SDK changes its behavior according to the new value. For example, if the current tracking consent is `.pending`:

- if changed to `.granted`, the SDK will send all current and future data to Datadog;
- if changed to `.notGranted`, the SDK will wipe all current data and will not collect any future data.
