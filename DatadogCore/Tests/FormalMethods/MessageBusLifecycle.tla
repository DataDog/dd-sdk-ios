------------------------ MODULE MessageBusLifecycle ------------------------
EXTENDS Naturals, TLC

CONSTANT Scenario

VARIABLES phase, configurationSaved, lateReceiver, configurationDelivered,
          coreAlive, fallbackCalled

vars == <<phase, configurationSaved, lateReceiver, configurationDelivered,
          coreAlive, fallbackCalled>>

Init ==
    /\ phase = 0
    /\ configurationSaved = FALSE
    /\ lateReceiver = FALSE
    /\ configurationDelivered = FALSE
    /\ coreAlive = TRUE
    /\ fallbackCalled = FALSE

LateConfiguration ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ configurationSaved' = TRUE
       /\ UNCHANGED <<lateReceiver, configurationDelivered, coreAlive, fallbackCalled>>
    \/ /\ phase = 1
       \* The one-shot timer dispatches to receivers connected at this instant.
       /\ phase' = 2
       /\ UNCHANGED <<configurationSaved, lateReceiver, configurationDelivered,
                       coreAlive, fallbackCalled>>
    \/ /\ phase = 2
       /\ phase' = 3 /\ lateReceiver' = TRUE
       /\ UNCHANGED <<configurationSaved, configurationDelivered, coreAlive,
                       fallbackCalled>>

MissingCoreFallback ==
    \/ /\ phase = 0
       /\ phase' = 1 /\ coreAlive' = FALSE
       /\ UNCHANGED <<configurationSaved, lateReceiver, configurationDelivered,
                       fallbackCalled>>
    \/ /\ phase = 1
       \* send() returns at its nil-core guard without invoking the fallback.
       /\ phase' = 2
       /\ UNCHANGED <<configurationSaved, lateReceiver, configurationDelivered,
                       coreAlive, fallbackCalled>>

Next ==
    \/ /\ Scenario = "LateConfiguration" /\ LateConfiguration
    \/ /\ Scenario = "MissingCoreFallback" /\ MissingCoreFallback

Contract ==
    /\ (Scenario = "LateConfiguration" =>
        ~(phase = 3 /\ lateReceiver /\ configurationSaved /\ ~configurationDelivered))
    /\ (Scenario = "MissingCoreFallback" =>
        ~(phase = 2 /\ ~coreAlive /\ ~fallbackCalled))

Spec == Init /\ [][Next]_vars

=============================================================================
