# Async protocol diagnostics

This directory contains ten opt-in TLA+ counterexample configurations for asynchronous ownership, flush,
callback, and fan-out behavior in `DatadogCore` and `DatadogTrace`.

The models are diagnostic known counterexamples. A successful model run means
that TLC found the documented invariant violation. They are paired with XCTest
replays whose names begin with `testDiagnostic_`.

Start with [REVIEW-GUIDE.md](REVIEW-GUIDE.md), then see [FINDINGS.md](FINDINGS.md)
for the implementation evidence and limitations.

Run the models with:

```bash
DatadogCore/Tests/FormalMethods/run-models.sh /path/to/tla2tools.jar
```
