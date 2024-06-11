# Unreleased

- [IMPROVEMENT] Bump `IPHONEOS_DEPLOYMENT_TARGET` and `TVOS_DEPLOYMENT_TARGET` from 11 to 12. See [#1891][]

# 2.12.0 / 03-06-2024

- [IMPROVEMENT] Crash errors now include up-to-date global RUM attributes. See [#1834][]
- [FEATURE] `DatadogTrace` now supports OpenTelemetry. See [#1828][]
- [FIX] Fix crash on accessing request.allHTTPHeaderFields. See [#1843][]
- [FEATURE] Support for trace context injection configuration to allow selective injection. See [#1835][]
- [FEATURE] `DatadogWebViewTracking` is now available for Obj-C. See [#1854][]
- [FEATURE] RUM "stop session", "get session ID" and "evaluate feature flag" APIs are now available for Obj-C. See [#1853][]

# 2.11.0 / 08-05-2024

- [FEATURE] `DatadogTrace` now supports head-based sampling. See [#1794][]
- [FEATURE] Support WebView recording in Session Replay. See [#1776][]
- [IMPROVEMENT] Add `isInitialized` and `stopInstance` methods to ObjC API. See [#1800][]
- [IMPROVEMENT] Add `addUserExtraInfo` method to ObjC API. See [#1799][]
- [FIX] Add background upload capability to extensions. See [#1803][]
- [IMPROVEMENT] Start sending data immediately after SDK is initialized. See [#1798][]
- [IMPROVEMENT] Make the SDK compile on macOS 12+. See [#1711][]

# 2.10.1 / 02-05-2024

- [FIX] Use trace and span id as decimal. See [#1807][]

# 2.10.0 / 23-04-2024

- [IMPROVEMENT] Add image duplicate detection between sessions. See [#1747][]
- [FEATURE] Add support for 128 bit trace IDs. See [#1721][]
- [FEATURE] Fatal App Hangs are tracked in RUM. See [#1763][]
- [FIX] Avoid name collision with Required Reason APIs. See [#1774][]

# 2.9.0 / 11-04-2024

- [FEATURE] Call RUM's `errorEventMapper` for crashes. See [#1742][]
- [FEATURE] Support calling log event mapper for crashes. See [#1741][]
- [FIX] Fix crash in `NetworkInstrumentationFeature`. See [#1767][]
- [FIX] Remove modulemap. See [#1746][]
- [FIX] Expose objc interfaces in Session Replay module. See [#1697][]

# 2.8.1 / 20-03-2024

- [FEATURE] App Hangs are tracked as RUM errors. See [#1685][]
- [FIX] Propagate parent span in distributing tracing. See [#1627][]
- [IMPROVEMENT] Add Device's Brand, Name, and Model in LogEvent. See [#1672][] (Thanks [@aldoKelvianto][])
- [FEATURE] Improved image recording in Session Replay. See [#1592][]
- [FEATURE] Allow custom error fingerprinting on logs with a special attribute. See [#1722][]
- [FEATURE] Add global log attributes. See [#1707][]
- [FEATURE] Privacy Manifest data usage description. See [#1724][]
- [FIX] Pass through data when network request completes. See [#1696][]

# 2.7.1 / 12-02-2024

- [FIX] Privacy Report missing properties. See [#1656][]
- [FIX] Privacy manifest collision in static framework. See [#1666][]

# 2.7.0 / 25-01-2024

- [FIX] RUM session not being linked to spans. See [#1615][]
- [FIX] `URLSessionTask.resume()` swizzling in iOS 13 and 12. See [#1637][]
- [FEATURE] Allow stopping a core instance. See [#1541][]
- [FEATURE] Link crashes sent as Log events to RUM session. See [#1645][]
- [IMPROVEMENT] Add extra HTTP codes to the list of retryable status codes. See [#1639][]
- [FEATURE] Add privacy manifest to `DatadogCore`. See [#1644][]

# 2.6.0 / 09-01-2024
- [FEATURE] Add `currentSessionID(completion:)` accessor to access the current session ID.
- [FEATURE] Add `BatchProcessingLevel` configuration allowing to process more batches within single read/upload cycle. See [#1531][]
- [FIX] Use `currentRequest` instead `originalRequest` for URLSession request interception. See [#1609][]
- [FIX] Remove weak `UIViewController` references. See [#1597][]

# 2.5.1 / 20-12-2023

- [BUGFIX] Fix `view.time_spent` in RUM view events. See [#1596][]

- [FEATURE] Start RUM session on RUM init. See [#1594][]

# 2.5.0 / 08-11-2023

- [BUGFIX] Optimize Session Replay diffing algorithm. See [#1524][]
- [FEATURE] Add network instrumentation for async/await URLSession APIs. See [#1394][]
- [FEATURE] Change default tracing headers for first party hosts to use both Datadog headers and W3C `tracecontext` headers. See [#1529][]
- [FEATURE] Add tracestate headers when using W3C tracecontext. See [#1536][]
- [BUGFIX] Fix RUM ViewController leaks. See [#1533][]

# 2.4.0 / 18-10-2023

- [FEATURE] WebView Log events can be now sampled. See [#1515][]
- [BUGFIX] WebView RUM events are now dropped if mobile RUM session is not sampled. See [#1502][]
- [BUGFIX] Fix `os.name` in Log events. See [#1493][]

# 2.3.0 / 02-10-2023

- [IMPROVEMENT] Add UIBackgroundTask for uploading jobs. See [#1412][]
- [IMPROVEMENT] Report Build Number in Logs and RUM. See [#1465][]
- [BUGFIX] Fix wrong `view.name` reported in RUM crashes. See [#1488][]
- [BUGFIX] Fix RUM sessions state propagation in Crash Reporting. See [#1498][]

# 2.2.1 / 13-09-2023

- [BUGFIX] Add default RUM views and actions predicates to DatadogObjc . See [#1464][].

# 2.2.0 / 12-09-2023

- [IMPROVEMENT] Enable cross-platform SDKs to change app `version`. See [#1447][]
- [IMPROVEMENT] Enable cross-platform SDKs to edit more of telemetry configuration. See [#1456][]

# 2.1.2 / 29-08-2023

- [BUGFIX] Do not embed DatadogInternal while building Trace and RUM xcframeworks. See [#1444][].

# 2.1.1 / 22-08-2023

- [BUGFIX] `DatadogObjc` not fully available in `2.1.0`. See [#1428][].

# 2.1.0 / 18-08-2023

- [BUGFIX] Manual trace injection APIs are not available in DatadogTrace. See [#1415][].
- [BUGFIX] Fix session replay uploads to AP1 site. See [#1418][].
- [BUGFIX] Allow instantiating custom instance of the SDK after default one. See [#1413][].
- [BUGFIX] Do not propagate attributes from Errors and LongTasks to Views.
- [IMPROVEMENT] Upgrade to PLCrashReporter 1.11.1.
- [FEATURE] Report session sample rate to the backend with RUM events. See [#1410][]
- [IMPROVEMENT] Expose Session Replay to Objective-C. see [#1419][]

# 2.0.0 / 31-07-2023

Release `2.0` introduces breaking changes. Follow the [Migration Guide](MIGRATION.md) to upgrade from `1.x` versions.

- [FEATURE] Session Replay.
- [FEATURE] Support multiple SDK instances.
- [IMPROVEMENT] All relevant products (RUM, Trace, Logs, etc.) are now extracted into different modules.
- [BUGFIX] Module stability: fix name collision.

# 1.22.0 / 21-07-2023
- [BUGFIX] Fix APM local spans not correlating with RUM views. See [#1355][]
- [IMPROVEMENT] Reduce number of view updates by filtering events from payload. See [#1328][]

# 1.21.0 / 27-06-2023
- [BUGFIX] Fix TracingUUID string format. See [#1311][] (Thanks [@changm4n][])
- [BUGFIX] Rename _Datadog_Private to DatadogPrivate. See [#1331] (Thanks [@alexfanatics][])
- [IMPROVEMENT] Add context to crash when there's an active view. See [#1315][]


# 1.20.0 / 01-06-2023
- [BUGFIX] Use targetTimestamp as reference to calculate FPS for variable refresh rate displays. See [#1272][]

# 1.19.0 / 26-04-2023
- [BUGFIX] Fix view attributes override by action attributes. See [#1250][]
- [IMPROVEMENT] Add Tracer sampling rate. See [#1259][]
- [BUGFIX] Fix RUM context not being attached to log when no user action exists. See [#1264][]

# 1.18.0 / 19-04-2023
- [IMPROVEMENT] Add start reason to the session. See [#1247][]
- [IMPROVEMENT] Add ability to stop the session. See [#1219][]

# 1.17.0 / 23-03-2023
- [BUGFIX] Fix crash in `VitalInfoSampler`. See [#1216][] (Thanks [@cltnschlosser][])
- [IMPROVEMENT] Fix Xcode analysis warning. See [#1220][]
- [BUGFIX] Send crashes to both RUM and Logs. See [#1209][]

# 1.16.0 / 02-03-2023
- [IMPROVEMENT] Always create an ApplicationLaunch view on session initialization. See [#1160][]
- [BUGFIX] Remove the data race caused by sampling on the RUM thread. See [#1177][] (Thanks [@cltnschlosser][])
- [BUGFIX] Add ability to adjust configuration telemetry sampling rate. See [#1188][]

# 1.15.0 / 23-01-2023

- [BUGFIX] Fix 'Could not allocate memory' after corrupted TLV. See [#1089][] (Thanks [@cltnschlosser][])
- [BUGFIX] Fix error count on the view update event following a crash. See [#1145][]

# 1.14.0 / 20-12-2022

- [IMPROVEMENT] Add a method for sending error attributes on logs as strings. See [#1051][].
- [IMPROVEMENT] Add manual Open Telemetry b3 headers injection. See [#1057][]
- [IMPROVEMENT] Add automatic Open Telemetry b3 headers injection. See [#1061][]
- [IMPROVEMENT] Add manual and automatic W3C traceparent header injection. See [#1071][]

# 1.13.0 / 08-11-2022

- [IMPROVEMENT] Improve console logs when using `DDNoopRUMMonitor`. See [#1007][] (Thanks [@dfed][])
- [IMPROVEMENT] Add public API to control tracking of frustrations signals. See [#1013][]
- [IMPROVEMENT] Send trace sample rate (`dd.rulePsr`) for APM's traffic ingestion control page. See [#1029][]
- [IMPROVEMENT] Add a method to add user info properties. See [#1031][]
- [BUGFIX] Fix vitals default presets. See [#1043][]
- [IMPROVEMENT] Add logging sampling. See [#1045][]


# 1.12.1 / 18-10-2022

- [IMPROVEMENT] Upgrade to PLCrashReporter 1.11.0 to fix Xcode 14 support.

# 1.12.0 / 16-09-2022

- [BUGFIX] Fix manual User Action dropped if a new view start. See [#997][]
- [IMPROVEMENT] Enable cross-platform SDKs to change app `version`. See [#973][]
- [IMPROVEMENT] Add internal APIs for cross-platform SDKs. See [#964][]
- [IMPROVEMENT] Add mobile vitals frequency configuration. See [#876][]
- [IMPROVEMENT] Include the exact model information in RUM `device.model`. See [#888][]
- [FEATURE] Allow filtering outgoing logs with a status threshold. See [#867][]
- [BUGFIX] Fix compilation issue in SwiftUI Previews. See [#949][]
- [IMPROVEMENT] Expose server date provider for custom clock synchronization. See [#950][]

# 1.11.1 / 20-06-2022

### Changes

- [BUGFIX] Fix Mac Catalyst builds compatibility. See [#894][]

# 1.11.0 / 13-06-2022

### Changes

- [BUGFIX] Fix rare problem with bringing up the "Local Network Permission" alert. See [#830][]
- [BUGFIX] Fix RUM event `source`. See [#832][]
- [BUGFIX] Stop reporting pre-warmed application launch time. See [#789][]
- [BUGFIX] Allow log event dropping. See [#795][]
- [FEATURE] Integration with CI Visibility Tests. See[#761][]
- [FEATURE] Add tvOS Support. See [#793][]
- [FEATURE] Add data encryption interface on-disk data storage. See [#797][]
- [IMPROVEMENT] Allow manually tracked resources in RUM Sessions to detect first party hosts. See [#837][]
- [IMPROVEMENT] Add tracing sampling rate. See [#851][]
- [IMPROVEMENT] Crash Reporting: Filter out unrecognized trailing `???` stack frame in `error.stack`. See [#794][]
- [IMPROVEMENT] Reduce the number of intermediate view events sent in RUM payloads. See [#815][]
- [IMPROVEMENT] Allow manually tracked resources in RUM Sessions to detect first party hosts. See [#837][]
- [IMPROVEMENT] Add tracing sampling rate. See [#851][]
- [BUGFIX] Fix rare problem with bringing up the "Local Network Permission" alert. See [#830][]
- [BUGFIX] Fix RUM event `source`. See [#832][]
- [FEATURE] Integration with CI Visibility Tests. See[#761][]
- [FEATURE] Add tvOS Support. See [#793][]
- [FEATURE] Add data encryption interface on-disk data storage. See [#797][]
- [BUGFIX] Stop reporting pre-warmed application launch time. See [#789][]
- [BUGFIX] Allow log event dropping. See [#795][]
- [IMPROVEMENT] Crash Reporting: Filter out unrecognized trailing `???` stack frame in `error.stack`. See [#794][]
- [IMPROVEMENT] Reduce the number of intermediate view events sent in RUM payloads. See [#815][]

# 1.10.0 / 04-12-2022

### Changes

- [FEATURE] Web-view tracking. See [#729][]
- [BUGFIX] Strip query parameters from span resource. See [#728][]

# 1.9.0 / 01-26-2022

### Changes

- [BUGFIX] Report binary image with no UUID. See [#724][]
- [FEATURE] Add Application Launch events tracking. See [#699][]
- [FEATURE] Set `PLCrashReporter` custom path. See [#692][]
- [FEATURE] `SwiftUI` Instrumentation. See [#676][]
- [IMPROVEMENT] Embed Kronos. See [#708][]
- [IMPROVEMENT] Add `@service` attribute to all RUM events. See [#725][]
- [IMPROVEMENT] Adds support for flutter error source. See [#715][]
- [IMPROVEMENT] Add crash reporting console logs. See [#712][]
- [IMPROVEMENT] Keep view active until all resources are consumed. See [#702][]
- [IMPROVEMENT] Allow passing in a type for errors sent with a message. See [#680][] (Thanks [@AvdLee][])
- [IMPROVEMENT] Add config overrides for debug launch arguments. See [#679][]

# 1.8.0 / 11-23-2021

### Changes

- [BUGFIX] Fix rare crash in `CarrierInfoProvider`. See [#627][] [#623][], [#619][] (Thanks [@safa-ads][], [@matcartmill][])
- [BUGFIX] Crash Reporting: Fix issue with some truncated stack traces not being displayed. See [#641][]
- [BUGFIX] Fix reading SDK attributes in Objective-C. See [#654][]
- [FEATURE] RUM: Track slow UI renders with RUM Long Tasks. See [#567][]
- [FEATURE] RUM: Add API to notify RUM session start: `.onRUMSessionStart(_: (String, Bool) -> Void)`. See [#590][]
- [FEATURE] Logs: Add logs scrubbing API: `.setLogEventMapper(_: (LogEvent) -> LogEvent)`. See [#640][]
- [FEATURE] Add `Datadog.isInitialized` API. See [#566][]
- [FEATURE] Add API for clearing out all SDK data: `Datadog.clearAllData()`. See [#644][]
- [FEATURE] Add support for `us5` site. See [#576][]
- [FEATURE] Support `URLSession` proxy configuration with `.connectionProxyDictionary`. See [#582][]
- [IMPROVEMENT] Compress HTTP body in SDK uploads. See [#626][]
- [IMPROVEMENT] Change type of `.xhr` RUM Resources to `.native`. See [#605][]
- [IMPROVEMENT] Link logs and traces to RUM Actions. See [#615][]
- [IMPROVEMENT] Crash Reporting: Fix symbolication issue for iOS Simulator crashes. See [#563][]
- [IMPROVEMENT] Fix various typos in docs. See [#569][] (Thanks [@michalsrutek][])
- [IMPROVEMENT] Use Intake API V2 for SDK data uploads. See [#562][]

# 1.7.2 / 11-8-2021

### Changes

- [BUGFIX] Fix iOS 15 crash related to `ProcessInfo.isLowPowerModeEnabled`. See [#609][] [#655][] (Thanks [@pingd][])

# 1.7.1 / 10-4-2021

### Changes

- [BUGFIX] Fix iOS 15 crash in `MobileDevice.swift`. See [#609][] [#613][] (Thanks [@arnauddorgans][], [@earltedly][])
- [BUGFIX] RUM: Fix bug with "Refresh Rate" Mobile Vital reporting very low values. [#608][]

# 1.7.0 / 09-27-2021

### Changes

- [BUGFIX] RUM: Fix `DDRUMView` API visibility for Objective-C. See [#583][]
- [FEATURE] Crash Reporting: Add `DatadogCrashReporting`
- [FEATURE] RUM: Add Mobile Vitals. See [#493][] [#514][] [#522][] [#495][]
- [FEATURE] RUM: Add option for renaming instrumented actions. See [#539][]
- [FEATURE] RUM: Add option for tracking events when app is in background. See [#504][] [#537][]
- [FEATURE] Add support for `us3` site. See [#523][]
- [IMPROVEMENT] RUM: Improve RUM <> APM integration. See [#524][] [#575][] [#531][] (Thanks [@jracollins][], [@marcusway][])
- [IMPROVEMENT] RUM: Improve naming for views started with `key:`. See [#534][]
- [IMPROVEMENT] RUM: Improve actions instrumentation. See [#509][] [#545][] [#547][]
- [IMPROVEMENT] RUM: Sanitize custom timings for views. See [#525][]
- [IMPROVEMENT] Do not retry uploading events if Client Token is invalid. See [#535][]

# 1.6.0 / 06-09-2021

### Changes

- [BUGFIX] Trace: Fix `[configuration trackUIKitRUMViews]` not working properly in Obj-c. See [#419][]
- [BUGFIX] Trace: Make `tracePropagationHTTPHeaders` available in Obj-c. See [#421][] (Thanks [@ben-yolabs][])
- [BUGFIX] RUM: Fix RUM Views auto-instrumentation issue on iOS 11. See [#474][]
- [FEATURE] RUM: Support adding custom attributes for auto-instrumented RUM Resources. See [#473][]
- [FEATURE] Trace: Add scrubbing APIs for redacting auto-instrumented spans. See [#481][]
- [IMPROVEMENT] RUM: Add "VIEW NAME" attribute to RUM Views. See [#318][]
- [IMPROVEMENT] RUM: Views cannot be now dropped using view event mapper. See [#415][]
- [IMPROVEMENT] RUM: Improve presentation of errors sent with `Logger`. See [#423][]
- [IMPROVEMENT] Trace: Improve presentation of errors sent with `span.log()`. See [#431][]
- [IMPROVEMENT] Add support for extra user attributes in Obj-c. See [#444][]
- [IMPROVEMENT] Trace: Add `foreground_duration` and `is_background` information to network spans. See [#436][]
- [IMPROVEMENT] RUM: Views will now automatically stop when the app leaves foreground. See [#479][]
- [IMPROVEMENT] `DDURLSessionDelegate` can now be initialized before starting SDK. See [#483][]

# 1.5.2 / 04-13-2021

### Changes

- [BUGFIX] Add missing RUM Resource APIs to RUM for Objc. See [#447][] (Thanks [@sdejesusF][])
- [BUGFIX] Fix eventual `swiftlint` error during `carthage` builds. See [#450][]
- [IMPROVEMENT] Improve cocoapods installation by not requiring `!use_frameworks`. See [#451][]

# 1.5.1 / 03-11-2021

### Changes

- [BUGFIX] Carthage XCFrameworks support. See [#439][]

# 1.5.0 / 03-04-2021

### Changes

- [BUGFIX] Fix baggage items propagation issue for `Span`. See [#365][] (Thanks [@philtre][])
- [FEATURE] Add set of scrubbing APIs for redacting and dropping particular RUM Events. See [#367][]
- [FEATURE] Add support for GDPR compliance with new `Datadog.set(trackingConsent:)` API. See [#335][]
- [FEATURE] Add `Global.rum.addTiming(name:)` API for marking custom tming events in RUM Views. See [#323][]
- [FEATURE] Add support for Alamofire networking with `DatadogAlamofireExtension`. See [#340][]
- [FEATURE] Add configuration of data upload frequency and paylaod size with `.set(batchSize:)` and `.set(uploadFrequency:)` APIs. See [#358][]
- [FEATURE] Add convenient `.setError(_:)` API for setting `Error` on `Span`. See [#390][]
- [IMPROVEMENT] Improve `DATE` accurracy (with NTP time sync) for all data send from the SDK. See [#327][]
- [IMPROVEMENT] Improve App Launch Time metric accurracy. See [#381][]

# 1.4.1 / 01-18-2021

### Changes

- [BUGFIX] Fix app extension compilation issue for `UIApplication.shared` symbol. See [#370][] (Thanks [@SimpleApp][])

# 1.4.0 / 12-14-2020

### Changes

- [BUGFIX] Fix crash when `serviceName` contains space characters. See [#317][] (Thanks [@philtre][])
- [BUGFIX] Fix issue with data uploads when battery status is `.unknown`. See [#320][]
- [BUGFIX] Fix compilation issue for Mac Catalyst. See [#277][] (Thanks [@Hengyu][])
- [FEATURE] RUM: Add RUM monitoring feature (manual and auto instrumentation)
- [FEATURE] Add single `.set(endpoint:)` API to configure all Datadog endpoints. See [#322][]
- [FEATURE] Add support for GovCloud endpoints. See [#235][]
- [FEATURE] Add support for extra user attributes. See [#315][]
- [FEATURE] Logs: Add `error: Error` attribute to logging APIs. See [#303][] (Thanks [@sdejesusF][])
- [FEATURE] Trace: Add `span.setActive()` API for indirect referencing Spans. See [#187][]
- [FEATURE] Trace: Add `Global.sharedTracer.startRootSpan(...)` API. See [#236][]
- [IMPROVEMENT] Trace: Add auto instrumentation for `URLSessionTasks` created with no completion handler. See [#262][]
- [IMPROVEMENT] Extend allowed characters set for the `environment` value. See [#246][] (Thanks [@sdejesusF][])
- [IMPROVEMENT] Improve data upload performance. See [#249][]

# 1.3.1 / 08-14-2020

### Changes

- [BUGFIX] Fix SPM compilation issue for DatadogObjC. See [#220][] (Thanks [@TsvetelinVladimirov][])
- [BUGFIX] Fix compilation issue in Xcode 11.3.1. See [#217][] (Thanks [@provTheodoreNewell][])

# 1.3.0 / 08-03-2020

### Changes

- [FEATURE] Trace: Add tracing feature following the Open Tracing spec

# 1.2.4 / 07-17-2020

### Changes

- [BUGFIX] Logs: Fix out-of-memory crash on intensive logging. See [#185][] (Thanks [@hyling][])

# 1.2.3 / 07-15-2020

### Changes

- [BUGFIX] Logs: Fix memory leaks in logs upload. See [#180][] (Thanks [@hyling][])
- [BUGFIX] Fix App Store Connect validation issue for `DatadogObjC`. See [#182][] (Thanks [@hyling][])

# 1.2.2 / 06-12-2020

### Changes

- [BUGFIX] Logs: Fix occasional logs malformation. See [#133][]

# 1.2.1 / 06-09-2020

### Changes

- [BUGFIX] Fix `ISO8601DateFormatter` crash on iOS 11.0 and 11.1. See [#129][] (Thanks [@lgaches][], [@Britton-Earnin][])

# 1.2.0 / 05-22-2020

### Changes

- [BUGFIX] Logs: Fixed family of `NWPathMonitor` crashes. See [#110][] (Thanks [@LeffelMania][], [@00FA9A][], [@jegnux][])
- [FEATURE] Logs: Change default `serviceName` to app bundle identifier. See [#102][]
- [IMPROVEMENT] Logs: Add milliseconds precision. See [#96][] (Thanks [@flobories][])
- [IMPROVEMENT] Logs: Deliver logs faster in app extensions. See [#84][] (Thanks [@lmramirez][])
- [OTHER] Logs: Change default `source` to `"ios"`. See [#111][]
- [OTHER] Link SDK as dynamic framework in SPM. See [#82][]

# 1.1.0 / 04-21-2020

### Changes

- [BUGFIX] Fix "Missing required module 'Datadog_Private'" Carthage error. See [#80][]
- [IMPROVEMENT] Logs: Sync logs time with server. See [#65][]

# 1.0.2 / 04-08-2020

### Changes

- [BUGFIX] Fix "'module.modulemap' should be inside the 'include' directory" Carthage error. See [#73][] (Thanks [@joeydong][])

# 1.0.1 / 04-07-2020

### Changes

- [BUGFIX] Fix "out of memory" crash. See [#64][] (Thanks [@lmramirez][])

# 1.0.0 / 03-31-2020

### Changes

- [FEATURE] Logs: Add logging feature

<!--- The following link definition list is generated by PimpMyChangelog --->

[#64]: https://github.com/DataDog/dd-sdk-ios/issues/64
[#65]: https://github.com/DataDog/dd-sdk-ios/issues/65
[#73]: https://github.com/DataDog/dd-sdk-ios/issues/73
[#80]: https://github.com/DataDog/dd-sdk-ios/issues/80
[#82]: https://github.com/DataDog/dd-sdk-ios/issues/82
[#84]: https://github.com/DataDog/dd-sdk-ios/issues/84
[#96]: https://github.com/DataDog/dd-sdk-ios/issues/96
[#102]: https://github.com/DataDog/dd-sdk-ios/issues/102
[#110]: https://github.com/DataDog/dd-sdk-ios/issues/110
[#111]: https://github.com/DataDog/dd-sdk-ios/issues/111
[#129]: https://github.com/DataDog/dd-sdk-ios/issues/129
[#133]: https://github.com/DataDog/dd-sdk-ios/issues/133
[#180]: https://github.com/DataDog/dd-sdk-ios/issues/180
[#182]: https://github.com/DataDog/dd-sdk-ios/issues/182
[#185]: https://github.com/DataDog/dd-sdk-ios/issues/185
[#187]: https://github.com/DataDog/dd-sdk-ios/issues/187
[#217]: https://github.com/DataDog/dd-sdk-ios/issues/217
[#220]: https://github.com/DataDog/dd-sdk-ios/issues/220
[#235]: https://github.com/DataDog/dd-sdk-ios/issues/235
[#236]: https://github.com/DataDog/dd-sdk-ios/issues/236
[#246]: https://github.com/DataDog/dd-sdk-ios/issues/246
[#249]: https://github.com/DataDog/dd-sdk-ios/issues/249
[#262]: https://github.com/DataDog/dd-sdk-ios/issues/262
[#277]: https://github.com/DataDog/dd-sdk-ios/issues/277
[#303]: https://github.com/DataDog/dd-sdk-ios/issues/303
[#315]: https://github.com/DataDog/dd-sdk-ios/issues/315
[#317]: https://github.com/DataDog/dd-sdk-ios/issues/317
[#318]: https://github.com/DataDog/dd-sdk-ios/issues/318
[#320]: https://github.com/DataDog/dd-sdk-ios/issues/320
[#322]: https://github.com/DataDog/dd-sdk-ios/issues/322
[#323]: https://github.com/DataDog/dd-sdk-ios/issues/323
[#327]: https://github.com/DataDog/dd-sdk-ios/issues/327
[#335]: https://github.com/DataDog/dd-sdk-ios/issues/335
[#340]: https://github.com/DataDog/dd-sdk-ios/issues/340
[#358]: https://github.com/DataDog/dd-sdk-ios/issues/358
[#365]: https://github.com/DataDog/dd-sdk-ios/issues/365
[#367]: https://github.com/DataDog/dd-sdk-ios/issues/367
[#370]: https://github.com/DataDog/dd-sdk-ios/issues/370
[#381]: https://github.com/DataDog/dd-sdk-ios/issues/381
[#390]: https://github.com/DataDog/dd-sdk-ios/issues/390
[#415]: https://github.com/DataDog/dd-sdk-ios/issues/415
[#419]: https://github.com/DataDog/dd-sdk-ios/issues/419
[#421]: https://github.com/DataDog/dd-sdk-ios/issues/421
[#423]: https://github.com/DataDog/dd-sdk-ios/issues/423
[#431]: https://github.com/DataDog/dd-sdk-ios/issues/431
[#436]: https://github.com/DataDog/dd-sdk-ios/issues/436
[#439]: https://github.com/DataDog/dd-sdk-ios/issues/439
[#444]: https://github.com/DataDog/dd-sdk-ios/issues/444
[#447]: https://github.com/DataDog/dd-sdk-ios/issues/447
[#450]: https://github.com/DataDog/dd-sdk-ios/issues/450
[#451]: https://github.com/DataDog/dd-sdk-ios/issues/451
[#473]: https://github.com/DataDog/dd-sdk-ios/issues/473
[#474]: https://github.com/DataDog/dd-sdk-ios/issues/474
[#479]: https://github.com/DataDog/dd-sdk-ios/issues/479
[#481]: https://github.com/DataDog/dd-sdk-ios/issues/481
[#483]: https://github.com/DataDog/dd-sdk-ios/issues/483
[#493]: https://github.com/DataDog/dd-sdk-ios/issues/493
[#495]: https://github.com/DataDog/dd-sdk-ios/issues/495
[#504]: https://github.com/DataDog/dd-sdk-ios/issues/504
[#509]: https://github.com/DataDog/dd-sdk-ios/issues/509
[#514]: https://github.com/DataDog/dd-sdk-ios/issues/514
[#522]: https://github.com/DataDog/dd-sdk-ios/issues/522
[#523]: https://github.com/DataDog/dd-sdk-ios/issues/523
[#524]: https://github.com/DataDog/dd-sdk-ios/issues/524
[#525]: https://github.com/DataDog/dd-sdk-ios/issues/525
[#531]: https://github.com/DataDog/dd-sdk-ios/issues/531
[#534]: https://github.com/DataDog/dd-sdk-ios/issues/534
[#535]: https://github.com/DataDog/dd-sdk-ios/issues/535
[#537]: https://github.com/DataDog/dd-sdk-ios/issues/537
[#539]: https://github.com/DataDog/dd-sdk-ios/issues/539
[#545]: https://github.com/DataDog/dd-sdk-ios/issues/545
[#547]: https://github.com/DataDog/dd-sdk-ios/issues/547
[#562]: https://github.com/DataDog/dd-sdk-ios/issues/562
[#563]: https://github.com/DataDog/dd-sdk-ios/issues/563
[#566]: https://github.com/DataDog/dd-sdk-ios/issues/566
[#567]: https://github.com/DataDog/dd-sdk-ios/issues/567
[#569]: https://github.com/DataDog/dd-sdk-ios/issues/569
[#575]: https://github.com/DataDog/dd-sdk-ios/issues/575
[#576]: https://github.com/DataDog/dd-sdk-ios/issues/576
[#582]: https://github.com/DataDog/dd-sdk-ios/issues/582
[#583]: https://github.com/DataDog/dd-sdk-ios/issues/583
[#590]: https://github.com/DataDog/dd-sdk-ios/issues/590
[#605]: https://github.com/DataDog/dd-sdk-ios/issues/605
[#608]: https://github.com/DataDog/dd-sdk-ios/issues/608
[#609]: https://github.com/DataDog/dd-sdk-ios/issues/609
[#613]: https://github.com/DataDog/dd-sdk-ios/issues/613
[#615]: https://github.com/DataDog/dd-sdk-ios/issues/615
[#619]: https://github.com/DataDog/dd-sdk-ios/issues/619
[#623]: https://github.com/DataDog/dd-sdk-ios/issues/623
[#626]: https://github.com/DataDog/dd-sdk-ios/issues/626
[#627]: https://github.com/DataDog/dd-sdk-ios/issues/627
[#640]: https://github.com/DataDog/dd-sdk-ios/issues/640
[#641]: https://github.com/DataDog/dd-sdk-ios/issues/641
[#644]: https://github.com/DataDog/dd-sdk-ios/issues/644
[#654]: https://github.com/DataDog/dd-sdk-ios/issues/654
[#655]: https://github.com/DataDog/dd-sdk-ios/issues/655
[#676]: https://github.com/DataDog/dd-sdk-ios/issues/676
[#679]: https://github.com/DataDog/dd-sdk-ios/issues/679
[#680]: https://github.com/DataDog/dd-sdk-ios/issues/680
[#692]: https://github.com/DataDog/dd-sdk-ios/issues/692
[#699]: https://github.com/DataDog/dd-sdk-ios/issues/699
[#702]: https://github.com/DataDog/dd-sdk-ios/issues/702
[#708]: https://github.com/DataDog/dd-sdk-ios/issues/708
[#712]: https://github.com/DataDog/dd-sdk-ios/issues/712
[#715]: https://github.com/DataDog/dd-sdk-ios/issues/715
[#724]: https://github.com/DataDog/dd-sdk-ios/issues/724
[#725]: https://github.com/DataDog/dd-sdk-ios/issues/725
[#728]: https://github.com/DataDog/dd-sdk-ios/issues/728
[#729]: https://github.com/DataDog/dd-sdk-ios/issues/729
[#761]: https://github.com/DataDog/dd-sdk-ios/issues/761
[#789]: https://github.com/DataDog/dd-sdk-ios/issues/789
[#793]: https://github.com/DataDog/dd-sdk-ios/issues/793
[#794]: https://github.com/DataDog/dd-sdk-ios/issues/794
[#795]: https://github.com/DataDog/dd-sdk-ios/issues/795
[#797]: https://github.com/DataDog/dd-sdk-ios/issues/797
[#815]: https://github.com/DataDog/dd-sdk-ios/issues/815
[#830]: https://github.com/DataDog/dd-sdk-ios/issues/830
[#832]: https://github.com/DataDog/dd-sdk-ios/issues/832
[#837]: https://github.com/DataDog/dd-sdk-ios/issues/837
[#851]: https://github.com/DataDog/dd-sdk-ios/issues/851
[#867]: https://github.com/DataDog/dd-sdk-ios/issues/867
[#876]: https://github.com/DataDog/dd-sdk-ios/issues/876
[#888]: https://github.com/DataDog/dd-sdk-ios/issues/888
[#894]: https://github.com/DataDog/dd-sdk-ios/issues/894
[#949]: https://github.com/DataDog/dd-sdk-ios/issues/949
[#950]: https://github.com/DataDog/dd-sdk-ios/issues/950
[#964]: https://github.com/DataDog/dd-sdk-ios/issues/964
[#973]: https://github.com/DataDog/dd-sdk-ios/issues/973
[#997]: https://github.com/DataDog/dd-sdk-ios/issues/997
[#1007]: https://github.com/DataDog/dd-sdk-ios/issues/1007
[#1013]: https://github.com/DataDog/dd-sdk-ios/issues/1013
[#1029]: https://github.com/DataDog/dd-sdk-ios/issues/1029
[#1031]: https://github.com/DataDog/dd-sdk-ios/issues/1031
[#1043]: https://github.com/DataDog/dd-sdk-ios/issues/1043
[#1045]: https://github.com/DataDog/dd-sdk-ios/pull/1045
[#1051]: https://github.com/DataDog/dd-sdk-ios/pull/1051
[#1057]: https://github.com/DataDog/dd-sdk-ios/pull/1057
[#1061]: https://github.com/DataDog/dd-sdk-ios/pull/1061
[#1071]: https://github.com/DataDog/dd-sdk-ios/pull/1071
[#1089]: https://github.com/DataDog/dd-sdk-ios/pull/1089
[#1145]: https://github.com/DataDog/dd-sdk-ios/pull/1145
[#1160]: https://github.com/DataDog/dd-sdk-ios/pull/1160
[#1177]: https://github.com/DataDog/dd-sdk-ios/pull/1177
[#1188]: https://github.com/DataDog/dd-sdk-ios/pull/1188
[#1209]: https://github.com/DataDog/dd-sdk-ios/pull/1209
[#1216]: https://github.com/DataDog/dd-sdk-ios/pull/1216
[#1219]: https://github.com/DataDog/dd-sdk-ios/pull/1219
[#1220]: https://github.com/DataDog/dd-sdk-ios/pull/1220
[#1247]: https://github.com/DataDog/dd-sdk-ios/pull/1247
[#1250]: https://github.com/DataDog/dd-sdk-ios/pull/1250
[#1259]: https://github.com/DataDog/dd-sdk-ios/pull/1259
[#1264]: https://github.com/DataDog/dd-sdk-ios/pull/1264
[#1272]: https://github.com/DataDog/dd-sdk-ios/pull/1272
[#1311]: https://github.com/DataDog/dd-sdk-ios/pull/1311
[#1315]: https://github.com/DataDog/dd-sdk-ios/pull/1315
[#1331]: https://github.com/DataDog/dd-sdk-ios/pull/1331
[#1328]: https://github.com/DataDog/dd-sdk-ios/pull/1328
[#1355]: https://github.com/DataDog/dd-sdk-ios/pull/1355
[#1410]: https://github.com/DataDog/dd-sdk-ios/pull/1410
[#1412]: https://github.com/DataDog/dd-sdk-ios/pull/1412
[#1413]: https://github.com/DataDog/dd-sdk-ios/pull/1413
[#1415]: https://github.com/DataDog/dd-sdk-ios/pull/1415
[#1418]: https://github.com/DataDog/dd-sdk-ios/pull/1418
[#1419]: https://github.com/DataDog/dd-sdk-ios/pull/1419
[#1428]: https://github.com/DataDog/dd-sdk-ios/pull/1428
[#1444]: https://github.com/DataDog/dd-sdk-ios/pull/1444
[#1464]: https://github.com/DataDog/dd-sdk-ios/pull/1464
[#1412]: https://github.com/DataDog/dd-sdk-ios/pull/1412
[#1488]: https://github.com/DataDog/dd-sdk-ios/pull/1488
[#1502]: https://github.com/DataDog/dd-sdk-ios/pull/1502
[#1515]: https://github.com/DataDog/dd-sdk-ios/pull/1515
[#1465]: https://github.com/DataDog/dd-sdk-ios/pull/1465
[#1498]: https://github.com/DataDog/dd-sdk-ios/pull/1498
[#1493]: https://github.com/DataDog/dd-sdk-ios/pull/1493
[#1394]: https://github.com/DataDog/dd-sdk-ios/pull/1394
[#1524]: https://github.com/DataDog/dd-sdk-ios/pull/1524
[#1529]: https://github.com/DataDog/dd-sdk-ios/pull/1529
[#1533]: https://github.com/DataDog/dd-sdk-ios/pull/1533
[#1645]: https://github.com/DataDog/dd-sdk-ios/pull/1645
[#1594]: https://github.com/DataDog/dd-sdk-ios/pull/1594
[#1536]: https://github.com/DataDog/dd-sdk-ios/pull/1536
[#1609]: https://github.com/DataDog/dd-sdk-ios/pull/1609
[#1639]: https://github.com/DataDog/dd-sdk-ios/pull/1639
[#1615]: https://github.com/DataDog/dd-sdk-ios/pull/1615
[#1531]: https://github.com/DataDog/dd-sdk-ios/pull/1531
[#1637]: https://github.com/DataDog/dd-sdk-ios/pull/1637
[#1541]: https://github.com/DataDog/dd-sdk-ios/pull/1541
[#1592]: https://github.com/DataDog/dd-sdk-ios/pull/1592
[#1672]: https://github.com/DataDog/dd-sdk-ios/pull/1672
[#1596]: https://github.com/DataDog/dd-sdk-ios/pull/1596
[#1597]: https://github.com/DataDog/dd-sdk-ios/pull/1597
[#1627]: https://github.com/DataDog/dd-sdk-ios/pull/1627
[#1644]: https://github.com/DataDog/dd-sdk-ios/pull/1644
[#1685]: https://github.com/DataDog/dd-sdk-ios/pull/1685
[#1656]: https://github.com/DataDog/dd-sdk-ios/pull/1656
[#1666]: https://github.com/DataDog/dd-sdk-ios/pull/1666
[#1696]: https://github.com/DataDog/dd-sdk-ios/pull/1696
[#1697]: https://github.com/DataDog/dd-sdk-ios/pull/1697
[#1707]: https://github.com/DataDog/dd-sdk-ios/pull/1707
[#1711]: https://github.com/DataDog/dd-sdk-ios/pull/1711
[#1721]: https://github.com/DataDog/dd-sdk-ios/pull/1721
[#1722]: https://github.com/DataDog/dd-sdk-ios/pull/1722
[#1724]: https://github.com/DataDog/dd-sdk-ios/pull/1724
[#1741]: https://github.com/DataDog/dd-sdk-ios/pull/1741
[#1742]: https://github.com/DataDog/dd-sdk-ios/pull/1742
[#1746]: https://github.com/DataDog/dd-sdk-ios/pull/1746
[#1747]: https://github.com/DataDog/dd-sdk-ios/pull/1747
[#1794]: https://github.com/DataDog/dd-sdk-ios/pull/1794
[#1774]: https://github.com/DataDog/dd-sdk-ios/pull/1774
[#1763]: https://github.com/DataDog/dd-sdk-ios/pull/1763
[#1767]: https://github.com/DataDog/dd-sdk-ios/pull/1767
[#1843]: https://github.com/DataDog/dd-sdk-ios/pull/1843
[#1798]: https://github.com/DataDog/dd-sdk-ios/pull/1798
[#1891]: https://github.com/DataDog/dd-sdk-ios/pull/1891
[#1776]: https://github.com/DataDog/dd-sdk-ios/pull/1776
[#1834]: https://github.com/DataDog/dd-sdk-ios/pull/1834
[#1721]: https://github.com/DataDog/dd-sdk-ios/pull/1721
[#1803]: https://github.com/DataDog/dd-sdk-ios/pull/1803
[#1853]: https://github.com/DataDog/dd-sdk-ios/pull/1853
[#1807]: https://github.com/DataDog/dd-sdk-ios/pull/1807
[#1854]: https://github.com/DataDog/dd-sdk-ios/pull/1854
[#1828]: https://github.com/DataDog/dd-sdk-ios/pull/1828
[#1835]: https://github.com/DataDog/dd-sdk-ios/pull/1835
[@00fa9a]: https://github.com/00FA9A
[@britton-earnin]: https://github.com/Britton-Earnin
[@hengyu]: https://github.com/Hengyu
[@leffelmania]: https://github.com/LeffelMania
[@simpleapp]: https://github.com/SimpleApp
[@tsvetelinvladimirov]: https://github.com/TsvetelinVladimirov
[@arnauddorgans]: https://github.com/arnauddorgans
[@ben-yolabs]: https://github.com/ben-yolabs
[@earltedly]: https://github.com/earltedly
[@flobories]: https://github.com/flobories
[@hyling]: https://github.com/hyling
[@jegnux]: https://github.com/jegnux
[@joeydong]: https://github.com/joeydong
[@jracollins]: https://github.com/jracollins
[@lgaches]: https://github.com/lgaches
[@lmramirez]: https://github.com/lmramirez
[@marcusway]: https://github.com/marcusway
[@aldoKelvianto]: https://github.com/aldoKelvianto
[@matcartmill]: https://github.com/matcartmill
[@michalsrutek]: https://github.com/michalsrutek
[@philtre]: https://github.com/philtre
[@pingd]: https://github.com/pingd
[@provtheodorenewell]: https://github.com/provTheodoreNewell
[@safa-ads]: https://github.com/safa-ads
[@sdejesusf]: https://github.com/sdejesusF
[@avdlee]: https://github.com/AvdLee
[@dfed]: https://github.com/dfed
[@cltnschlosser]: https://github.com/cltnschlosser
[@alexfanatics]: https://github.com/alexfanatics
[@changm4n]: https://github.com/changm4n