# 1.3.1 / 08-14-2020

### Changes

* [BUGFIX] Fix SPM compilation issue for DatadogObjC. See #220 (Thanks @TsvetelinVladimirov)
* [BUGFIX] Fix compilation issue in Xcode 11.3.1. See #217 (Thanks @provTheodoreNewell)

# 1.3.0 / 08-03-2020

### Changes

* [FEATURE] Trace: Add tracing feature following the Open Tracing spec

# 1.2.4 / 07-17-2020

### Changes

* [BUGFIX] Logs: Fix out-of-memory crash on intensive logging. See #185 (Thanks @hyling)

# 1.2.3 / 07-15-2020

### Changes

* [BUGFIX] Logs: Fix memory leaks in logs upload. See #180 (Thanks @hyling)
* [BUGFIX] Fix App Store Connect validation issue for `DatadogObjC`. See #182 (Thanks @hyling)

# 1.2.2 / 06-12-2020

### Changes

* [BUGFIX] Logs: Fix occasional logs malformation. See #133

# 1.2.1 / 06-09-2020

### Changes

* [BUGFIX] Fix `ISO8601DateFormatter` crash on iOS 11.0 and 11.1. See #129 (Thanks @lgaches, @Britton-Earnin)

# 1.2.0 / 05-22-2020

### Changes

* [BUGFIX] Logs: Fixed family of `NWPathMonitor` crashes. See #110 (Thanks @LeffelMania, @00FA9A, @jegnux)
* [FEATURE] Logs: Change default `serviceName` to app bundle identifier. See #102
* [IMPROVEMENT] Logs: Add milliseconds precision. See #96 (Thanks @flobories)
* [IMPROVEMENT] Logs: Deliver logs faster in app extensions. See #84 (Thanks @lmramirez)
* [OTHER] Logs: Change default `source` to `"ios"`. See #111
* [OTHER] Link SDK as dynamic framework in SPM. See #82

# 1.1.0 / 04-21-2020

### Changes

* [BUGFIX] Fix "Missing required module 'Datadog_Private'" Carthage error. See #80
* [IMPROVEMENT] Logs: Sync logs time with server. See #65

# 1.0.2 / 04-08-2020

### Changes

* [BUGFIX] Fix "'module.modulemap' should be inside the 'include' directory" Carthage error. See #73 (Thanks @joeydong)

# 1.0.1 / 04-07-2020

### Changes

* [BUGFIX] Fix "out of memory" crash. See #64 (Thanks @lmramirez)


# 1.0.0 / 03-31-2020

### Changes

* [FEATURE] Logs: Add logging feature

