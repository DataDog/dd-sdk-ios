# Deferred single-scene reliability extraction

Status: deferred. Do not execute this phase until the multi-scene runtime is
stable and every planned experiment is complete, documented, or explicitly
hardware-deferred.

This document owns the post-freeze extraction plan. The active multi-scene work
remains in [PLAN.md](PLAN.md); exact evidence remains in
[EXPERIMENTS.md](EXPERIMENTS.md).

## Objective

Deliver proven improvements that also fix existing source-less, single-scene
applications without customer code changes. Land those generic fixes on clean
branches from the then-current `develop`, then rebuild the scene-specific work as
a branch stacked on top.

Keep the completed original multi-scene branch as the experimental reference
until the rebuilt stack is fully compared and verified. Do not push any branch
before the final checkpoint and explicit approval.

## Entry gate: freeze multi-scene first

Before extracting anything:

1. Finish every planned simulator experiment.
2. Document every successful, failed, rejected, invalid, and
   hardware-inconclusive experiment.
3. Resolve or explicitly defer every remaining runtime-code question.
4. Update the overview, assessment, experiment ledger, plan, and handoff.
5. Run the final multi-scene validation suite.
6. Commit the completed state in logical, signed commits.
7. Confirm that no planned experiment is expected to change an extraction
   candidate.

Do not proceed while RUM scopes, network interception, `ViewCache`, or Trace
correlation are still changing.

Never stage local configuration, credentials, simulator artifacts, captured
intake payloads, or `xcconfigs/Datadog.local.xcconfig`.

## Preserve the completed implementation

Create a durable local safety ref for the final multi-scene state. Do not rewrite
or delete it. Record:

- final branch and commit;
- exact `develop` comparison revision;
- complete validation results;
- remaining physical-device and human-driven experiments;
- intentionally dirty or local-only files.

These historical commits are archaeological pointers only. Re-resolve the final
implementation after the freeze:

- `bf37a2e99`: network interception and Resource work;
- `ea787a35a`: repeated view occurrences;
- `a6cd5df60`: Resource completion ownership;
- `ff37d7154`: active-view cache retention;
- `dbb68ccae`: Trace request-time RUM context;
- `dcfe819a5`: Logs and mirrored-error routing, which remains scene-specific
  unless later evidence proves otherwise.

## Eligibility rule: prove a generic defect first

For each candidate, start from a clean branch based on the then-current
`develop`. First add a source-less, single-scene regression that fails on
`develop` and passes with the narrow extracted change. A test that requires scene
identifiers or exact command targets is not sufficient.

If the defect cannot be reproduced without multi-scene infrastructure, keep the
change on the multi-scene branch.

Generic branches must not introduce:

- `RUMSceneIdentifier`, `RUMCommandTarget`, or `RUMContextHandoff`;
- iOS 27-only behavior;
- SwiftUI manual-authority or semantic-navigation machinery;
- public API or wire-format changes.

## Mandatory extraction candidates

### URLSession exactly-once interception

Extract the invariant that one `URLSessionTask` produces one request mutation and
one instrumentation lifecycle even when `resume()` is repeated or follows a
suspension.

Take only synchronized prepared-task identity tracking, claiming before handler
mutation, the post-claim prepared-request fallback, completion cleanup, and
focused automatic plus registered-delegate compatibility tests. Keep UI-event
scene handoff and third-party scene capture on the multi-scene branch.

### Repeated RUM view occurrence isolation

Extract inactive scopes ignoring later start/stop commands for the same customer
or platform identity, restored scopes being marked already started, and
session-boundary protection against two active occurrences.

Required source-less tests:

- `Home -> Detail -> Home` creates distinct H1, D1, and H2 UUIDs;
- H1 retained by a pending Resource cannot absorb H2 lifecycle or attributes;
- H1's Resource stays on H1 while a new action belongs to H2;
- starting the same identity after restoration leaves one active occurrence.

### Resource completion ownership

Reimplement this narrowly on `develop`; do not cherry-pick the scene router.
Resolve completion ownership by `resourceKey`, and deliver metrics, success, or
failure only to that owner. The current view's action may advance expiration by
time, but must not count another view's Resource or error as its child.

