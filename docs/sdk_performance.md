# SDK Performance and impact on the host application

## Methodology

The following benchmarks were collected by running Datadog iOS SDK ([fe86f81](https://github.com/DataDog/dd-sdk-ios/commit/fe86f8151e0a7932bb397f98cb166a9c81f5dac9)) in open source application: [Beam](https://github.com/awkward/beam). Performance data was recorded with Xcode 14.3 (14E222b) Debug Navigator and network traffic was recorded with [Charles Proxy 4.6.4](https://www.charlesproxy.com/download/latest-release/) installed on macOS.

**3** **configurations** were measured:

- running app with SDK not initialized;

- running app with SDK initialized and data collection enabled (`trackingConsent: .granted`);

- running app with SDK initialized but data collection disabled (`trackingConsent: .notGranted`).

**Application info**:

[Beam](https://github.com/awkward/beam) is an open source Reddit client, available on the App Store (see [Beam for reddit](https://apps.apple.com/us/app/beam-for-reddit/id937987469)). All tests were performed for [759623f](https://github.com/awkward/beam/commit/759623fae6df021d9a04ab5ef63cb6520029fba6) commit using `Release` configuration with debugger attached.

**iOS Device info**:

All data was collected on iPhone 13 (MLPF3F/A), running iOS 16.4.1 (a) with 42,54GB of available memory (out of 128GB). This device had 147 apps installed, but no other applications were running during the tests. The device was connected to the LTE network and WIFI interface.

## Results

Rows represent individual test runs and columns represent each scenario:

- “SDK not initialized” - SDK is installed, but not initialized.

- “Consent granted” - SDK is initialized with data collection enabled (tracking consent: `.granted`).

- “Consent not granted” - SDK is initialized with data collection disabled (tracking consent: `.notGranted`).

### Max CPU (in %)

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|41%|46%|42%|
|#2|37%|51%|39%|
|#3|42%|45%|47%|
|#4|36%|42%|38%|
|#5|44%|37%|36%|

<u>No significant difference in CPU pick</u>.

### Max RAM (in MBs)

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|70.7 MB|78.6 MB|88.2 MB|
|#2|64.9 MB|77 MB|76.9 MB|
|#3|66.8 MB|75.2 MB|68.3 MB|
|#4|70.8MB|58.5 MB|71.8 MB|
|#5|66.6MB|72.7 MB|77.3 MB|


<u>No significant difference in RAM pick</u>.

### High CPU Utilization (% of periods with CPU utilization higher than 20%)

CPU usage of greater than 20%. High CPU utilization rapidly drains a device’s battery.

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|2.7%|3.3%|3.3%|
|#2|3.3%|3.1%|3.4%|
|#3|2.9%|3.2%|3.8%|
|#4|2.9%|3.1%|3.3%|
|#5|3%|2.8%|3.4%|

<u>No significant difference in high CPU utilization</u>.

### Battery Utilization - Overhead

Overhead represents energy use as a result of bringing up radios and other system resources the app needs to perform work.

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|39.2%|46.7%|36.9%|
|#2|39.7%|44.1%|38%|
|#3|41%|45.2%|35.3%|
|#4|40.6%|43.5%|37.9%|
|#5|40.1%|44%|36.7%|

We see a minor decrease of overhead when the SDK is not initialized or without consent but <u>it is not significant enough to measure an impact</u>.

### Network Utilization (Uploads / Downloads)

This table includes data sent and received by Datadog SDK only.

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|n/a|U: 21.85 KB / D: 1.68 KB|U: 0 KB / D: 0 KB|
|#2|n/a|U: 21.98 KB / D: 1.68 KB|U: 0 KB / D: 0 KB|
|#3|n/a|U: 21.71 KB / D: 1.68 KB|U: 0 KB / D: 0 KB|
|#4|n/a|U: 21.86 KB / D: 1.68 KB|U: 0 KB / D: 0 KB|
|#5|n/a|U: 22.02 KB / D: 1.68 KB|U: 0 KB / D: 0 KB|

<u>No increase in energy use due to networking</u>.

### Disk Usage (Reads / Writes)

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|R: 31.4 MB / W: 44.4 MB|R: 54.5 MB / W: 48.5 MB|R: 65.9 MB / W: 49.9 MB|
|#2|R: 27.9 MB / W: 44.2 MB|R: 35 MB / W: 48.6 MB|R: 26.3 MB / W: 47.4 MB|
|#3|R: 33.5 MB / W: 40.9 MB|R: 35.5 MB / W: 49.2 MB|R: 31.9 MB / W: 44.4 MB|
|#4|R: 32.5 MB / W: 43.1 MB|R: 30.6 MB / W: 45.4 MB|R: 34.5 MB / W: 43.1 MB|
|#5|R: 29.4 MB / W: 43.9 MB|R: 33.1 MB / W: 45.8 MB|R: 32.2 MB MB / W: 50.5 MB|

<u>No significant impact on disk usage</u>.

### Application Launch Time (cold start in seconds)

The application launch time is the time interval between the application process start and the [UIApplicationDidBecomeActiveNotification](https://developer.apple.com/documentation/uikit/uiapplicationdidbecomeactivenotification).

|Run|SDK not initialized|Consent granted|Consent not granted|
|--- |--- |--- |--- |
|#1|0.718|0.764|0.410|
|#2|0.696|0.483|0.388|
|#3|1.317|1.255|1.222|
|#4|0.607|0.413|0.536|
|#5|1.132|0.331|0.920|

<u>No significant difference in application launch time</u>.

### Bundle Size

||without Datadog SDK|with Datadog SDK|
|--- |--- |--- |
|Size of the `.ipa` file|22.2 MB|23.6 MB|

## Appendix

**Test scenario**:

The test scenario was designed to simulate typical app usage (browsing reddits, user profiles and their comments). To eliminate external factors and noise (like another process being woken up or the app executing slightly different logic) the scenario was run multiple times:

- 5 times for each of 3 configurations to record performance data with Xcode Debug Navigator.

- 5 times for “SDK initialized and data collection enabled” to record network traffic with Charles Proxy.

- 1 time for “SDK not initialized” and “data collection disabled” scenarios to record network traffic.

Each test run took exactly `2min 30s`:

1.  Install the app on the device.

2.  Launch the app, dismiss onboarding screen (_“Explore without account”_), and push notifications alert.

3.  `20s`: Wait.

4.  `30s`: Refresh reddits list on the Subreddits screen → go to “Art” reddit → load Top items for past month → go to 3rd reddit → load Top comments → go to the first user profile → load their Comments → go back to the main screen → go to Search tab → search for “food” → enter some result from the top of the list → go back to the main screen.

5.  `20s`: Wait.

6.  `30s`: Repeat step 4 with browsing “DYI” reddit and searching for “soccer”.

7.  `50s`: Wait.

8.  Pause the app process and record measurements.

**Measurements**:

All performance results were collected using Xcode 14.3 Debug Navigator. The app process was paused `2min 30s` after launch and its state was dumped by taking screenshots of navigator sections: CPU, Memory, Energy, Disk, Network, and GPU.

Network traffic was recorded with Charles Proxy 4.6.4. The proxy was enabled before each run and disabled after `2min 30s`.

**Instrumentation:**

The SDK was initialized with basic RUM instrumentation for tracking views, actions, and resources:

```swift
Datadog.initialize(
    appContext: .init(),
    trackingConsent: trackingConsent,
    configuration: .builderUsing(
        rumApplicationID: applicationID,
        clientToken: clientToken,
        environment: "benchmark"
    )
    .enableLogging(true)
    .enableRUM(true)
    .enableTracing(true)
    .trackUIKitRUMViews()
    .trackUIKitRUMActions()
    .trackURLSession()
    .set(rumSessionsSamplingRate: 100)
    .set(loggingSamplingRate: 100)
    .set(loggingSamplingRate: 100)
    .set(customRUMEndpoint: URL(string: "http://172.16.10.112:8000/rum")!)
    .set(customLogsEndpoint: URL(string: "http://172.16.10.112:8000/logs")!)
    .build()
)

Datadog.verbosityLevel = .debug

DatadogTracer.initialize(
    configuration: .init(customIntakeURL: URL(string: "http://172.16.10.112:8000/span")!)
)

logger = DatadogLogger.builder.build()
```

The `DDURLSessionDelegate` was installed in session instances created in: `ImgurController`, `AuthenticationController`, `DataRequest` and `RedditUserRequest`.
