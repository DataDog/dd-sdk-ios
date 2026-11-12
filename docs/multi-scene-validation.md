# Proposed multi-scene candidate validation

This stack is held from merge pending API review, physical iPhone Duo acceptance, final CI and maintainer approval. The proposed API has no stability approval yet.

The final candidate preserves the qualified SDK implementation. Its proposed exposure changes access levels and Release visibility without changing executable bodies. A later cleanup removes the unused, unshipped prototype target alias; all retained API declarations and executable bodies are unchanged. Accepted behavioral and normal-client evidence is reused after comparing source and affected dependencies; this deletion does not claim a new full SDK build or runtime run.

| Check | Scope and result |
| --- | --- |
| Ordinary SPM Release | Existing Core and RUM products compile and link with Swift 5 and Swift 6 consumers at deployment target iOS 15. |
| External conformer | An ordinary-import monitor conformer and all 21 target-taking Swift calls compile. The existing OperationOptions requirement uses a normal selective DatadogInternal import, without SPI. |
| Objective-C | Both consumer builds compile the 20 target-taking selectors. Actual generated Release headers contain the nullable DDRUMViewTarget factory. |
| Compiler configuration | Optimized products use no test-only, coverage, sanitizer or scene-validation flags. |
| Ownership and lifecycle | Applicable accepted captures cover independent windows, delayed work, automatic/manual attribution, navigation transitions, reader lifetime, scene lifecycle and restoration. Proposed exposure does not reopen those scenarios. |
| Platform and fallback | Existing applicable platform, disabled-path and legacy fallback evidence is retained. Additional validation is limited to changed interfaces and unresolved delivery requirements. |

The first repository-framework Release product carried test/coverage flags and was not accepted as an ordinary customer product. The SPM path above supplies that proof. Original stopped attempts and cleanup records remain unchanged in local evidence; later saved-result acceptance is separate.

Consumer compilation and linkage do not establish backend delivery or a real-app journey. The integration guide enables RUM and provides examples for that next step. Record the exact pinned revision, app integration changes, journeys and observed owners during app testing.

The integration examples pass typechecking in Swift 5 and Swift 6 language modes. Normal-import controls established that the prototype spelling and internal transition machinery were not customer exports, and deployment-target checks reject an unguarded iOS 27 host. The unused prototype alias has since been removed entirely. The checked-in snapshots use CI’s Swift 6.2 compiler: 40 Swift additions and 22 Objective-C additions, with no removals from the pinned delivery base. The SDK’s `observingCurrentDestination` initializer requires Swift 6.4 and remains in the source; it is absent from the Swift 6.2 snapshot. These are review diffs, not approved API contracts.

The source-documentation extractor reports diagnostics in inactive AppKit code while producing the complete RUM source inventory. Its strict semantic-clean audit remains incomplete. Ordinary iOS compilation, generated headers and consumer checks pass independently. The snapshots include SPI declarations and omit availability annotations, so the normal-import and availability checks define the actual customer exposure. The tool limitation, original failed audits and outgoing PR CI remain open before final acceptance. An older eight-cell build-SDK/Duo matrix was unexecuted and is not counted as accepted current coverage. Existing split-view/tab-bar capture limits remain. Session Replay captured-content correctness, optional networking benchmarks and unavailable React Native SPM integration are outside the completed scope. Physical Duo acceptance is still required before merge.
