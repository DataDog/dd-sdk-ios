---
title: Troubleshooting
kind: documentation
further_reading:
  - link: "https://github.com/DataDog/dd-sdk-ios"
    tag: "Github"
    text: "dd-sdk-ios Source code"
  - link: "/real_user_monitoring"
    tag: "Homepage"
    text: "Explore Datadog RUM"
---

## Check if Datadog SDK is properly initialized

After configuring Datadog SDK and running the app for the first time this is recommended to look at your debugger console in Xcode. The SDK implements several consistency checks and prints relevant warnings if something is missconfigured.

## Debugging
When writing your application, you can enable development logs by setting the `verbosityLevel` value. Relevant messages from the SDK with a priority equal to or higher than the provided level are then printed to debugger console in Xcode:

```swift
Datadog.verbosityLevel = .debug
```

If all goes well you should see output similar to this saying that a batch of RUM data was properly uploaded:
```
[DATADOG SDK] 🐶 → 17:23:09.849 [DEBUG] ⏳ (rum) Uploading batch...
[DATADOG SDK] 🐶 → 17:23:10.972 [DEBUG]    → (rum) accepted, won't be retransmitted: success
```

**Note:** It is recommended to only use `Datadog.verbosityLevel` in `DEBUG` configuration and keep it unset in `RELEASE`.

## Set tracking consent (GDPR compliance)

To be compliant with the GDPR regulation, the SDK requires the tracking consent value at initialization.
The `trackingConsent` can be one of the following values:

1. `.pending` - the SDK starts collecting and batching the data but does not send it to Datadog. The SDK waits for the new tracking consent value to decide what to do with the batched data.
2. `.granted` - the SDK starts collecting the data and sends it to Datadog.
3. `.notGranted` - the SDK does not collect any data: logs, traces, and RUM events are not sent to Datadog.

To change the tracking consent value after the SDK is initialized, use the `Datadog.set(trackingConsent:)` API call.
The SDK changes its behavior according to the new value. For example, if the current tracking consent is `.pending`:

- if changed to `.granted`, the SDK will send all current and future data to Datadog;
- if changed to `.notGranted`, the SDK will wipe all current data and will not collect any future data.

## Sample RUM sessions

To control the data your application sends to Datadog RUM, you can specify a sampling rate for RUM sessions while [initializing the SDK][1] as a percentage between 0 and 100.

For instance, to only keep 50% of sessions use:
```swift
Datadog.initialize(
    // ...
    configuration: Datadog.Configuration
        .builderUsing(/* ... */)
        .set(rumSessionsSamplingRate: 50.0)
        // ...
        .build()
)
```

## Sending data when device is offline

RUM ensures availability of data when your user device is offline. In cases of low-network areas, or when the device battery is too low, all the RUM events are first stored on the local device in batches. They are sent as soon as the network is available, and the battery is high enough to ensure the SDK does not impact the end user's experience. If the network is not available while your application is in the foreground, or if an upload of data fails, the batch is kept until it can be sent successfully.

This means that even if users open your application while offline, no data is lost.

**Note**: The data on the disk is automatically discarded if it gets too old to ensure the SDK doesn't use too much disk space.

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]:/real_user_monitoring/ios/advanced_configuration/#initialization-parameters
