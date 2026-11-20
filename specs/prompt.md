I started with the problem describe in @specs/description.md
I am doing good and, after a couple of interactions, I managed to create the @specs/current_change.diff diff which is good.
This diff doesn't reflect 100% @specs/description.md because I received some suggestions, and now the "How?" section of @specs/description.md needs to be updated because it still describes filtering in RUMViewScope.

Then, I reveiced another suggestion:

> Filtering in Monitor before the scopes looks like the right place to us.
> There's one case we'd like to keep: hangs right after the app comes back to the foreground. The run loop iteration that resumes the app starts while the history still says .background, and the SDK records .inactive only when it handles willEnterForegroundNotification inside that same iteration. A real hang in applicationWillEnterForeground, or anywhere else in that iteration, therefore overlaps .background for a moment, and containsState drops it. Could we drop a long task only when most of its interval falls in a suspendable state, for example by comparing applicationNotSuspendedDuration(during:) with the duration? A test with an interval that spans a .background to .inactive transition would cover it. A test in LongTaskObserverTests checking that the observer sets isMeasuredOnMainRunLoop would also protect the flag.

Task 1: apply the requested changes on the local branch without committing it
Task 2: update @specs/description.md
