# Session Replay Performances

# Methodology

The following measures were collected by a [Benchmark Application](https://github.com/DataDog/dd-sdk-ios/tree/develop/BenchmarkTests) with Datadog iOS SDK ([d41d5dd](https://github.com/DataDog/dd-sdk-ios/commit/d41d5dd2a14c1533f1384b4a9d22801c68abad71)) running in [Datadog Synthetic Testing for Mobile Application](https://docs.datadoghq.com/synthetics/mobile_app_testing/) environment.

Each scenario execute **Baseline** and **Instrumented** runs: Baseline runs without the Datadog SDK initialized while **Instrumented** runs with RUM and Session Replay enabled.
The **Overhead** metrics are computed by comparing the Baseline with Instrumented values.

# UIKit Catalog Scenario

The scenario goes through the [UIKit Catalog](https://developer.apple.com/documentation/uikit/views_and_controls/uikit_catalog_creating_and_customizing_views_and_controls) during approximately 5m 30s at each run.

The applied [configuration](https://github.com/DataDog/dd-sdk-ios/blob/d41d5dd2a14c1533f1384b4a9d22801c68abad71/BenchmarkTests/Runner/Scenarios/SessionReplay/SessionReplayScenario.swift#L23-L45) sets permissive masking.


## Synthetic Tests Runs

![graph image](images/3192494145857827.png)

## Memory Usage

![graph image](images/8737857257350907.png)

## Memory Overhead

![graph image](images/8905638968308716.png)

## CPU Load

![graph image](images/8116457404167432.png)


## CPU Overhead

![graph image](images/06351283027023702.png)


# SwiftUI Catalog Scenario

The scenario goes through the [SwiftUI Catalog](https://github.com/barbaramartina/swiftuicatalog) during approximately 4m 45s at each run.

The applied [configuration](https://github.com/DataDog/dd-sdk-ios/blob/d41d5dd2a14c1533f1384b4a9d22801c68abad71/BenchmarkTests/Runner/Scenarios/SessionReplay/SessionReplaySwiftUIScenario.swift#L23-L44) sets permissive masking.


## Synthetic Tests Runs

![graph image](images/8871395869966259.png)

## Memory Usage

![graph image](images/385773249719056.png)

## Memory Overhead

![graph image](images/26979705914111296.png)
> We see no significant memory overhead when recording SwiftUI.


## CPU Load

![graph image](images/2095333423650021.png)


## CPU Overhead

![graph image](images/6851476281144375.png)