Required source-less tests cover success and failure after A -> B navigation,
inactive owners, absence of B action/error counts and `error_tap`, and unchanged
ordinary same-view behavior.

### Active-view cache retention

Extract only the generic lifetime correction: active views remain pinned beyond
the current three-minute TTL; retention starts after the view becomes inactive;
stopped views keep the normal window; session expiration or non-transfer releases
the pin; capacity and newest-first behavior remain compatible.

Keep scene buckets and fair cross-scene eviction on the multi-scene branch. Add a
WebView regression proving that a long-lived active native view remains available
as its container.

## Conditional Trace extraction

After the mandatory four, reassess request-time Trace correlation. Extract it
only if it is still a bounded internal change using existing
`NetworkContext.rumContext` without scene infrastructure.

The acceptable slice captures the request-time `RUMCoreContext`, uses a fixed
span-write context for completion-created URLSession spans, and preserves an
explicitly absent start context rather than adopting a later view. Header
injection, sampling, and user/account behavior must remain unchanged.

Required tests reverse-complete requests started under two sequential views and
prove a request started without a view does not adopt one at completion. Do not
include the rejected existing-header or customer request-rewrite hardening.

## Work that stays scene-specific

Do not move these into the generic delivery:

- scene-aware Logs and mirrored-error routing;
- UI-event and `TaskLocal` scene handoff;
- scene-targeted manual APIs;
- SwiftUI semantic navigation and presentation authority;
- split-view structural filtering;
- WebView scene identity;
- cross-window Operations;
- per-scene crash, watchdog, INV, and lifecycle routing.

The Logs half of the earlier Logs/Trace grouping depends on the exact-view/action
router and is not currently a clean generic extraction.

## Rebuild as a local branch stack

Use ticketed repository branch names and signed, atomic commits. Do not use a
`codex/` branch. Resolve the real tickets before starting this deferred phase.

```text
develop
└── URLSession reliability
    └── RUM occurrence, Resource, and cache reliability
        └── optional Trace request-context reliability
            └── rebuilt multi-scene branch
```

Before each commit, show the staged diff, propose the ticket-prefixed message,
obtain approval, commit with signing enabled, and verify the signature. Do not
push.

Do not blindly rebase the original branch because its foundational commits mix
generic and scene-specific work. Create a new multi-scene branch from the final
generic tip, replay only scene-specific implementation by component, and
cherry-pick later commits only when they cannot reintroduce extracted code. Keep
the original branch as the comparison source and update documentation hashes only
after the rebuilt history is stable.

Investigate every unexpected production-source difference between the archived
and rebuilt branches. Their behavior should be equivalent once the generic base
is included.

## Validation gates

Run focused tests during each extraction, then the authoritative module suites:

- `DatadogInternal`;
- `DatadogRUM`;
- `DatadogWebViewTracking`;
- `DatadogTrace` if the conditional Trace slice is included.

Before review, also run `make test-ios-all`, `make spm-build-ios`, repository
lint, and API-surface verification. Read the current Makefile and simulator list
before selecting schemes or `DEVICE=`.

Run a live ordinary single-window control with scene support absent or disabled:

- automatic UIKit navigation and actions;
- `Home -> Detail -> Home`;
- a Resource started before navigation and completed afterward;
- repeated `resume()`;
- long-lived WebView/native-container attribution;
- a Trace crossing navigation if Trace is included.

Require correct ownership, distinct view occurrences, stable event volume, no
crash, and no new customer configuration. Then rerun the relevant multi-scene
experiments on the rebuilt stacked branch.

## Pre-review stop

Before pushing or opening code review, report:

- each extracted fix and commit;
- failing-before and passing-after evidence for every generic defect;
- focused, module, full-suite, lint, build, and API results;
- archived-versus-rebuilt branch comparison;
- remaining risks and device-only validation;
- signature verification for every new commit;
- confirmation that credentials and local configuration were not committed.

Stop there and request explicit approval before any push or code-review creation.
