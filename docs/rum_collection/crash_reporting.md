---
title: Crash Reporting
kind: documentation
further_reading:
  - link: "https://github.com/DataDog/dd-sdk-ios"
    tag: "Github"
    text: "dd-sdk-ios Source code"
  - link: "/real_user_monitoring"
    tag: "Documentation"
    text: "Datadog Real User Monitoring"
---

Enable iOS crash reporting and error tracking to get comprehensive crash reports, and error trends in RUM UI. With this beta feature, you get access to 

 - Aggregated iOS crash data and RUM crash attributes
 - Desymbolicated iOS error reports
 - Trend analysis with iOS error tracking

This guide follows the setup for iOS crash reporting and error tracking in the following steps
 - Add crash reporting
 - Desymbolicate error reports
 - Verify setup

### Add crash reporting 

If you have not set up the SDK yet, follow the [in-app setup instructions][1] or refer to the [iOS RUM setup documentation][2]. Upgrade to [dd-sdk-ios v1.7.0+][3] to get access to iOS crash reporting and error tracking. Update your initialization snippet to include crash reporting:


```
Datadog.initialize(
    appContext: .init(),
    trackingConsent: .pending,
    configuration: Datadog.Configuration
    .builderUsing(
        rumApplicationID: "APP_ID",
        clientToken: "CLIENT_TOKEN",
        environment: "ENVIRONMENT"
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

If you haven't already, install [Datadog CI][4] through NPM or Yarn. The package is under [@datadog/datadog-ci][5]. 

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

**This command runs only in macOS.**

To begin with ensure you have `DATADOG_API_KEY` in your environment.

```bash
# Environment setup
export DATADOG_API_KEY="<API KEY>"
```

Note: To configure the tool to use EU endpoint define `DATADOG_SITE` environment variable to `datadoghq.eu`. To override the full URL for the intake endpoint define the `DATADOG_DSYM_INTAKE_URL` environment variable.

Use the `upload` command to upload dSYM files in your derived path

```bash
datadog-ci dsyms upload ~/Library/Developer/Xcode/DerivedData/
```

In addition, some optional parameters are available:

* `--max-concurrency` (default: `20`): number of concurrent upload to the API.
* `--dry-run` (default: `false`): it will run the command without the final step of upload. All other checks are performed.


If your app has bitcode enabled, download your app's dSYM files from [App Store Connect][7].
They come in the form of a zip file, named `appDsyms.zip`. Run `datadog-ci` by pointing to the zip file.

```bash
datadog-ci dsyms upload ~/Downloads/appDsyms.zip
```

### Verify setup

To verify this command works as expected, you can trigger a test run and verify it returns 0:

```bash
export DATADOG_API_KEY='<API key>'

// at this point, build any project in Xcode so that it produces dSYM files in Derived Data path
// assuming your Derived Data path is ~/Library/Developer/Xcode/DerivedData/

yarn launch dsyms upload ~/Library/Developer/Xcode/DerivedData/
```

Successful output should look like this:

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

[1]: https://app.datadoghq.com/rum/application/create
[2]: /real_user_monitoring/ios
[3]: https://github.com/DataDog/dd-sdk-ios/releases
[4]: https://github.com/DataDog/datadog-ci
[5]: https://www.npmjs.com/package/@datadog/datadog-ci
[6]: https://www.npmjs.com/package/npx
[7]: https://appstoreconnect.apple.com/
