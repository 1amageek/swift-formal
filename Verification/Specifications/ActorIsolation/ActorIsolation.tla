------------------------ MODULE ActorIsolation ------------------------
EXTENDS Integers
CONSTANT Atomic
Tasks == {1, 2}
VARIABLES stock, accepted, pc, observed
vars == <<stock, accepted, pc, observed>>

\* Documentation/SPEC.md 8.4 and 17.1: one actor, two reservations,
\* initial inventory one. Atomic selects the corrected non-suspending path.
Init == /\ stock = 1
        /\ accepted = 0
        /\ pc = [t \in Tasks |-> "start"]
        /\ observed = [t \in Tasks |-> FALSE]

CheckAndSuspend(t) == /\ ~Atomic /\ pc[t] = "start"
                      /\ observed' = [observed EXCEPT ![t] = stock > 0]
                      /\ pc' = [pc EXCEPT ![t] = "resume"]
                      /\ UNCHANGED <<stock, accepted>>

Resume(t) == /\ ~Atomic /\ pc[t] = "resume"
             /\ stock' = IF observed[t] THEN stock - 1 ELSE stock
             /\ accepted' = IF observed[t] THEN accepted + 1 ELSE accepted
             /\ pc' = [pc EXCEPT ![t] = "done"]
             /\ UNCHANGED observed

ReserveWithoutSuspension(t) == /\ Atomic /\ pc[t] = "start"
                               /\ stock' = IF stock > 0 THEN stock - 1 ELSE stock
                               /\ accepted' = IF stock > 0 THEN accepted + 1 ELSE accepted
                               /\ pc' = [pc EXCEPT ![t] = "done"]
                               /\ UNCHANGED observed

Next == \E t \in Tasks: CheckAndSuspend(t) \/ Resume(t) \/ ReserveWithoutSuspension(t)
Spec == Init /\ [][Next]_vars
NoOverselling == stock >= 0 /\ accepted <= 1
Conservation == stock + accepted = 1
======================================================================
