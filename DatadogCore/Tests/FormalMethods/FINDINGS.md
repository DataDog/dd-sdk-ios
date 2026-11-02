# Findings

## 1. Retryable teardown upload is removed after one attempt

**Priority:** P1 pending confirmation of the teardown contract.

`DataUploadWorker.flushSynchronously()` calls `dataUploader.upload(...)` inside
a `defer` that always marks the underlying file as read. Its second attempt is
only entered when `upload(...)` throws. Normal HTTP and network failures are
returned as `DataUploadStatus(needsRetry: true)`, so they do not throw, do not
receive the documented extra attempt, and are deleted when the scope exits.

The replay returns a retryable status followed by a success status. It observes
one upload attempt and no remaining file.

The path is currently documented as test-only and `flushAndTearDown()` also says
that it does not retry. Review is needed because the implementation comment says
it performs one more retry, while the higher-level method says all authorized
data should be considered uploaded after return.

## 2. Client-stats flush returns before storage takes ownership

**Priority:** P2.

`ClientStatsFeature.flush()` synchronously removes buckets from the concentrator,
then opens an asynchronous `eventWriteContext`. The `Flushable` call returns
while the exported buckets exist only in the pending closure and have not reached
the feature writer.

The replay defers write contexts, calls `flush()`, observes empty storage after
return, then runs the pending context and observes the bucket.

`DatadogCore.flush()` normally follows feature flushes with context and storage
queue barriers and repeats the sequence. That orchestration may compensate for
this schedule. The narrow question is whether direct `Flushable` conformance is
allowed to acknowledge before its own work is terminal.

## 3. Data-store read callback is stranded by store deallocation

**Priority:** P2.

`FeatureDataStore.value(forKey:callback:)` enqueues a closure that captures the
store weakly. If the store deallocates before that closure begins, the closure
returns without invoking the accepted callback with `.noValue` or `.error`.

The replay blocks the data-store queue, requests a read, releases the last store
reference, then drains the queue. The callback remains unfulfilled.

Normal core teardown flushes known data stores before releasing features. Owners
should validate other lifetimes, including feature replacement and callers that
retain a `DataStore` only long enough to issue a read.

## 4. Late message-bus receiver misses accumulated configuration

**Priority:** P3.

`MessageBus` accumulates configuration and schedules exactly one dispatch from
its initializer. Connecting a receiver after that deadline only inserts it into
the receiver map; it does not replay the saved configuration.

The replay waits until an initial receiver receives the accumulated snapshot,
then connects a second receiver and drains the bus. The second receiver receives
no configuration.

This matters only if a feature that consumes configuration telemetry can be
registered after the dispatch deadline. It may be accepted if the snapshot is
defined strictly as telemetry for features already present at initialization.

## 5. Message fallback is skipped after core deallocation

**Priority:** P3.

`MessageBus.send(message:else:)` checks its weak core reference inside the bus
queue. When that reference is nil it returns immediately, before testing
receivers and before invoking the fallback.

The replay connects a core, drains the connection, deallocates the core, sends a
message with a fallback, and drains the bus. The fallback is not called.

The public protocol describes the fallback as the path for messages that no
feature processes. Owners should decide whether a stopped core is outside that
contract or is precisely an unhandled-message case.

## 6. Older overlapping remote-config response overwrites newer state

**Priority:** P1 pending reachability review.

While `lastSyncDate` is nil, a foreground notification can start a second fetch
before the initialization fetch completes. Each completion persists and
publishes its payload without a request generation check. If the newer request
finishes first and the older request finishes second, the older payload replaces
both the cached file and `DatadogCore.remoteConfiguration`.

The replay starts two requests, completes request 2 with `newer`, then request 1
with `older`, and observes delivery order `[newer, older]` plus `older` on disk.

## 7. Core flush returns with fifth-round message work active

**Priority:** P2.

`DatadogCore.flush()` repeats its bus-feature-context-storage sequence exactly
five times. A flushable feature can enqueue bus work during the fifth feature
flush. No sixth bus barrier follows, so the method can return while that message
receiver is still running.

The replay sends a blocking message only from the feature's fifth `flush()` and
observes the core flush return before releasing the receiver.

## 8. RUM timeseries flush returns before storage takes ownership

**Priority:** P2.

`TimeseriesSessionCollector.flush()` synchronously empties its sample buffers,
but `flushMemory()` and `flushCPU()` transfer each batch into an asynchronous
`eventWriteContext`. The documented synchronous flush can therefore return while
the only copy of a batch is held by a pending closure.

The replay defers write contexts, flushes a sampled session, observes no stored
event after return, then runs the deferred contexts and observes the batch.

As with client stats, outer core queue barriers may compensate during ordinary
teardown. The direct collector contract is the question under review.

## 9. Stopped remote-config provider delivers an in-flight response

**Priority:** P2.

`RemoteConfigurationProvider.stop()` removes its foreground observer but does
not record a stopped state or cancel the active request. The request callback
checks only whether the provider has deallocated. A retained, stopped provider
therefore persists and delivers an in-flight response, contrary to the lifecycle
documentation.

The replay starts a controlled request, calls `stop()`, completes the request,
and observes the handler invocation.

## 10. Retry status migrates to a replacement upload batch

**Priority:** P2.

`DataUploadWorker.previousUploadStatus` belongs to the worker rather than to a
specific readable file. After batch A returns a retryable failure, external data
clearing can remove A before the next cycle. If batch B then appears, B is sent
with A's response code and attempt number.

The replay fails A with HTTP 500, removes A, stores B, and synchronously flushes.
The upload of B receives A's status as its `previous` value.

Owners should validate the consequences for request retry query parameters,
reconciliation, telemetry, and server-side request identity.
