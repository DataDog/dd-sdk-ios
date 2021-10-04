---
title: iOS Crash Reporting and Error Tracking
kind: documentation
beta: true
further_reading:
  - link: "https://datadoghq.com/blog/ios-crash-reporting-datadog/"
    tag: "Blog"
    text: "Introducing iOS Crash Reporting and Error Tracking"
  - link: "/real_user_monitoring"
    tag: "Documentation"
    text: "Learn how to explore your RUM data"
---
## Overview

<div class="alert alert-info"><p>iOS Crash Reporting and Error Tracking is in beta. Upgrade to <a href="https://github.com/DataDog/dd-sdk-ios/releases">dd-sdk-ios v1.7.0+</a> to get access.</p>
</div>

Enable iOS Crash Reporting and Error Tracking to get comprehensive crash reports and error trends with Real User Monitoring. With this feature, you get access to:

 - Aggregated iOS crash dashboards and attributes
 - Symbolicated iOS crash reports
 - Trend analysis with iOS error tracking

## Setup

### Add crash reporting 

If you have not set up the SDK yet, follow the [in-app setup instructions][1] or refer to the [iOS RUM setup documentation][2]. 

Add the `DatadogCrashReporting` dependency to your project. For CocoaPods, use `pod 'DatadogSDKCrashReporting'`. For SPM and Carthage, `DatadogCrashReporting` is available with `dd-sdk-ios`.

| Package manager            | Installation method                                                                         |
|----------------------------|-------------------------------------------------------|
| CocoaPods                  | Use `pod 'DatadogSDKCrashReporting'`                      |
| Swift Package Manager      | Link the `DatadogCrashReporting` module                   |
| Carthage                   | Use `DatadogCrashReporting.xcframework`               |


Update your initialization snippet to include crash reporting:

```
import DatadogCrashReporting

Datadog.initialize(
    appContext: .init(),
    trackingConsent: .granted,
    configuration: Datadog.Configuration
    .builderUsing(
        rumApplicationID: "<rum_application_id>",
        clientToken: "<client_token>",
        environment: "<environment_name>"
    )
    .trackUIKitActions()
    .trackUIKitRUMViews()
    .enableCrashReporting(using: DDCrashReportingPlugin())
    .build()
)
Global.rum = RUMMonitor.initialize()
```

### Symbolicate reports using Datadog CI

If your iOS error is unsymbolicated, upload your dSYM file using [@datadog/datadog-ci][5] to symbolicate your different stack traces. For any given error, you have access to the file path, the line number, and a code snippet for each frame of the related stack trace. 

```sh
export DATADOG_API_KEY="<API KEY>"

// if you have a zip file containing dSYMs
npx @datadog/datadog-ci dsyms upload appDsyms.zip

// if you have a folder containing dSYMs
npx @datadog/datadog-ci dsyms upload /path/to/appDsyms/
```

**Note**: To configure the tool to use the EU endpoint, set the `DATADOG_SITE` environment variable to `datadoghq.eu`. To override the full URL for the intake endpoint, define the `DATADOG_DSYM_INTAKE_URL` environment variable. 

If your application has Bitcode enabled, download your app's dSYM files on [App Store Connect][7]. For more information, see [dSYMs commands][8].


## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: https://app.datadoghq.com/rum/application/create
[2]: /real_user_monitoring/ios
[3]: https://github.com/DataDog/dd-sdk-ios/releases
[4]: https://github.com/DataDog/datadog-ci
[5]: https://www.npmjs.com/package/@datadog/datadog-ci
[6]: https://www.npmjs.com/package/npx
[7]: https://appstoreconnect.apple.com/
[8]: https://github.com/DataDog/datadog-ci/blob/master/src/commands/dsyms/README.md
