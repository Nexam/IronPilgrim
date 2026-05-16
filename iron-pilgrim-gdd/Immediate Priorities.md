# Iron Pilgrim — Immediate Priorities

> What to build next, and why, given the current state of the project.

Current state: the procedural leg rig (`StepsPlanner` + `MechSkeletonDriver`) is substantially working — pelvis driven, torso driven, foot IK placing correctly, gait FSM stepping one foot at a time. The rig is good enough to build on but not yet fully validated, because it has never been seen with real leg geometry.

---

## 1. Port stride oscillator + inertia lean onto the torso bone

**Why now**: These systems existed and were working in the previous rig. The torso bone was always their intended home — they were just waiting for the bone to be driven. It is now. This is a short, bounded task with no new design decisions, and the cockpit view is currently missing its high-frequency tremor layer: the body moves correctly at the macro scale (pelvis riding the gait) but the camera has no footstep sharpness on top.

**What it is**: a sine wave driven by velocity parametrizing camera bob and sway (sharpened with `pow()` for footstep contrast) plus a pitch lean derived from frame-to-frame Y delta. Both live on the torso node or feed into it — the camera inherits the result via the BoneAttachment3D.

**Skip**: rebuilding the oscillator from scratch. Port what worked.

---

## 2. Get real leg geometry into the rig

**Why now**: debug spheres confirm the IK math is correct. Mesh confirms the legs *look* correct. These are different tests. The gait feel, stance width, foot placement, pelvis height, knee travel, and cannon angle all read very differently once there's actual geometry on the bones — what looks fine in wireframe often reveals proportion problems or joint rotation issues when you see shins and ankles.

This is the "validate mech identity" gate the build order has been deferring. It must happen before the rig is considered done, and it should happen before investing further in gait tuning — because what looks wrong might be a geometry problem, not a code problem.

**What's needed**: a rough Blender pass — actual tube/box geometry for thigh, shin, cannon, foot in the digitigrade Z-fold rest pose, vertex-weighted to the existing mk2 skeleton. It does not need to be the final mesh. It needs to be close enough in proportion that the silhouette reads correctly and the IK deformation is visible.

**Unlock**: once you can see the rig with geometry, you know what still needs fixing before moving on to mech mesh + idle animation properly.

---

## 3. Decide the drone design

**Why now**: the drone is blocked on a design decision that has been ambiguous across two documents. Resolving it costs nothing and unblocks the design work needed before the system gets built.

**The tension**: Overview.md and CLAUDE.md call the drone a stationary workshop tool — deploy it, it stays put, the mech stands idle while you use it. The Repair doc describes a light, nimble flying unit that physically moves around the mech, scouts locally, and can be permanently lost and replaced with found units of varying condition and quirks.

**The stakes**: these are meaningfully different in scope and feel. The mobile version is richer — it makes the drone a character in its own right (attachment, loss, imperfect replacements) and allows for interesting spatial repair puzzles. The stationary version is simpler and keeps the mech as the unambiguous center of all gameplay. Both are compatible with the scope guard ("avoid drone replacing mech gameplay").

**Suggested resolution to pressure-test**: the drone is mobile but *short-range and battery-limited*. It never becomes an exploration vehicle because it can't go far and can't stay out long. The mech is still the traveler; the drone is the maintenance hand. This gets you the character depth (loss, replacement, quirks) without the drone becoming a parallel game. But this is a design call, not a code call — decide it before the system enters the build queue.

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
