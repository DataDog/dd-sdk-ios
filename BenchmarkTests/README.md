# Benchmark Tests

[Synthetics for Mobile](https://docs.datadoghq.com/mobile_app_testing/) runs Benchmark test scenarios to collect metrics of the SDK performances.

## Setup

To open the project with the correct environment, make sure Xcode is closed and then run the following command:

```bash
make benchmark-tests-open
```

## Development

Each scenario is independent and can be considered as an app within the runner.

### Create a scenario

A scenario must comply with the [`Scenario`](Runner/Scenarios/Scenario.swift) protocol. Upon start, a scenario initializes the SDK, enables features, and returns a root view-controller.

Here is a simple example of a scenario using Logs:
```swift
import Foundation
import UIKit

import DatadogCore
import DatadogLogs

struct LogsScenario: Scenario {

    /// The initial view-controller of the scenario
    let initialViewController: UIViewController = LoggerViewController()

    /// Start instrumenting the application by enabling the Datadog SDK and
    /// its Features.
    ///
    /// - Parameter info: The application information to use during SDK
    /// initialisation.
    func instrument(with info: AppInfo) {

        Datadog.initialize(
            with: .benchmark(info: info), // SDK init with the benchmark configuration
            trackingConsent: .granted
        )

        Logs.enable()
    }
}
```

Once the scenario is created, add its name as an enum case of the [`SyntheticScenario`](Runner/Scenarios/SyntheticScenario.swift#L12) object so it can be selected by setting the `BENCHMARK_SCENARIO` environment variable.

### Run a scenario

There are two ways to execute a scenario:
1. Use environment variables in the `Runner.xcscheme` (Edit Scheme from Xcode)
```xml
<EnvironmentVariables>
    <EnvironmentVariable
        key = "BENCHMARK_RUN"
        value = "<run>"
        isEnabled = "YES">
    </EnvironmentVariable>
    <EnvironmentVariable
        key = "BENCHMARK_SCENARIO"
        value = "<scenario>"
        isEnabled = "YES">
    </EnvironmentVariable>
</EnvironmentVariables>
```
2. Open a deep link:
```bash
xcrun simctl openurl booted 'bench://start?scenario=<scenario>&run=<run>'
```
If you need to execute multiple scenarios/runs in the same application process, you must stop the previous execution with: 
```bash
xcrun simctl openurl booted 'bench://stop'
```

### Synthetics Configuration

Please refer to the [Confluence page (internal)](https://datadoghq.atlassian.net/wiki/spaces/RUMP/pages/3981476482/Benchmarks+iOS)

## CI

CI continuously builds, signs, and uploads a runner application to Synthetics, which runs predefined tests.

### Build

Before building the application, make sure the `BenchmarkTests/xcconfigs/Benchmark.local.xcconfig` configuration file is present and contains the `Mobile - Integration Org` client token, RUM application ID, and API Key. These values are sensitive and must be securely stored.

```ini
CLIENT_TOKEN=
RUM_APPLICATION_ID=
API_KEY=
```

### Sign

To sign the runner application, the certificate and provision profile defined in [Synthetics.xcconfig](xcconfigs/Synthetics.xcconfig) and in [exportOptions.plist](exportOptions.plist) needs to be installed on the build machine. The certificate and profile are sensitive files and must be securely stored. Make sure to update both files when updating the certificate and provisioning profile, otherwise signing fails.

> [!NOTE]
> Certificate & Provisioning Profile are also available through the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi). But we don't have the tooling in place.

### Upload

The application version (build number) is set to the commit SHA of the current job, and the build is uploaded to Synthetics using the [datadog-ci](https://github.com/DataDog/datadog-ci) CLI. This step expects environment variables to authenticate with the `Mobile - Integration Org`:

```bash
export DATADOG_API_KEY=
export DATADOG_APP_KEY=
export S8S_APPLICATION_ID=
```
