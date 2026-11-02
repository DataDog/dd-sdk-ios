-------------------------- MODULE ClientStatsFlush --------------------------
EXTENDS Naturals, TLC

VARIABLES phase, buffered, pendingWrite, stored, flushAcknowledged

vars == <<phase, buffered, pendingWrite, stored, flushAcknowledged>>

Init ==
    /\ phase = 0
    /\ buffered = 1
    /\ pendingWrite = 0
    /\ stored = 0
    /\ flushAcknowledged = FALSE

Next ==
    \/ /\ phase = 0
       \* flushForStorage removes the bucket and eventWriteContext defers its write.
       /\ phase' = 1 /\ buffered' = 0 /\ pendingWrite' = 1
       /\ UNCHANGED <<stored, flushAcknowledged>>
    \/ /\ phase = 1
       /\ phase' = 2 /\ flushAcknowledged' = TRUE
       /\ UNCHANGED <<buffered, pendingWrite, stored>>
    \/ /\ phase = 2
       /\ phase' = 3 /\ pendingWrite' = 0 /\ stored' = 1
       /\ UNCHANGED <<buffered, flushAcknowledged>>

FlushIsBarrier == ~flushAcknowledged \/ (buffered = 0 /\ pendingWrite = 0)

Spec == Init /\ [][Next]_vars

=============================================================================
