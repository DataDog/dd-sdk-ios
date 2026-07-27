# Shopist Memory Profiling Representativeness Validation

## Objective

Update Shopist with deterministic, developer-controlled memory workloads that validate how useful the proposed iOS memory profiler is in realistic application usage.

This task does not validate profiler overhead. It validates:

1. Which customer memory problems are represented by `+allocWithZone:` sampling.
2. Whether the expected class and allocation stack are actionable in Datadog Profile Explorer.
3. How the profile behaves for partially supported and unsupported allocation paths.
4. Whether `alloc_*` and `inuse_*` communicate allocation churn and retention as intended.

The result should be a small evidence package that can be referenced by the iOS Memory Profiling RFC.

## Scope

Add a debug-only **Memory Profiling Validation** screen to Shopist. The screen must expose isolated controls for the workloads below and a single reset action.

Do not add or change SDK behavior as part of this task. Shopist is only the workload generator and validation host.

## Preconditions

- Use a Shopist build containing the memory-profiling PoC.
- Enable RUM and continuous CPU profiling using the normal Shopist configuration.
- Enable memory profiling at 100% for the validation build.
- Run on a physical iPhone using a Release or release-like internal configuration.
- Keep all validation UI and workload code behind Shopist's existing internal/debug mechanism so it cannot ship accidentally.
- Use deterministic, local data. Do not depend on network responses.

## Validation Screen

Create a screen named **Memory Profiling Validation** with:

- A visible status showing the active workload and its current retained object/byte count.
- One control for each workload.
- A **Reset All Workloads** control.
- Conservative and stress presets where useful.
- A confirmation step before any stress preset that intentionally retains substantial memory.

Each action must:

1. Emit a RUM action named `memory_profiling_validation`.
2. Include attributes:
   - `validation.scenario`
   - `validation.operation`
   - `validation.iteration`
   - `validation.requested_object_count`
   - `validation.requested_bytes`
3. Log the same information locally with a timestamp.
4. Execute from a scenario-specific call site so its allocation stack is recognizable in Profile Explorer.

Use stable class and function names beginning with `MemoryProfilingValidation` so captured stacks are easy to search.

## Workload 1: Retained NSObject Graph

### Purpose

Validate the strongest expected use case: Objective-C-compatible objects allocated through `+allocWithZone:` and deliberately retained.

### Implementation

- Define an `NSObject` subclass such as `MemoryProfilingValidationRetainedNode`.
- Give each node a small fixed set of instance properties and child references.
- Allocate a deterministic tree or linked graph from a named function such as `retainNSObjectGraph()`.
- Store the root in screen-owned validation state so the graph remains alive.
- Provide controls to retain additional graphs and release all retained graphs.

### Validation

- `alloc_objects` should increase when a graph is created.
- `inuse_objects` and `inuse_space` should remain elevated while the graph is retained.
- Releasing all roots should remove the graph from subsequent `inuse_*` profiles.
- The validation class and `retainNSObjectGraph()` call site should rank prominently.

## Workload 2: Transient NSObject Churn

### Purpose

Validate allocation churn that does not create lasting heap growth.

### Implementation

- Define a separate `NSObject` subclass such as `MemoryProfilingValidationTransientObject`.
- Allocate a deterministic number of objects from `performTransientNSObjectChurn()`.
- Release the objects within the same operation.
- Use an explicit autorelease pool where appropriate so lifetime is deterministic.
- Do not retain any objects after the action completes.

### Validation

- `alloc_objects` and `alloc_space` should show the workload.
- `inuse_objects` and `inuse_space` should return near their pre-action baseline.
- The transient allocation call site should be clearly distinguishable from the retained graph.

## Workload 3: Foundation Data or Image Cache

### Purpose

Demonstrate the known partial-coverage case where an Objective-C wrapper is visible but substantial backing storage may be allocated elsewhere.

### Implementation

