# Actor isolation specification checks

Documentation/SPEC.md sections 8.4 and 17.1 own this independent requirements model. Initial inventory is one and two calls target the same actor. The reentrant path reads availability, suspends, then updates using its retained observation. The corrected path checks and updates inside a non-suspending actor-isolated step.

TLC finds the reentrant NoOverselling counterexample. Both calls observe available stock before either update, then both accept and stock becomes -1. The complete trace is in Reentrant.cfg.log. With Atomic=TRUE, TLC explores all four reachable states, generating five states with depth three, and checks NoOverselling and Conservation. Terminal stuttering is allowed and deadlock checking is disabled. No fairness, progress or external-actor claim is made.

Lean 4.35.0 checks reservationConservesCapacity, arbitraryAtomicSchedule and noOverselling for arbitrary natural-number capacities and any number of atomic reservations. A fourth theorem checks every guarded transition in the concrete reentrant trace and its violating final state. The first two theorems use propext, noOverselling uses propext and Quot.sound, and the concrete trace theorem has no axiom dependencies. No admitted proof or native evaluation axiom is used.

The TLA corrected model uses integer stock; its reachable nonnegative stock and accepted counts correspond to the Lean natural-number state. The reentrant trace uses integers in both formalizations. Atomic execution is a requirements assumption about the corrected non-suspending actor interval. These are specification results. They do not establish that Formal can lower Actor SIL or that an implementation has this behavior.

Run `python3 verify.py --toolchain <verified-formal-toolchain>` in this directory. Each checker has a 60-second deadline and TLC uses a fresh extraction/state directory. Retained inputs, outputs and the command are referenced by the whole-project receipt.
