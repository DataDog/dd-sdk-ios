### What and why?

Refresh the shared feature flags fixtures to keep mobile behavior consistent. Changed sources: `SOURCE_COMMIT`. Ref: FFL-3568.

### How?

Move the changed pins in `ci/feature-flags-precomputed-fixtures.json`; CI fetches the new snapshots before tests. The existing fixture loop runs new cases in normal SDK CI.

### Review checklist
- [ ] Feature or bugfix MUST have appropriate tests (unit, integration)
- [ ] Make sure each commit and the PR mention the Issue number or JIRA reference
- [ ] Add Objective-C interface for public APIs - see our [guidelines](https://datadoghq.atlassian.net/wiki/spaces/RUMP/pages/3157787243/RFC+-+Modular+Objective-C+Interface#Recommended-solution) (internal)
- [ ] Run `make api-surface` when adding new APIs
