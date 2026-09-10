# Flags SDK Simulator Diagnostics

## What This Does

The Example app runs network diagnostics on startup to verify the Datadog feature flags endpoints are reachable from the simulator/device. It checks:

1. **Configured site** — logs which `DatadogSite` is active and the endpoint URLs
2. **Flags CDN host** — computes the exact CDN hostname the SDK will call (e.g. `preview.ff-cdn.us5.datadoghq.com` for US5)
3. **DNS resolution** — resolves both the flags CDN host and the intake host, logs IP addresses or failure
4. **HTTP HEAD reachability** — HEAD requests to both CDN and intake endpoints
5. **HTTP POST probe** — SDK-shaped POST to the flags CDN with auth headers, reveals auth vs network errors
6. **Flag snapshot** — waits for `FlagsClient` to reach `Ready` state, then dumps all loaded flag keys with type/variant/reason

All results logged via `NSLog` with `[FlagsDiagnostics]` prefix. Also includes improved error reporting in the SDK's `FlagAssignmentsFetcher` to surface HTTP status codes instead of generic "bad server response."

## Prerequisites

- **Xcode 16+** (check repo's `.xcode-version` for exact version)
- **iOS Simulator** (any iPhone, iOS 17+)

## 1. Clone the branch

```bash
git clone -b typo/flags-emulator-diagnostics-ios \
  git@github.com:DataDog/dd-sdk-ios.git
cd dd-sdk-ios
```

## 2. Configure credentials

Create `xcconfigs/Datadog.local.xcconfig` (gitignored) to override defaults:

```
DATADOG_CLIENT_TOKEN=<YOUR_DD_CLIENT_TOKEN>
RUM_APPLICATION_ID=<YOUR_RUM_APP_ID>
DATADOG_SITE=us5
```

| Field | Description |
|-------|-------------|
| `DATADOG_CLIENT_TOKEN` | Client token from your Datadog org |
| `RUM_APPLICATION_ID` | RUM application ID from your Datadog org |
| `DATADOG_SITE` | Datadog site: `us1`, `us3`, `us5`, `eu1`, `ap1`, `ap2`, `uk1` |

**To test endpoint reachability without real credentials**, set `DATADOG_CLIENT_TOKEN` to any non-empty string and `RUM_APPLICATION_ID` to any non-empty string. The diagnostics will still run DNS + HTTP checks.

## 3. Build and run

```bash
# Open in Xcode
open Datadog.xcworkspace

# Select the "Example" scheme, pick a simulator, and Run (⌘R)
```

Or from command line:

```bash
xcodebuild build -workspace Datadog.xcworkspace \
  -scheme Example \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

## 4. Read diagnostics

```bash
# Filter logs for diagnostics
xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "FlagsDiagnostics"' --level info
```

Or in Xcode Console, filter for `FlagsDiagnostics`.

## Expected Output

### Working network

```
[FlagsDiagnostics] ========== FLAGS SDK NETWORK DIAGNOSTICS START ==========
[FlagsDiagnostics] Configured site: US5
[FlagsDiagnostics] Flags CDN URL: https://preview.ff-cdn.us5.datadoghq.com/precompute-assignments
[FlagsDiagnostics] Exposures intake URL: https://browser-intake-us5-datadoghq.com/api/v2/exposures
[FlagsDiagnostics] DNS [Flags CDN] preview.ff-cdn.us5.datadoghq.com -> x.x.x.x
[FlagsDiagnostics] DNS [Intake] browser-intake-us5-datadoghq.com -> x.x.x.x, ...
[FlagsDiagnostics] HEAD [Flags CDN] preview.ff-cdn.us5.datadoghq.com -> HTTP 405
[FlagsDiagnostics] HEAD [Exposures intake] browser-intake-us5-datadoghq.com -> HTTP 403
[FlagsDiagnostics] POST [Flags CDN] preview.ff-cdn.us5.datadoghq.com -> HTTP 200
[FlagsDiagnostics] POST [Flags CDN] body: {"data":{"type":"precompute-assignments",...}}
[FlagsDiagnostics] ========== FLAGS SDK NETWORK DIAGNOSTICS END ==========
[FlagsDiagnostics] FlagsClient state: ready
[FlagsDiagnostics] Flag snapshot: 3 flag(s) loaded
[FlagsDiagnostics]   flag: my-feature | type=boolean variant=true reason=STATIC
```

A 405 from HEAD and 403 from intake are expected — they confirm the server is reachable.

### Broken network / DNS failure

```
[FlagsDiagnostics] DNS [Flags CDN] preview.ff-cdn.us5.datadoghq.com -> FAILED: nodename nor servname provided
[FlagsDiagnostics] HEAD [Flags CDN] FAILED: A server with the specified hostname could not be found.
```

### Auth failure (valid network, bad token)

```
[FlagsDiagnostics] HEAD [Flags CDN] preview.ff-cdn.us5.datadoghq.com -> HTTP 405
[FlagsDiagnostics] POST [Flags CDN] preview.ff-cdn.us5.datadoghq.com -> HTTP 403
[FlagsDiagnostics] POST [Flags CDN] body: {"errors":["Forbidden"]}
[FlagsDiagnostics] FlagsClient state: error
[FlagsDiagnostics] Flag snapshot: client entered Error state
```
