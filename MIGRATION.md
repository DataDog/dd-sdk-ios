# Migration from 1.x to 2.0

This document describes the main changes introduced in SDK `2.0` compared to `1.x`.

### Product Modules 

All the products (RUM, Trace, Logs, etc.) are now extracted into different modules. That allows you to integrate only what is needed into your application.

In comparison with version 1.x where all products were in a single module `Datadog`, now you need to adopt the following libraries instead:

- `DatadogCore`
- `DatadogLogs`
- `DatadogTrace`
- `DatadogRUM`
- `DatadogWebViewTracking`

These come in addition to the existing `DatadogCrashReporting` and `DatadogObjc`.

**NOTE**: In case of Crash Reporting and WebView Tracking usage it's also needed to add RUM and/or Logs modules to be able to report events to RUM and/or Logs respectively.

The `2.0` version of the iOS SDK also expose unified API layouts and naming between iOS and Android SDKs and with other Datadog products.

### Support for multiple SDK instances

Previously Datadog SDK implemented a singleton and only one SDK instance could exist in the application process. This created obstacles for use-cases like the usage of the SDK by 3rd party libraries.

With version 2.0 we addressed this limitation:

* Now it is possible to initialize multiple instances of the SDK, associating them with a name.
* Many methods of the SDK can optionally take a SDK instance as an argument. If not provided, the call will be associated with the default (nameless) SDK instance.

Here is an example illustrating the typical usage in case of default instance vs named instance:

```swift
// default instance
Datadog.initialize(
    with: configuration, 
    trackingConsent: trackingConsent
)

Datadog.setUserInfo(...)

// named instance
let core = Datadog.initialize(
    with: configuration, 
    trackingConsent: trackingConsent, 
    instanceName: "myInstance"
)

Datadog.setUserInfo(..., in: core)
```

**NOTE**: SDK instance name should have the same value between application runs. Storage paths for SDK events are associated with it.

You can retrieve the named SDK instance by calling `Datadog.sdkInstance(named: "<name>")` and use the `Datadog.isInitialized(instanceName: "<name>")` method to check if the particular SDK instance is initialized.

## SDK Configuration Changes

Better SDK granularity is achieved with the extraction of different products into independent modules, therefor all product-specific configurations have been moved to their dedicated modules.

> The SDK must be initialized before enabling any product.

The Builder pattern of the SDK initialization has been removed in favor of structure definitions. The following example shows how a `1.x` initialization would translate in `2.0`.

**V1 Initialization**
```swift
import Datadog

Datadog.initialize(
    appContext: .init(),
    trackingConsent: .granted,
    configuration: Datadog.Configuration
        .builderUsing(
            clientToken: "<client token>",
            environment: "<environment>"
        )
        .set(serviceName: "<service name>")
        .build()
```
**V2 Initialization**
```swift
import DatadogCore

Datadog.initialize(
    with: Datadog.Configuration(
        clientToken: "<client token>",
        env: "<environment>",
        service: "<service name>"
    ), 
    trackingConsent: .granted
)
```

API changes:

|`1.x`|`2.0`|
|---|---|
|`Datadog.Configuration.Builder.set(serviceName:)`|`Datadog.Configuration.service`|
|`Datadog.Configuration.Builder.set(batchSize:)`|`Datadog.Configuration.batchSize`|
|`Datadog.Configuration.Builder.set(uploadFrequency:)`|`Datadog.Configuration.uploadFrequency`|
|`Datadog.Configuration.Builder.set(proxyConfiguration:)`|`Datadog.Configuration.proxyConfiguration`|
|`Datadog.Configuration.Builder.set(encryption:)`|`Datadog.Configuration.encryption`|
|`Datadog.Configuration.Builder.set(serverDateProvider:)`|`Datadog.Configuration.serverDateProvider`|
|`Datadog.AppContext(mainBundle:)`|`Datadog.Configuration.bundle`|

## Logs Product Changes

All the classes related to Logs are now strictly in the `DatadogLogs` module. You will first need to enable the product:

```swift
import DatadogLogs

Logs.enable()
```

Then, you can create a logger instance:

```swift
import DatadogLogs

let logger = Logger.create(with: Logger.Configuration(name: "<logger name>"))
```

API changes:

|`1.x`|`2.0`|
|---|---|
|`Datadog.Configuration.Builder.setLogEventMapper`|`Logs.Configuration.eventMapper`|
|`Datadog.Configuration.Builder.set(loggingSamplingRate:)`|`Logs.Configuration.eventMapper`|
|`Logger.Builder.set(serviceName:)`|`Logger.Configuration.service`|
|`Logger.Builder.set(loggerName:)`|`Logger.Configuration.name`|
|`Logger.Builder.sendNetworkInfo`|`Logger.Configuration.networkInfoEnabled`|
|`Logger.Builder.bundleWithRUM`|`Logger.Configuration.bundleWithRumEnabled`|
|`Logger.Builder.bundleWithTrace`|`Logger.Configuration.bundleWithTraceEnabled`|
|`Logger.Builder.sendLogsToDatadog = false`|`Logger.Configuration.remoteSampleRate = 0`|
|`Logger.Builder.set(datadogReportingThreshold:)`|`Logger.Configuration.remoteLogThreshold`|
|`Logger.Builder.printLogsToConsole(:, usingFormat)`|`Logger.Configuration.consoleLogFormat`|

