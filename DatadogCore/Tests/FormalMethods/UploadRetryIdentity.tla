-------------------------- MODULE UploadRetryIdentity --------------------------
EXTENDS Naturals, TLC

VARIABLES phase, currentBatch, retryOwner, attempts

vars == <<phase, currentBatch, retryOwner, attempts>>

Init ==
    /\ phase = 0
    /\ currentBatch = "none"
    /\ retryOwner = "none"
    /\ attempts = 0

Next ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ currentBatch' = "A"
       /\ UNCHANGED <<retryOwner, attempts>>
    \/ /\ phase = 1
       /\ phase' = 2 /\ retryOwner' = "A" /\ attempts' = 1
       /\ UNCHANGED currentBatch
    \/ /\ phase = 2
       /\ phase' = 3 /\ currentBatch' = "none"
       /\ UNCHANGED <<retryOwner, attempts>>
    \/ /\ phase = 3
       /\ phase' = 4 /\ currentBatch' = "B"
       /\ UNCHANGED <<retryOwner, attempts>>
    \/ /\ phase = 4
       /\ phase' = 5 /\ attempts' = 2
       /\ UNCHANGED <<currentBatch, retryOwner>>

RetryBelongsToCurrentBatch == phase < 5 \/ retryOwner = "none" \/ retryOwner = currentBatch

Spec == Init /\ [][Next]_vars

=============================================================================
