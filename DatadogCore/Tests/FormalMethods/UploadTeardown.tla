---------------------------- MODULE UploadTeardown ----------------------------
EXTENDS Naturals, TLC

VARIABLES phase, accepted, persisted, attempts, delivered, retryableFailure

vars == <<phase, accepted, persisted, attempts, delivered, retryableFailure>>

Init ==
    /\ phase = 0
    /\ accepted = 0
    /\ persisted = 0
    /\ attempts = 0
    /\ delivered = 0
    /\ retryableFailure = FALSE

Next ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ accepted' = 1 /\ persisted' = 1
       /\ UNCHANGED <<attempts, delivered, retryableFailure>>
    \/ /\ phase = 1
       \* A normal transport failure is returned as needsRetry, not thrown.
       /\ phase' = 2 /\ attempts' = 1 /\ retryableFailure' = TRUE
       /\ UNCHANGED <<accepted, persisted, delivered>>
    \/ /\ phase = 2
       \* The defer marks the file as read even though no retry occurred.
       /\ phase' = 3 /\ persisted' = 0
       /\ UNCHANGED <<accepted, attempts, delivered, retryableFailure>>

RetryableWorkRemainsOwned ==
    phase < 3 \/ ~retryableFailure \/ attempts > 1 \/ persisted = 1 \/ delivered = accepted

Spec == Init /\ [][Next]_vars

=============================================================================
