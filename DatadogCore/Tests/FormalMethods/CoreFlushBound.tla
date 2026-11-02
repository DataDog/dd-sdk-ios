----------------------------- MODULE CoreFlushBound -----------------------------
EXTENDS Naturals, TLC

VARIABLES phase, round, pendingMessage, activeMessage, flushAcknowledged

vars == <<phase, round, pendingMessage, activeMessage, flushAcknowledged>>

Init ==
    /\ phase = 0
    /\ round = 0
    /\ pendingMessage = 0
    /\ activeMessage = 0
    /\ flushAcknowledged = FALSE

Next ==
    \/ /\ phase = 0 /\ round < 5
       /\ round' = round + 1
       /\ pendingMessage' = IF round = 4 THEN 1 ELSE pendingMessage
       /\ UNCHANGED <<phase, activeMessage, flushAcknowledged>>
    \/ /\ phase = 0 /\ round = 5 /\ pendingMessage = 1
       /\ phase' = 1 /\ pendingMessage' = 0 /\ activeMessage' = 1
       /\ UNCHANGED <<round, flushAcknowledged>>
    \/ /\ phase = 1
       /\ phase' = 2 /\ flushAcknowledged' = TRUE
       /\ UNCHANGED <<round, pendingMessage, activeMessage>>

FlushIsBarrier == ~flushAcknowledged \/ (pendingMessage = 0 /\ activeMessage = 0)

Spec == Init /\ [][Next]_vars

=============================================================================
