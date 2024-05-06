# End to End Tests

E2E Test scenarios are run in [Synthetics for Mobile](https://docs.datadoghq.com/mobile_app_testing/) and [Monitors](https://docs.datadoghq.com/monitors/) will assert the proper propagation of data.


## CI

CI will continuously build, sign, and upload a Runner application to Synthetics which will run predefined Tests daily.

### Build

Before building the application, the `E2ETests/xcconfigs/E2E.local.xcconfig` configuration file must be present with the `Mobile - Integration Org` client token and RUM application ID, these values are sensitive and must be securely stored.

```ini
CLIENT_TOKEN=
RUM_APPLICATION_ID=
```

> [!TIP]
> Files can be base64 encoded and stored in secret variables. To copy the encoded file content, you can do:
> ```bash
> cat E2ETests/xcconfigs/E2E.local.xcconfig | base64 | pbcopy
> ```

### Sign

To sign the Runner application, the Certificate and Provision Profile defined in [Synthetics.xcconfig](xcconfigs/Synthetics.xcconfig) and in [exportOptions.plist](exportOptions.plist) needs to be installed on the build machine, these files are sensitive and must be securely stored. Make sure to update both files when updating the Certificate and Provisioning Profile, otherwise signing will fail.

> [!NOTE]
> Certificate & Provisioning Profile could be downloaded using [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi) instead of stored CI secrets. But we don't have the tooling in place.

### Upload

The application version (build number) will be set to the commit SHA of the current job, and the build will be uploaded to Synthetics using the [datadog-ci](https://github.com/DataDog/datadog-ci) CLI. This step expects environment variables to authenticate with the  `Mobile - Integration Org`:

```bash
export DATADOG_API_KEY=
export DATADOG_APP_KEY=
export S8S_APPLICATION_ID=
```

## Development

Each scenario is independent and can be considered as an app within the Runner.

### Create a Scenario

A scenario must comply with the [`Scenario`](Runner/Scenarios/Scenario.swift) protocol. Upon start, a scenario will initialize the SDK, enable Features, and return a root view-controller.

Here is a simple example of a scenario using Logs:
```swift
import Foundation
import UIKit

import DatadogCore
import DatadogLogs

struct SessionReplayWebViewScenario: Scenario {

    func start(info: TestInfo) -> UIViewController {

        Datadog.initialize(
            with: .e2e(info: info), // SDK init with the e2e configuration
            trackingConsent: .granted
        )

        Logs.enable()

        return LoggerViewController()
    }
}
```

The test should then be added to the [`SyntheticScenario`](Runner/Scenarios/Scenario.swift) enumeration so it can be selected, either manually or by setting the `E2E_SCENARIO` environment variable.


### Adding the Test in Synthetics

When creating a test in Synthetics, make sure to **always run on the latest version**.

You can skip the Scenario selection screen by setting the `Process Arguments` of the Synthetic test:
```json
{
  "E2E_SCENARIO": "<name of the test>"
}
```

The test's name must match the [`SyntheticScenario`](Runner/Scenarios/Scenario.swift) enum case.