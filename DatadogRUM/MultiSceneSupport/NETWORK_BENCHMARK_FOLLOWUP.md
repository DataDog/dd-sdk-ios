# Network benchmarking infrastructure follow-up

Status: optional follow-up, saved on 2026-09-20 at the user's request.
Owner: SDK testing-infrastructure maintainers; ownership assignment and scheduling
remain open. This work does not block the E01 URLSession bug fix or Duo readiness.

The [preserved harness](../../tools/multi-scene/network-benchmark-followup/README.md)
contains the implemented fixture, runner, evaluator, controls, build inputs and
qualified evidence. Its [manifest](../../tools/multi-scene/network-benchmark-followup/manifest.json)
verifies 71 preserved files, including a byte-checked compressed archive of92
raw records from the stopped matrix. The original
[EXP-198 protocol](Experiments/EXP-198-network-performance-protocol.md) and
[result](Results/EXP-198-network-performance.json) retain the experiment history.
No measured failure or incomplete run is relabeled as a pass.

## Current release acceptance

The user clarified that “RUM should not be worse” means preserving View and Action
information and Resource-to-view attribution. For network interception, correctness
and absence of leaks/retain cycles take priority. No additional task-owned objects
may survive the task's required lifecycle. Increased bytes, allocation counts or
processing per task are acceptable when they have no visible impact on an iPhone
15-class device under representative use.

Consequently, completing EXP-198's 32-cell matrix and meeting its nanosecond,
allocation-count or retained-byte budgets are not E01 release prerequisites.
Required network checks remain functional regression coverage and focused lifetime
checks across success, failure, cancellation and feature release. No replacement
mandatory network performance campaign or standalone device-impact assessment is
required. Investigate further only if there is concrete evidence of a visible
problem. Legitimate active ownership is distinct from retention after completion.

The user's latest scope limits required performance benchmarking to a bounded,
representative before/after application comparison for the new SwiftUI semantic
tracking and multi-scene changes: frame rate, hitches/hangs, CPU and memory.
Correctness, attribution and object lifetime remain separate. The expectation that
regressions are unlikely is not a measured result. S1:P01/P02 are optional network
follow-ups, S1:P03 retains object lifetime, and S1:P04 retains accepted reentrancy.
S2/S3:P01 owns the relevant application comparison or verified source exclusion;
S2/S3:P02 is optional microbenchmark infrastructure. No new gate is marked passed.

The matrix stopped after22 valid cells when a host guard mistook macOS's
BackgroundShortcutRunner for XCTest before the next app launch. The guard
correction passes41 controls. An independent reviewer approved retaining those
cells under the original deadline, but the continuation implementation, its added
controls and native slots22–31 were not executed before this scope correction.
All raw receipts, the failed preflight and unfinished continuation are preserved.
No numeric matrix verdict or SDK performance regression is inferred.

## Preserved capabilities and limitations

The prototype compares exact baseline/candidate source and binary identities in
Release builds. It covers automatic and registered-delegate interception, caller
and queued-work timing boundaries, calibrated all-thread allocation counters,
repeated task lifetimes and explicit cleanup. The original snapshot has37 passing host controls,
29 passing corrected evaluator controls, two successful Release builds and four
successful native prerequisite cells at the recorded checkpoint. These and the later41-control guard correction are harness/fixture qualification,
not a completed performance verdict or device-impact claim.

The snapshot contains an observed timing input, original oracle mistake and its
source-backed correction: the baseline held second resume mutates twice but emits
one SDK start. Completed-task re-resume is a separate discriminator. Preserve that
distinction when generalizing the fixture. The earlier terminal-state retention
finding and EXP-199 repair remain correctness evidence.

## Bounded integration backlog

| Deliverable | Owner | Dependency | Decisive check | Environment |
| --- | --- | --- | --- | --- |
| Package a configurable benchmark runner | SDK test-infrastructure maintainer | Preserved sources and chosen infrastructure location | Fresh checkout can build the fixture for explicit baseline/candidate revisions and discovered destinations without old temporary paths | Supported Xcode and simulator; no credentials or backend |
| Select maintainable representative workloads | Network instrumentation maintainer | Runner packaging and review of the current callback boundaries | Real native prerequisites and retained-owner controls discriminate missing work and leaks; workload stays finite | Automatic and registered delegates; Release build |
| Qualify repeatability and useful reporting | SDK performance maintainer | Representative workloads | Repeated unchanged-baseline comparisons characterize noise; raw samples, all-thread coverage and semantic negatives remain available | Dedicated idle host, with representative physical-device comparison where useful |
| Integrate with existing test infrastructure | SDK test-infrastructure maintainer | Reviewed workload/reporting contract | One scheduled or explicit run produces a compact source/build-bound report with artifacts and verified cleanup | Existing CI; new numeric enforcement requires a separate policy decision |

First decision when this follow-up is picked up: choose whether to integrate only
the lifetime regression fixture initially or the broader timing/allocation runner.
No new experiment, optimization project or CI gate is authorized merely by saving
this work.
