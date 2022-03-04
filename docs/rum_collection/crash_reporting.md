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

If you have not set up the SDK yet, follow the [in-app setup instructions][1] or see the [iOS RUM setup documentation][2].

#### Dependency Manager
{{< tabs >}}
{{% tab "CocoaPods" %}}
Add `DatadogSDKCrashReporting` to your `Podfile`:
```ruby
platform :ios, '11.0'
use_frameworks!

target 'App' do
  pod 'DatadogSDKCrashReporting'
end
```
{{% /tab %}}
{{% tab "Swift Package Manager" %}}
Add the package at `https://github.com/DataDog/dd-sdk-ios` and link `DatadogCrashReporting` to your application target.

**Note:** If you link to `Datadog` or the `DatadogStatic` library, replace it with `DatadogCrashReporting`.

{{% /tab %}}
{{% tab "Carthage" %}}
Add `github "DataDog/dd-sdk-ios"` to your `Cartfile` and link `DatadogCrashReporting.xcframework` to your application target.
{{% /tab %}}
{{< /tabs >}}

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

### Symbolicate reports

If your iOS error is unsymbolicated, upload your dSYM file using one of the following tools to symbolicate your different stack traces. For any given error, you have access to the file path, the line number, and a code snippet for each frame of the related stack trace.

#### Fastlane Plugin

The Datadog plugin helps you upload dSYM files to Datadog from your fastlane configuration.

1. Add [`fastlane-plugin-datadog`][3] to your project
```sh
fastlane add_plugin datadog
```

2. Then configure fastlane to upload your symbols, e.g.:
```ruby
# download_dsyms action feeds dsym_paths automatically
lane :upload_dsym_with_download_dsyms do
  download_dsyms
  upload_symbols_to_datadog(api_key: "datadog-api-key")
end
```
> See [`fastlane-plugin-datadog`][3] for more instructions.

#### Github Action

The [Datadog Upload dSYMs GitHub Action][4] let you upload your symbols during your GitHub Action jobs:

```yml
name: Upload dSYM Files

jobs:
  build:
    runs-on: macos-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v2

      - name: Generate/Download dSYM Files
        uses: ./release.sh

      - name: Upload dSYMs to Datadog
        uses: DataDog/upload-dsyms-github-action@v1
        with:
          api_key: ${{ secrets.DATADOG_API_KEY }}
          site: datadoghq.com
          dsym_paths: |
            path/to/dsyms/folder
            path/to/zip/dsyms.zip
```

#### Datadog CI

You can also use the command line tool [@datadog/datadog-ci][5] to upload your dSYM file:

```sh
export DATADOG_API_KEY="<API KEY>"

// if you have a zip file containing dSYMs
npx @datadog/datadog-ci dsyms upload appDsyms.zip

// if you have a folder containing dSYMs
npx @datadog/datadog-ci dsyms upload /path/to/appDsyms/
```

**Note**: To configure the tool to use the EU endpoint, set the `DATADOG_SITE` environment variable to `datadoghq.eu`. To override the full URL for the intake endpoint, define the `DATADOG_DSYM_INTAKE_URL` environment variable. 

If your application has Bitcode enabled, download your app's dSYM files on [App Store Connect][6]. For more information, see [dSYMs commands][7].


## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: https://app.datadoghq.com/rum/application/create
[2]: https://docs.datadoghq.com/real_user_monitoring/ios
[3]: https://github.com/DataDog/datadog-fastlane-plugin
[4]: https://github.com/marketplace/actions/datadog-upload-dsyms
[5]: https://www.npmjs.com/package/@datadog/datadog-ci
[6]: https://appstoreconnect.apple.com/
[7]: https://github.com/DataDog/datadog-ci/blob/master/src/commands/dsyms/README.md
