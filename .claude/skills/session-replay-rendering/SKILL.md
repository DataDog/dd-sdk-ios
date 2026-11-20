---
name: dd-sdk-ios:session-replay-rendering
description: Diagnose and fix visual defects in the dd-sdk-ios Core Animation Session Replay pipeline. Use when investigating interaction states, choosing which pipeline stage owns a fix, or designing rendering regression coverage.
---

# Session Replay Rendering

Keep captured facts accurate, rendering decisions local, and main-thread work small. Read the affected pipeline before choosing where to fix an appearance defect.

## Establish the failing state

- For stable UI states, reproduce the defect in a layer-tree snapshot test (`SRLayerSnapshotTests`) by creating or extending a test fixture. Inspect the test attachments: captured layer tree, composition tree, wireframes, and rendered image.
- Read the snapshot test harness before proposing interaction coverage. The current harness hosts views and captures their state; it does not provide UI automation for holding a real touch or sampling a switch animation.
- When the defect depends on interaction, use a focused sample or runtime probe that captures layers through the same pipeline while interacting. Compare resting and active states, including semantics, wrapper layers, corner radii, shadows, and captured descendants. Distinguish observed changes from hypotheses about private UIKit types.
- Use that evidence to construct deterministic `CALayerSnapshot` values for unit tests. Do not make animation timing or private UIKit hierarchy construction a prerequisite for testing composition logic.

## Put the decision in the stage that owns it

Sources below are in `DatadogSessionReplay/Sources/LayerTreeRecorder/`.

| Stage | Responsibility |
|-------|----------------|
| `SemanticObservationMapping` and `CALayerSnapshot` | Capture layer identity, properties, privacy, and capture hints on the main thread. |
| `CompositionTreeBuilder` | Traverse captured `CALayerSnapshot` values and carry ancestor context through the tree. |
| `CALayerSnapshot+SRCompositionLayer` | Select the composition representation and generate rendering modifiers. |
| `LayerWireframeBuilder` | Generate wireframe content within the composition. |

A rendering approximation should normally change generated output while preserving the captured semantic observation. Reclassify a layer only when the observation itself is wrong.

When an output decision depends on ancestors, prefer carrying context from captured layer data through composition generation over walking live layer ancestors during capture. Keep context local to each traversal branch so it reaches descendants through wrappers without leaking into siblings.

Pass the smallest input each stage needs. Derive rendering decisions at the stage that owns them, and avoid passing both source context and values computed from it. Name context inputs to make their scope clear, including whether they describe the immediate parent or the ancestor chain.

Check representation requirements directly; avoid constructing output objects merely to decide whether they are needed. Make contextual dependencies explicit in method inputs. Reuse existing rendering behavior when it represents the same effect.

## Keep changes narrow

Scope new rendering behavior to the conditions supported by the investigation. Identify existing behavior that shares the same semantic category and should remain unaffected.

Inspect existing privacy and clipping paths before adding guards. Each extra condition should protect a reachable case or a documented invariant; avoid redundant checks that obscure the actual rendering rule.

Before ignoring sublayers, trace which descendants supply wireframe content and which are replaced by the ancestor's representation. A container's semantic category alone is insufficient to decide whether its descendants can be omitted.

## Cover behavior with the appropriate tests

- Choose tests based on the changed behavior. Use deterministic unit tests for transformations of captured layer data and snapshot tests for reproducible visual states.
- Review existing coverage before adding tests. Extend tests that already exercise the behavior, and add separate tests when they cover a distinct failure mode or integration boundary. Name tests after the behavior they prove.
- For visual regression testing, pull the layer-tree snapshot test reference PNGs for the supported environment being tested. Pointer files alone are insufficient. See [the snapshot test README](../../../DatadogSessionReplay/SRSnapshotTests/README.md) for commands and environment selection. Review unexpected image differences before deciding whether references should change.
- For interaction states the snapshot test harness cannot reproduce deterministically, identify the remaining E2E validation. Report what automated tests establish and what still needs to be verified in an actual replay.

For execution details, use the repository's [running-tests](../running-tests/SKILL.md) and [setting-up-worktree](../setting-up-worktree/SKILL.md) skills as needed.

Before presenting the diff, review it for decisions in the wrong stage, redundant arguments, helpers that only rename an expression, and tests that add no distinct coverage. Keep useful code when a proposed abstraction would only move the complexity elsewhere.
