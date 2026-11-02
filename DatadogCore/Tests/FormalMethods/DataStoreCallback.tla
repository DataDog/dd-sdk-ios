-------------------------- MODULE DataStoreCallback --------------------------
EXTENDS Naturals, TLC

VARIABLES phase, acceptedReads, pendingReads, completedReads, storeAlive

vars == <<phase, acceptedReads, pendingReads, completedReads, storeAlive>>

Init ==
    /\ phase = 0
    /\ acceptedReads = 0
    /\ pendingReads = 0
    /\ completedReads = 0
    /\ storeAlive = TRUE

Next ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ acceptedReads' = 1 /\ pendingReads' = 1
       /\ UNCHANGED <<completedReads, storeAlive>>
    \/ /\ phase = 1
       /\ phase' = 2 /\ storeAlive' = FALSE
       /\ UNCHANGED <<acceptedReads, pendingReads, completedReads>>
    \/ /\ phase = 2
       \* The queued weak-self closure runs and returns without the callback.
       /\ phase' = 3 /\ pendingReads' = 0
       /\ UNCHANGED <<acceptedReads, completedReads, storeAlive>>

EveryAcceptedReadCompletes == phase < 3 \/ acceptedReads = completedReads

Spec == Init /\ [][Next]_vars

=============================================================================
