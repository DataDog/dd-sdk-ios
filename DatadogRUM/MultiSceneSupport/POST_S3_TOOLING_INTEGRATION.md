# Reusable SDK tooling and documentation after S3

Status: planned after the S3 release; saved on 2026-09-22 at the user's request.
Owner: SDK maintainers with testing-infrastructure and documentation maintainers;
assign named owners when scheduling the work.
Dependency: S3 has shipped; record its released tag and source revision before starting.
This is a post-release integration follow-up, not an S1, S2 or S3 release gate.

## Goal and scope

Make the valuable tools, regression fixtures and engineering knowledge developed
through S1, S2 and S3 available to everyone working in this repository. Cover
maintainers, new contributors and agents; ordinary developer workflows must work
without a particular assistant, personal plugin installation or conversation history.

Inventory the complete corpus as it exists at S3 release, including additions since
this follow-up was saved. Integrate as much useful material as can be maintained,
rather than selecting only a convenient small subset. For each asset family,
record its value, readiness, maintenance cost and disposition: integrate, generalize,
move into existing tests or guidance, archive as evidence, or retire with a reason.
Identify valuable unfinished items explicitly rather than treating them as delivered.
Avoid duplicating infrastructure already maintained in the repository.

Start with the [runbook](TOOLING_RUNBOOK.md),
[tooling directory](../../tools/multi-scene),
[probe](../../Datadog/Example/MultiSceneProbe/README.md) and
[design and evidence map](../MULTI_SCENE_SUPPORT.md). Read historical experiments
only when needed to preserve a specific discriminator or decision.

## Deliverables

Owners below are responsible roles, not an assertion that a person has accepted
the assignment. This table is the follow-up's finite checklist.

| ID | Deliverable and value | Owner | Dependency | Decisive acceptance | Environment |
| --- | --- | --- | --- | --- | --- |
| I01 | Inventory and disposition of all S1-S3 asset families; high value for preserving useful work | SDK maintainer | Released S3 source and retained artifacts | Every candidate family has a destination or explicit disposition, value/readiness assessment, named maintenance owner and evidence links; proposals and unqualified tools are identified | Repository and retained artifacts; no native execution |
| I02 | Contributor and agent documentation; very high value | Documentation maintainer + relevant module owners | I01 | Existing contribution, development, testing, architecture and known-concern guides route to concise task references for SDK work, Xcode, simulators/devices and Datadog; an unfamiliar contributor can find the right procedure without experiment history | Fresh checkout; documentation/link checks |
| I03 | Reusable local evidence and execution helpers; very high value | Testing-infrastructure maintainer | I01 | Explicit inputs replace fixed revisions, toolchain paths, destinations, temporary directories and reviewer identities; identity, schema, freshness, persistence, deadline and cleanup controls reject known invalid evidence | Offline controls plus one bounded native qualification for each retained interaction mechanism |
| I04 | Datadog retrieval, ownership and profile verification; very high value | Telemetry integration maintainer | I01, I03 | Complete pagination/counts, whole-session ownership, exact identifiers, delayed events and actual profile artifacts are verified; sanitized fixtures exercise missing, duplicate, stale, truncated and wrong-owner data; live adapters declare their supported capabilities | Offline fixtures for all contributors; separately authenticated RUM/APM/Logs/Profiling checks as applicable |
| I05 | Maintained compatibility and native regression fixtures; high value | RUM maintainer + testing-infrastructure maintainer | I01, I03 | Ordinary UIKit/SwiftUI, mounted lifecycle/threading/retention, Resource/Trace and native/WebView cases protect meaningful invariants; deterministic cases join existing tests, native cases retain qualified scenario contracts and negative controls | Explicit supported Xcode/runtime matrix; simulator first, physical or human input only where required |
| I06 | Performance and profiling integration; high specialist value | Performance and profiling maintainers | I01, I03, I04 where backend joins are needed | Reuse baseline/candidate comparisons, allocations, retained-state and profile-correlation verification with documented noise and scope; integrate or explicitly disposition each candidate without claiming incomplete matrices are qualified | Isolated measurement host; representative device and backend only where the retained workload requires them |
| I07 | Durable design decisions and failure lessons; very high value | RUM and affected module maintainers | I01, released S3 behavior | Ownership, fallback, threading, lifecycle and compatibility contracts are concise, source-backed and linked to regression tests; rejected approaches explain the discriminator; shipped behavior is distinct from proposals | Source, existing tests and evidence review |
| I08 | Adoption, maintenance and evidence migration; high value | SDK maintainer + tooling owners | I02-I07 | A contributor outside the original work uses the documented commands from a fresh checkout; retained tools have owners, entry points, qualification limits and CI/manual lanes; links survive archival and valuable deferred items remain visible | Fresh supported development environment; CI and access-controlled artifact storage where applicable |

