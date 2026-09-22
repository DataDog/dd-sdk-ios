# Controlled app acceptance capture

This validation-only patch serves the existing S2:F08 J01–J04 journeys. The
[capture definition](capture-definition.json) freezes its scope before implementation.
It adds no SDK changes, app routes, interactions or dependencies. Existing accepted
app builds and earlier failed Home runs keep their original verdicts.

Capture uses the app’s existing navigation delegate and scene/window hooks. It
preserves controller classes, custom predicate results, all mapper results (including
filtered errors), and the original `trackRUMView` expression. Native delegate,
SwiftUI lifecycle, mapper and asynchronously received core-context observations are
separate evidence. None is relabelled as a different callback or a synchronous owner.

Raw controlled-session mapper and Browser data stays in local artifacts. Copy only
sanitized summaries to the repository; never print configuration or token values.
The Browser observer returns false and does not mutate messages or replace handlers.

No build or native execution is admitted by this preparation. After offline controls
and review, create separately identified symmetric app builds. Qualify capture in
the first planned baseline journey of the ordered human session. Do not add an
extra input diagnostic or reopen an old deadline.
