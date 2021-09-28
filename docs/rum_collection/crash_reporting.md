---
title: Crash Reporting and Error Tracking (beta)
kind: documentation
beta: true
further_reading:
  - link: "https://github.com/DataDog/dd-sdk-ios"
    tag: "GitHub"
    text: "dd-sdk-ios Source Code"
  - link: "/real_user_monitoring"
    tag: "Documentation"
    text: "Learn how to explore your RUM data"
---
## Overview

<div class="alert alert-info"><p>Crash Reporting and Error Tracking is in beta.</p>
</div>
Enable iOS crash reporting and error tracking to get comprehensive crash reports and error trends in the RUM UI. With this beta feature, you have access to:

 - Aggregated iOS crash data and RUM crash attributes
 - Desymbolicated iOS error reports
 - Trend analysis with iOS error tracking

This guide follows the setup for iOS crash reporting and error tracking in the following steps:
 - Crash reporting
 - Desymbolicate error reports
 - Verify setup

### Add crash reporting 

If you have not set up the SDK yet, follow the [in-app setup instructions][1] or refer to the [iOS RUM setup documentation][2]. Upgrade to [dd-sdk-ios v1.7.0+][3] to get access to iOS crash reporting and error tracking. 

Update your initialization snippet to include crash reporting:


```
import DatadogCrashReporting

Datadog.initialize(
    appContext: .init(),
    trackingConsent: .pending,
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

### Desymbolicate reports

If your mobile iOS source code is symbolicated, upload your dSYM file to Datadog so that your different stack traces can be desymbolicated. For a given error, you can get access to the file path, the line number, as well as a code snippet for each frame of the related stack trace.

#### Install Datadog CI

If you haven't already, install the [Datadog CI][4] through NPM or Yarn. The package is under [@datadog/datadog-ci][5]. 

```sh
# NPM
npm install --save-dev @datadog/datadog-ci

# Yarn
yarn add --dev @datadog/datadog-ci
```

If you need `datadog-ci` as a CLI tool instead of a package, you can run it with [`npx`][6] or install globally:

```sh
# npx
npx @datadog/datadog-ci [command]

# NPM install globally
npm install -g @datadog/datadog-ci

# Yarn v1 add globally
yarn global add @datadog/datadog-ci
```

#### Upload dSYM files

<div class="alert alert-warning"><p>This command runs only in macOS.</p></div>

First, ensure you have `DATADOG_API_KEY` in your environment.

```bash
# Environment setup
export DATADOG_API_KEY="<API KEY>"
```

**Note**: To configure the tool to use the EU endpoint, set the `DATADOG_SITE` environment variable to `datadoghq.eu`. To override the full URL for the intake endpoint, define the `DATADOG_DSYM_INTAKE_URL` environment variable.

Use the `upload` command to upload dSYM files in your derived path:

```bash
datadog-ci dsyms upload ~/Library/Developer/Xcode/DerivedData/
```

Optional parameters include the following:

* `--max-concurrency` (default: `20`): Number of concurrent uploads to the API.
* `--dry-run` (default: `false`): The command runs without the final upload step. All other checks are performed.


If your application has Bitcode enabled, download your app's dSYM files on [App Store Connect][7].
These files come in `zip` format named `appDsyms.zip`. Point to the `zip` file to run `datadog-ci`.

```bash
datadog-ci dsyms upload ~/Downloads/appDsyms.zip
```

### Verify setup

To verify the command works as expected, trigger a test run and verify it returns 0:

```bash
export DATADOG_API_KEY='<API key>'

// At this point, build any project in Xcode to produce dSYM files in Derived Data path,
// assuming your Derived Data path is ~/Library/Developer/Xcode/DerivedData/.

yarn launch dsyms upload ~/Library/Developer/Xcode/DerivedData/
```

Successful output resembles:

```bash
Starting upload with concurrency 20. 
Will look for dSYMs in /Users/mert.buran/Library/Developer/Xcode/DerivedData
Uploading dSYM with 00000-11111-00000-11111 from /path/to/dsym/file1.dSYM
Uploading dSYM with 00000-22222-00000-22222 from /path/to/dsym/file2.dSYM
Uploading dSYM with 00000-33333-00000-33333 from /path/to/dsym/file3.dSYM
...

Command summary:
✅ Uploaded 5 dSYMs in 8.281 seconds.
✨  Done in 10.71s.
```

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: https://app.datadoghq.com/rum/application/create
[2]: /real_user_monitoring/ios
[3]: https://github.com/DataDog/dd-sdk-ios/releases
[4]: https://github.com/DataDog/datadog-ci
[5]: https://www.npmjs.com/package/@datadog/datadog-ci
[6]: https://www.npmjs.com/package/npx
[7]: https://appstoreconnect.apple.com/
