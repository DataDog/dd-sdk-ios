# Repeated view occurrence isolation

## EXP-205 — Prove the independent source-less E02 defect

Defined before implementation on freshly verified develop62f64. The
[owning result](../Results/EXP-205-view-occurrence-isolation.json) freezes source,
selectors, environment and a60minute/two-invocation bound. This is an independent
ordinary-app defect investigation, not reuse of scene-targeted experimental tests.

Retain Home H1 with a pending Resource, navigate Detail then Home H2 with the
same key. The first control discriminates H2 start-attribute leakage. The second
uses an empty H2 start and asserts H1 unchanged before a later attributed H2 stop,
so it discriminates that stop independently. Resource events must keep H1's UUID;
new actions must use H2's UUID. Existing restoration coverage gains explicit
one-active-occurrence assertions.

Both controls must first fail unchanged develop only on the intended attribute
assertions. Then, and only then, admit two active-view predicates in one internal
source file and run the full affected RUM unit target. Keep old-view Resource
lifetime, active stop enrichment, supported platforms and public/wire behavior.
Stop on unexpected failure or timeout; no automatic retries. Independent native
and release qualification remain necessary before shipping this E02 candidate.

The initial build stops before tests because the isolated checkout lacks the
existing OpenTelemetryApi XCFramework; the result inventory has zero tests.
Source/dependencies/protected paths and hostless cleanup pass. A separately
recorded correction admits copying only that already-qualified prebuilt framework
and freezing its complete member inventory. One corrected red invocation and one
green invocation remain within the original deadline. No assertion, SDK behavior
or dependency version changes; any further environment/build issue stops the run.

The framework-corrected attempt then stops at test compilation: four mock calls
use the wrong named-argument order and six accesses target private `activeView`.
No test executes. Root checks the actual declarations and separately admits the
exact scaffold correction: attributes before identity, and active lookup through
the existing internal `viewScopes` collection. All assertions and the original
deadline remain fixed; production is still unchanged. The failed draft and full
diagnostics remain preserved. This is not SDK regression evidence.

The corrected baseline executes exactly two tests and fails only the intended H1
attribute checks: `home-2` and `late-stop` replace `home-1`. The stop control's
pre-stop assertion passes. The reviewed two-predicate fix at3ce541b3 then passes
all903 RUM tests/939 executions with zero failures/skips; the complete inventory
is the existing901 identifiers plus the two new tests. Tests are byte-identical
between red and green; only one production file differs across1864 source entries.
Independent source/artifact review, changed-file lint and cleanup pass. The local
commit uses the authorized unsigned fallback after signing timeout.

A separately frozen public-monitor phase completes this experiment's native
serialization boundary. It uses both existing full-view/delta attribute test
classes, identical source-less public APIs and exact Resource/action owners.
One baseline invocation must fail only H1's attribute-set assertion in both modes;
one candidate invocation must pass both unchanged tests. Each is bounded600seconds,
with25minutes total inside the original deadline. No credentials, backend run,
additional production edit or retry is admitted. E02 remains open until this
phase and its independent review finish; full release qualification remains separate.

The first public-monitor attempt stops at compilation with zero tests: root used
`takeSingle()` on event arrays, but the existing helper is session-specific.
The failed artifacts remain frozen. A declaration-reviewed scaffold correction
retains exact-one assertions and uses `XCTUnwrap(first)` for safe event extraction
in both mirrored classes. SDK source and semantic assertions stay fixed. One
corrected pair is admitted within the original native25minute and overall
deadlines; any further build/oracle issue stops it.

The corrected native baseline executes the two intended failures, then reaches
its 600-second host deadline before a readable result bundle exists. Its candidate
does not run. A passive sample identifies Xcode waiting for its separate
`simctl diagnose --timeout=600` child after Example exits. EXP-201 retained the
same collector timeout. Fixture and owned collector cleanup pass. A separately
reviewed host correction adds documented `-collect-test-diagnostics never` to
both arms, omitting verbose diagnostic archives while retaining assertions,
sanitizer settings, console/runtime warnings and complete xcresult checks. The
original native and experiment deadlines remain fixed; invocation caps shorten
to reserve cleanup time. No further correction is admitted.

The corrected pair is complete: unchanged develop fails exactly the two intended
H1 attribute-set assertions; the candidate passes both unchanged tests with no
skips. Both readable xcresults, exact inventories, frozen source/product identities
and cleanup finish before the original native deadline. The production change
remains the two predicates at `3ce541b3`; public tests are committed separately at
`96d064c4`, using the authorized unsigned fallback after a signing timeout.

This closes E02 eligibility after independent artifact review. It verifies public
monitor commands through feature-writer JSON in a native XCTest host, alongside
the 903-test RUM suite. Stored upload bytes, backend ownership, native navigation,
full candidate release qualification and E01 gates remain separate. Each console
retains 251 literal warning lines and 59 duplicate-class messages; an empty
structured warning list does not certify clean diagnostics. Verbose diagnostic
archives are omitted in the accepted pair, with prior failed attempts preserved.
