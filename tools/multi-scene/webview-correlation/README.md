# Legacy native/WebView correlation

EXP-165 closes D11 using real Core, RUM, WebViewTracking and SessionReplay modules
in a clean installed single-scene app. It sends fixture browser events through
JavaScript in a mounted WKWebView and captures actual compressed RUM uploads on a
loopback HTTP collector, using a dummy client token. No local xcconfig is read.

```sh
python3 -B tools/multi-scene/webview-correlation/run.py \
  --control COMMIT --candidate COMMIT --output NEW-RESULT.json
python3 -B -m unittest discover -s tools/multi-scene/webview-correlation -p 'test_*.py'
```

The runner resolves an available iOS 27 simulator each time, builds source archives
from explicit paths, verifies clean uninstall/installed executable identity and
rejects stale results or restored run identifiers. Each arm has a fresh UUID and
collector. SDK, fixture, package and executable hashes are recorded before use;
SDK/fixture/executable identity is checked again after execution. The complete
manifest, build logs, console and captured payloads remain in the new artifact
root; the requested JSON provides the durable attempt entry.

The fixture waits for an exact browser event acknowledgement before mutating
native ownership. Acknowledgement is repeatable and cannot be consumed by a
previous reader. Both gzip and the SDK's actual deflate transport are decoded;
parse errors invalidate acceptance. Required evidence is 19 named checks plus a
Replay-enabled native view payload. The control must specifically fail legacy
container equality; the candidate must pass everything. Actual native mounting,
Replay enablement and source/run identity are preconditions, not optional checks.

The peer is an injected logical RUM branch in one real UIWindowScene. This tests
peer exclusion without claiming two native WebViews or multi-scene Replay support.
T10 owns the two-container/backend release evidence. The fixture supplies the
Browser SDK bridge envelope directly; it does not embed a downloaded Browser SDK.
The declared-multi-scene fallback prohibition is covered by receiver unit tests.
