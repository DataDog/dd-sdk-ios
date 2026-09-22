# Selected S2 native/WebView comparison

The [owning preparation](../../../../DatadogRUM/MultiSceneSupport/Results/S2-T10-source-preparation.json)
freezes two cells and four Browser markers. This fixture uses normal SDK upload and
the actual installed WebKit message handler. Browser and native partitions retain
their own source/service fields. Session Replay is enabled only to establish native
container eligibility; captured Replay content is outside the test.

`acceptance/s2_webview_workflow.py` prepares exact source archives and builds both
arms. Build qualification binds every compiler input, object and complete product.
A reviewed plan, focused controls and a separate `native-admission.json` binding the
plan, review and both build receipts are required before `cell` may install an app.
Preparation or a successful build alone cannot admit native execution. Progress
updates at the owner do not invalidate a build; the frozen input/assertion/budget
contract and every executable helper remain exact.

Use the existing `acceptance/hosting_connector.js` with family `webview` to serve
raw Datadog count/page requests while the Python runner remains active. Every raw
response is persisted before validation/publication. No model turn is needed
between NativeB readiness, actual A deactivation and the M3 acknowledgement.

The runner exposes one `human_input` item when the exact native fold request is
ready. The operator changes only the selected Duo's fold pose. Actual display
inventory and active-display screenshots are captured locally; the sidebar icon
is never evidence. Open precedes NativeB, and Closed follows M3 acknowledgement.
Both gestures are outside the short inactive-retention interval. Request identity,
actual raw display bytes, public geometry/orientation, source-owned controller and
window inventory, and separate publication timing are mandatory. App waits use
monotonic durations; host deadlines use the host clock. Exact request/response
hashes and app-local consumption order join the clocks without assuming an offset.
Both clocks must accept their own boundary. Before launch, a real atomic output
publication/readback is checked in the native Documents directory.

A terminal snapshot seals the observation sequence. The host recaptures it before
removing the task app; a late callback stays an evidence failure even if cleanup
succeeds. Evidence failures cannot skip task-only termination/removal. Original
app/device/display state and process absence are checked independently. A later
restoration must never rewrite an original failed cleanup.

The first baseline cell qualifies this mechanism. Any failed cell stops the
matrix; no retries, live deadline extensions or equivalent input diagnostics.
T10 also needs the separately owned Datadog app journey. These cells confer no
interactive-navigation, adaptive-layout, physical-Duo or Replay-content credit.

Focused controls:

```sh
python3 -B -m unittest discover -s tools/multi-scene/acceptance -p 'test_s2_webview_*.py'
node --test tools/multi-scene/acceptance/test_hosting_connector.js
```
