

> What to build next, and why, given the current state of the project.

Current state: the procedural leg rig (`StepsPlanner` + `MechSkeletonDriver`) is substantially working — pelvis driven, torso driven, foot IK placing correctly, gait FSM stepping one foot at a time. ~~The rig is good enough to build on but not yet fully validated, because it has never been seen with real leg geometry.~~

The 3d model is rigged and in game already. Works fine

---

## 1. Port stride oscillator + inertia lean onto the torso bone

This is done already. Good enough for the current version

---

## 2. Get real leg geometry into the rig

done already

---

## 3. Decide the drone design

Mostly done. I'll go back to the design after we have a list of all components of the mech (Motors, engine, lights, cooling system, etc)

---

## 4. Component graph schema design (on paper)

**Why now**: the component graph is the foundation everything else is built on — damage propagation, power routing, the repair loop, the memory system, gait degradation. The longer it waits, the more placeholder assumptions accumulate in other systems. But the right first step is not to start coding it — it's to write the schema on paper, because the current model (`health`, `mass`, `power_consumption/output`, `functionality: float`) is already known to be incomplete.

**The gap**: the Repair doc identifies preferred damage modes — *degraded, intermittent, unstable, overheating, power hungry, misaligned, noisy* — that are qualitatively different failure modes, not just different values of a 0–1 float. A misaligned leg and an overheating leg both have low functionality, but they feel and behave differently. The schema needs to express this before the first node is implemented.

**What to produce**: a written schema — node properties, edge types, propagation rules, and a position on whether damage state is a float + enum, a float + set of flags, or something else. This is a document, not a pull request.

---

## What to skip for now: phase-based gait

Reactive stepping (lift on drift) is working. The asymmetric thresholds and the driven pelvis/torso are carrying much of the weight the old system lacked. Phase-based gait (cadence-driven foot lift, not drift-triggered) is a significant planner rewrite for a feel improvement that may or may not be noticeable once real geometry is in. Revisit this after the rig has been validated against a mesh — what looks like a gait problem might be a geometry or proportion problem.

---

## Priority order

| # | Task | Type | Blocking |
|---|---|---|---|
| 1 | Port stride oscillator + inertia lean to torso | Code | Cockpit feel |
| 2 | Rough leg geometry in Blender, weighted to mk2 skeleton | Art | Rig validation, mech identity |
| 3 | Decide drone: stationary vs. mobile | Design | Drone system build |
| 4 | Component graph schema (written, not coded) | Design | Everything downstream |
