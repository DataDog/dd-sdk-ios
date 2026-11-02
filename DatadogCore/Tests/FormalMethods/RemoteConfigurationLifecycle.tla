-------------------- MODULE RemoteConfigurationLifecycle --------------------
EXTENDS Naturals, TLC

CONSTANT Scenario

VARIABLES phase, running, inFlight, delivered, appliedVersion, highestCompleted

vars == <<phase, running, inFlight, delivered, appliedVersion, highestCompleted>>

Init ==
    /\ phase = 0
    /\ running = TRUE
    /\ inFlight = 0
    /\ delivered = 0
    /\ appliedVersion = 0
    /\ highestCompleted = 0

StopInFlight ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ inFlight' = 1
       /\ UNCHANGED <<running, delivered, appliedVersion, highestCompleted>>
    \/ /\ phase = 1
       /\ phase' = 2 /\ running' = FALSE
       /\ UNCHANGED <<inFlight, delivered, appliedVersion, highestCompleted>>
    \/ /\ phase = 2
       /\ phase' = 3 /\ inFlight' = 0 /\ delivered' = 1 /\ appliedVersion' = 1 /\ highestCompleted' = 1
       /\ UNCHANGED running

OutOfOrder ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ inFlight' = 2
       /\ UNCHANGED <<running, delivered, appliedVersion, highestCompleted>>
    \/ /\ phase = 1
       /\ phase' = 2 /\ inFlight' = 1 /\ delivered' = 1 /\ appliedVersion' = 2 /\ highestCompleted' = 2
       /\ UNCHANGED running
    \/ /\ phase = 2
       /\ phase' = 3 /\ inFlight' = 0 /\ delivered' = 2 /\ appliedVersion' = 1
       /\ UNCHANGED <<running, highestCompleted>>

Next ==
    \/ /\ Scenario = "StopInFlight" /\ StopInFlight
    \/ /\ Scenario = "OutOfOrder" /\ OutOfOrder

Contract ==
    /\ (Scenario = "StopInFlight" => ~(phase = 3 /\ ~running /\ delivered > 0))
    /\ (Scenario = "OutOfOrder" => (phase < 3 \/ appliedVersion = highestCompleted))

Spec == Init /\ [][Next]_vars

=============================================================================