## APM Trace Product Changes

All the classes related to Trace are now strictly in the `DatadogTrace` module. You will first need to enable the product:

```swift
import DatadogTrace

Trace.enable()
```

Then, you can access the shared Tracer instance:

```swift
import DatadogTrace

let tracer = Tracer.shared()
```

API changes:

|`1.x`|`2.0`|
|---|---|
|`Datadog.Configuration.Builder.trackURLSession`|`Trace.Configuration.urlSessionTracking`|
|`Datadog.Configuration.Builder.setSpanEventMapper`|`Trace.Configuration.eventMapper`|
|`Datadog.Configuration.Builder.set(tracingSamplingRate:)`|`Trace.Configuration.sampleRate`|
|`Tracer.Configuration.serviceName`|`Trace.Configuration.service`|
|`Tracer.Configuration.sendNetworkInfo`|`Trace.Configuration.networkInfoEnabled`|
|`Tracer.Configuration.globalTags`|`Trace.Configuration.tags`|
|`Tracer.Configuration.bundleWithRUM`|`Trace.Configuration.bundleWithRumEnabled`|
|`Tracer.Configuration.samplingRate`|`Trace.Configuration.sampleRate`|

## RUM Product Changes

All the classes related to RUM are now strictly in the `DatadogRUM` module. You will first need to enable the product:

```swift
import DatadogRUM

RUM.enable(
    with: RUM.Configuration(applicationID: "<RUM Application ID>")
)
```

Then, you can access the shared RUM monitor instance:

```swift
import DatadogRUM

let monitor = RUMMonitor.shared()
```

API changes:

|`1.x`|`2.0`|
|---|---|
|`Datadog.Configuration.Builder.trackURLSession`|`RUM.Configuration.urlSessionTracking`|
|`Datadog.Configuration.Builder.set(rumSessionsSamplingRate:)`|`RUM.Configuration.sessionSampleRate`|
|`Datadog.Configuration.Builder.onRUMSessionStart`|`RUM.Configuration.onSessionStart`|
|`Datadog.Configuration.Builder.trackUIKitRUMViews(using:)`|`RUM.Configuration.uiKitViewsPredicate`|
|`Datadog.Configuration.Builder.trackUIKitRUMActions(using:)`|`RUM.Configuration.uiKitActionsPredicate`|
|`Datadog.Configuration.Builder.trackRUMLongTasks(threshold:)`|`RUM.Configuration.longTaskThreshold`|
|`Datadog.Configuration.Builder.setRUMViewEventMapper`|`RUM.Configuration.viewEventMapper`|
|`Datadog.Configuration.Builder.setRUMResourceEventMapper`|`RUM.Configuration.resourceEventMapper`|
|`Datadog.Configuration.Builder.setRUMActionEventMapper`|`RUM.Configuration.actionEventMapper`|
|`Datadog.Configuration.Builder.setRUMErrorEventMapper`|`RUM.Configuration.errorEventMapper`|
|`Datadog.Configuration.Builder.setRUMLongTaskEventMapper`|`RUM.Configuration.longTaskEventMapper`|
|`Datadog.Configuration.Builder.setRUMResourceAttributesProvider`|`RUM.Configuration.urlSessionTracking.resourceAttributesProvider`|
|`Datadog.Configuration.Builder.trackBackgroundEvents`|`RUM.Configuration.trackBackgroundEvents`|
|`Datadog.Configuration.Builder.trackFrustrations`|`RUM.Configuration.frustrationsTracking`|
|`Datadog.Configuration.Builder.set(mobileVitalsFrequency:)`|`RUM.Configuration.vitalsUpdateFrequency`|
|`Datadog.Configuration.Builder.set(sampleTelemetry:)`|`RUM.Configuration.telemetrySampleRate`|

## Crash Reporting Changes

To enable Crash Reporting, make sure to also enable RUM and/or Logs.

```swift
import DatadogCrashReporting

CrashReporting.enable()
```

|`1.x`|`2.0`|
|---|---|
|`Datadog.Configuration.Builder.enableCrashReporting()`|`CrashReporting.enable`|

## WebViewTracking Changes

To enable WebViewTracking, make sure to also enable RUM and/or Logs.

```swift
import WebKit
import DatadogWebViewTracking

let webView = WKWebView(...)
WebViewTracking.enable(webView: webView)
```

|`1.x`|`2.0`|
|---|---|
|`WKUserContentController.startTrackingDatadogEvents`|`WebViewTracking.enable(webView:)`|