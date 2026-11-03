# Review guide

## Purpose

This is an engineering-validation experiment, not a remediation proposal. It
records ten small schedules where accepted work changes owners and another
operation later claims that the work was flushed, delivered, or acknowledged.
Reviewers should decide whether each schedule is a product-contract violation,
accepted best-effort behavior, or an invalid assumption before a production fix
is designed.

No production code or public API is changed.

## Contracts under review

- **Ownership:** accepted work remains queued, in flight, retryable, delivered,
  or explicitly dropped.
- **Flush barrier:** a successful `Flushable.flush()` leaves all preceding work
  terminal.
- **Callback completion:** an accepted asynchronous read eventually invokes its
  callback, including a terminal no-value or error result.
- **Fan-out:** accumulated configuration reaches every applicable receiver, or
  remains replayable for a receiver that connects later.
- **Fallback:** an unhandled message invokes the fallback supplied by its caller.

## Evidence chain

Each finding has two forms of evidence:

1. A small TLA+ state machine derived from the current Swift transition order.
   The runner expects the named invariant violation and rejects an unexpected
   pass, parse failure, or unrelated failure.
2. A controlled XCTest replay against the real implementation. The diagnostic
   tests intentionally pass when they reproduce the recorded behavior.

The models describe only the stated protocols. The implementation tests show
that the corresponding schedule is reachable in the tested component, but do
not establish customer frequency or prove broader system behavior.

## Priority-ranked findings

Priority reflects possible data loss, false completion, and how ordinary the
precondition appears. It is not a claim about measured incidence.

| Rank | Priority | Finding | Minimal schedule | XCTest replay |
|---:|:---:|---|---|---|
| 1 | P1 | Retryable teardown upload is removed after one attempt | `STORE -> FLUSH -> RETRYABLE_FAILURE -> DELETE` | `testDiagnostic_SynchronousFlushDiscardsRetryableBatchWithoutRetrying` |
| 2 | P1 | Older overlapping remote-config response overwrites newer state | `FETCH_OLD -> FETCH_NEW -> APPLY_NEW -> APPLY_OLD` | `testDiagnostic_OutOfOrderSyncResponsesRegressAppliedConfiguration` |
| 3 | P2 | Core flush returns with fifth-round bus work active | `ROUND_1..5 -> SEND -> FLUSH_RETURN` | `testDiagnostic_FifthFlushRoundCanEnqueueUnawaitedMessageWork` |
| 4 | P2 | Client-stats flush returns before storage takes ownership | `RECORD -> EXPORT -> DEFER_WRITE -> FLUSH_RETURN` | `testDiagnostic_FlushReturnsBeforeExportedBucketsReachStorage` |
| 5 | P2 | RUM timeseries flush returns before storage takes ownership | `SAMPLE -> EXPORT -> DEFER_WRITE -> FLUSH_RETURN` | `testDiagnostic_FlushReturnsBeforeTimeseriesBatchReachesStorage` |
| 6 | P2 | Data-store read callback is stranded by store deallocation | `READ -> DEALLOCATE -> WORKER_SKIP` | `testDiagnostic_ReadCallbackIsStrandedWhenStoreDeallocatesBeforeQueuedWorkRuns` |
| 7 | P2 | Stopped remote-config provider delivers an in-flight response | `FETCH -> STOP -> COMPLETE` | `testDiagnostic_StopDoesNotSuppressInFlightConfigurationDelivery` |
| 8 | P2 | Retry status migrates to a replacement upload batch | `FAIL(A) -> REMOVE(A) -> STORE(B) -> RETRY(B, statusA)` | `testDiagnostic_RetryStatusMigratesToReplacementBatch` |
| 9 | P3 | Late message-bus receiver misses accumulated configuration | `SAVE -> DISPATCH -> CONNECT` | `testDiagnostic_LateReceiverMissesAccumulatedConfiguration` |
| 10 | P3 | Message fallback is skipped after core deallocation | `CONNECT -> CORE_DEALLOCATE -> SEND` | `testDiagnostic_MessageFallbackIsNotCalledAfterCoreDeallocation` |

## Replaying the evidence

Run the implementation diagnostics with the repository's normal module test
commands, filtering on `Diagnostic_` where the runner supports a test filter.
The tests live in:

- `DatadogCoreTests`: message bus, core flush, remote configuration, feature data store, and upload worker.
- `DatadogTraceTests`: client-side stats flush.
- `DatadogRUMTests`: timeseries flush.

Run the models with a local `tla2tools.jar`:

```bash
DatadogCore/Tests/FormalMethods/run-models.sh /path/to/tla2tools.jar
```

## Questions for owners

1. Does teardown flush promise delivery, attempted delivery, or only local
   deletion after an attempt?
2. Is the `Flushable` contract intended to apply to a feature directly, or only
   after `DatadogCore.flush()` performs its later queue barriers?
3. Must a `DataStore.value` callback complete if the owning feature stops?
4. Is configuration telemetry intentionally a one-time snapshot for receivers
   present at the timer deadline?
5. Should a missing core be treated as an unhandled message for fallback
   purposes?
6. Must `stop()` suppress already-started remote-configuration callbacks?
7. Should concurrent remote-configuration fetches be generation-ordered?
8. Can retry metadata outlive the exact file that produced it?