- Implement a cache owned by validation state.
- Populate it from a named function such as `growFoundationBackedCache()`.
- Use deterministic local `NSMutableData`, decoded image, or bitmap-backed objects.
- Ensure the requested payload is physically materialized rather than lazily represented or optimized away.
- Expose controls to add cache entries and clear the cache.
- Track both wrapper count and requested payload bytes in the UI and RUM attributes.

### Validation

- Determine whether the wrapper class and allocation stack appear.
- Compare the profile's attributed bytes with the known requested payload.
- Record whether the backing memory is fully represented, partially represented, or absent.
- Clearing the cache should reduce process memory even if the profiler reports only part of that reduction.

This scenario is expected to document a limitation, not necessarily pass with full byte attribution.

## Workload 4: Pure Swift Retained Graph

### Purpose

Provide an unsupported-path control and verify that the product limitation is observable and accurately documented.

### Implementation

- Define a pure Swift class that does not inherit from `NSObject`, such as `MemoryProfilingValidationPureSwiftNode`.
- Build and retain a graph comparable in object count and approximate payload to Workload 1.
- Allocate it from a distinct `retainPureSwiftGraph()` call site.
- Provide a release action.

### Validation

- Confirm that the pure Swift allocation stack and type are absent or materially underrepresented.
- Confirm that process memory still grows while the graph is retained.
- Use the result to document that v1 does not cover pure Swift object allocation paths.

The absence of this workload from the profile is the expected result.

## Optional Control: Raw Native Allocation

If time permits, add a raw `malloc` buffer workload with explicit allocation, memory touching, retention, and `free`.

Expected result: process memory changes, but the allocation is not attributed through the NSObject sampler.

## Reset and Safety Requirements

`Reset All Workloads` must:

- Release every retained graph and cached object.
- Free any optional native buffers.
- Drain relevant autorelease pools.
- Update the visible retained counts to zero.
- Emit a `validation.operation = reset` RUM action.

Apply a hard upper bound to every workload. A mistaken repeated tap must not grow memory without limit. Prefer defaults that are safe on lower-memory physical devices.

## Evidence to Collect

For each workload:

1. Start from Reset and allow one baseline profile window.
2. Run the conservative preset.
3. Keep retained workloads alive for at least two profile windows.
4. Capture the relevant Profile Explorer view for:
   - `alloc_objects`
   - `alloc_space`
   - `inuse_objects`
   - `inuse_space`
5. Reset the workload and capture at least one subsequent window.
6. Record:
   - Device and OS version.
   - Shopist and SDK commit.
   - Workload parameters.
   - Known retained object count and requested bytes.
   - Observed top classes and stacks.
   - Whether the expected call site appears in the top three relevant entries.
   - Any difference between requested bytes, process-memory growth, and profiled bytes.

Export or link the resulting profiles where possible. Store screenshots and a short findings table with the RFC's validation evidence.

## Acceptance Criteria

The validation is successful when:

- The retained NSObject workload produces sustained `inuse_*` attribution to its expected class and allocation stack.
- The transient NSObject workload is prominent in `alloc_*` without equivalent sustained `inuse_*`.
- The Foundation-backed cache clearly demonstrates and quantifies its degree of representation.
- The pure Swift control demonstrates the documented v1 blind spot.
- Retained and transient Objective-C culprits are discoverable in the top three relevant Profile Explorer entries.
- Reset actions produce the expected reduction for supported live objects.
- Results can be summarized without claiming parity with total process memory or `phys_footprint`.

## Deliverables

- Shopist implementation of the debug-only validation screen and workloads.
- Tests for workload state and reset behavior where practical.
- Profile Explorer screenshots or exported profile links for every workload.
- A findings table classifying each workload as:
  - Reliably detected
  - Partially represented
  - Unsupported
- Recommended wording for the RFC's **Measurement Contract**, **Validated Customer Problems**, and **Known Limitations** sections.