## Candidate material to preserve

- Environment discovery and build/test verification from
  [environment guidance](Tooling/ENVIRONMENT.md) and
  [build guidance](Tooling/BUILD_TEST.md): actual toolchain/workspace/destination,
  selected tests, finalized results, compiler membership and installed binary identity.
- [Evidence contracts](Tooling/EVIDENCE.md),
  [installed-code verification](../../tools/multi-scene/acceptance/installed_code.py)
  and [shared assertions](../../tools/multi-scene/acceptance/acceptance_common.py).
  Preserve negative controls for stale fixtures, consumed readiness, restored run
  identifiers, assertions after the critical boundary and incomplete cleanup.
- [Device interaction](Tooling/DEVICE_INTERACTION.md) and qualified runner
  supervision: persist actual returned observations, verify input effects and
  task-process quiescence, restore original state and retain separate scenario,
  evidence and cleanup verdicts. Required missing evidence or cleanup stays invalid.
- [Datadog procedures](Tooling/BACKEND.md) and
  [transport validation](../../tools/multi-scene/acceptance/app_journey_transport.py):
  complete inventories, correct owners, exact joins and backend capability discovery.
- The [probe](../../Datadog/Example/MultiSceneProbe/README.md),
  [automatic coverage](../../tools/multi-scene/automatic-coverage/README.md),
  [SwiftUI lifetime](../../tools/multi-scene/swiftui-lifetime/README.md) and
  [controller threading](../../tools/multi-scene/controller-threads/README.md)
  fixtures, plus the other lifecycle, restoration, handoff and WebView fixtures.
- [Baselines](../../tools/multi-scene/baselines/README.md) and
  [profiling correlation](../../tools/multi-scene/profiling-correlation/README.md).
  Coordinate network work with the existing
  [network benchmarking follow-up](NETWORK_BENCHMARK_FOLLOWUP.md); do not create a
  duplicate campaign or reinterpret its incomplete evidence as a performance verdict.
- [Operations](OPERATIONS.md), [Resource completion](E03_COMPLETION_CONTRACT.md),
  [rejected approaches](REJECTED_APPROACHES.md),
  [component review](COMPONENT_REVIEW.md) and
  [simulator evidence limits](DUO_SIMULATOR_ASSESSMENT.md).
  Extract enduring decisions and source-linked tests, keeping historical reviews dated.
- [Progressive documentation](Tooling/DOCUMENTATION.md) and the
  [checklist validator](../../tools/multi-scene/release_checklist.py): one owner per
  fact, generated summaries, discoverable procedures and bounded reading paths.
  Separate reusable checks from S1-S3-specific policy.

This list seeds I01; it does not exclude valuable work completed later in S3.
Full runners and newly prepared human-input paths require a fresh readiness
assessment. Preparation or offline controls alone do not establish native reliability.

## Integration and completion rules

1. Put reusable commands and tests in maintained repository locations. Prefer
   small composable helpers and existing infrastructure. Describe prerequisites,
   inputs, outputs, artifact schemas, expected failure modes and cleanup.
2. Use the same commands for developers and agents. Keep AGENTS.md as a short
   router; optional task skills should invoke shared tooling, not duplicate rules
   or require personal plugins. Routine edits should not inherit release-campaign
   approval, identity or evidence requirements that do not apply to them.
3. Separate inexpensive offline CI, native compatibility, credentialed backend,
   performance and physical/human lanes. Missing access or unsupported environments
   must be explicit; a skipped or invalid run cannot become behavioral acceptance.
4. Preserve discriminating negative controls and original failed observations.
   Use descriptive scenario/test names. Keep experiment IDs only as provenance.
   Do not reopen completed release experiments solely to repackage documentation.
5. Keep credentials and internal configuration out of public artifacts. Use
   sanitized samples for offline tests and durable, appropriately restricted
   storage for raw internal telemetry. Preserve an old-to-new evidence/link map
   before moving or retiring files; historical records are not routine reading.
6. Assign a named owner and maintenance policy to each adopted component. Record
   unsupported versions and unqualified mechanisms honestly. Integrate in bounded,
   reviewable changes with validation appropriate to each extracted component.
7. Close this follow-up only after the inventory is fully dispositioned, adopted
   assets are discoverable and usable from a fresh checkout, and the independent
   contributor exercise passes. Document any valuable deferred assets with an owner
   and reason. File preservation alone does not satisfy repository-wide adoption.

Saving this follow-up starts no builds, simulator sessions, backend collection,
release gates, implementation campaign or automatic release monitoring.
