
# Iron Pilgrim — Game Summary

> A mech crossing a dying world, carrying something it doesn't understand, toward a signal it can't explain.

> [!note] Companion doc
> This is the high-level summary. **Worldbuilding.md** holds the detailed story spine — the war, the factions, the cargo's true nature, the reveal — and is authoritative for narrative.

---

## Concept

Iron Pilgrim is a 3D exploration game built in Godot 4. The player **is** the mech — not a pilot inside it but the machine itself: a **silicon-based AI**, damaged and half-amnesiac, that wakes already moving. There is no separate human pilot; the cockpit interior is the character space, and the screens flickering back to life as the mech repairs itself *are* its memory returning. The world is dying. The mech starts broken. The tone is bleak, heavy, slow, and lonely.

The mech is not a war machine — a battered **utility / scout**, built to traverse and to *carry*, with **scavenged light weaponry** picked up out of necessity. It carries one sealed cargo it cannot open or identify; protecting it is the only reason it has been given to care about anything. (What the cargo is — author-side: the last human, an infant — is in **Worldbuilding.md**, and the player must not learn it until the end.)

Target length: **10–20 hours**. This project focuses on mech gameplay as a foundation for a larger game down the line.

**Stack**: Godot 4, GDScript, Jolt physics (default in Godot 4.3+)

---

## References

| Reference | What it contributes |
|---|---|
| Warhammer 40k Dreadnought | The mind *is* the machine — no getting out; it is home, burden, and body |
| Space Engineers | Component-based construction, tactile understanding of your machine |
| Immersive Sims | Systemic freedom, emergent problem solving, no single correct path |
| Elden Ring | Ambiance — ancient, indifferent world, beauty in ruin |
| Ico · BLAME! · Children of Men | Escorting fragile, precious cargo through a hostile, depopulated world; the reveal recontextualises the road |

---

## Narrative & Goal

### What the player is
A damaged AI that *is* a utility mech. It doesn't fully recall what happened — to itself, to the world, or to its own purpose. It remembers procedures (walk, repair, navigate); it doesn't remember meaning. Recovering that meaning is the same loop as repairing itself: certain components are data cores, and restoring them gives back fragments.

### The world
The planet is inhabited almost entirely by **robots**, in warring factions, fighting for reasons that no longer have a clean answer — not to the player, not to the combatants. A scatter of strange, half-wrong **animals** lives here too, indifferent to the war. Humans are gone. The world is exhausted, ruined, slow. None of this arrives as exposition — only the world itself, its ruins and wreckage and faction markings, and recovered data fragments, from which the player assembles a partial picture.

### The Hook
The mech wakes up already moving. It carries a sealed cargo — something it cannot open or identify, labelled only `PAYLOAD — SEALED`, emitting a faint rhythmic pulse its degraded sensors won't resolve. A signal pulses from somewhere ahead. The mech doesn't know what emits it, or why it's compelled to follow it. But it is.

### The Journey
The signal is the north star — a direction, not a map. Everything else — terrain, creatures, robot patrols, structural failure, missing components — is the cost of following it. The player is always oriented toward a goal, and the world constantly forces detours. Those detours are the game. As the mech repairs sensors and progresses, the signal resolves slowly: a direction becomes a shape, a shape becomes a frequency, eventually something almost like a voice or an image. The signal is a slow reveal across the entire game; the cargo is the reveal it builds to.

### The End
The mech reaches the source and delivers the cargo. The container opens. What the cargo was, what the signal was, what happened to this world — the player gets answers, and they recontextualise the journey rather than close it. More questions than before, but the right kind. (The hard beats — is the child still alive after a journey this long; does the mech survive the handoff — are deliberately left open in **Worldbuilding.md**; "bleak, slow, lonely" suggests no clean rescue.)

### The Cargo
A sealed container in the mech's core compartment. Player-facing: a silent mystery, never explained until the end — the player projects meaning onto it. It must be protected; losing or damaging it has consequences. The mech is **constrained in ways the player feels but isn't told** — actions refused for "cargo integrity," never with an explanation. (Author-side truth and reveal discipline: **Worldbuilding.md**.)

---

## Tone & Pacing

- **Slow and contemplative** by default — the world is vast, movement has weight, silence is deliberate
- **No dialogue** — story told through environment, ruins, wreckage, faction markings, creature behaviour, recovered data fragments
- **Tension spikes** are occasional and earned — not a combat game, but pressure exists; when combat happens it is rare, ugly, and costly (scarce charge/ammo, damage cascading through the component graph, a "win" that still left you limping)
- The mech itself is a source of tension: component failures, power rerouting, a limb starting to compensate mid-traverse

---

## Gameplay Loop

1. Follow the signal — it gives direction, not a map
2. The world blocks the path — terrain, creatures, robot patrols, structural gaps the damaged mech can't cross
3. Detour to scavenge — find components, recover data fragments, piece together what happened here
4. Repair and reconfigure — the component graph is a problem-solving tool, not just a health bar; repairing data-core components also recovers memory
5. Return to the path — now able to cross what you couldn't before
6. Repeat, with the signal growing clearer

---

## The World's Inhabitants

### Robots
The warring machines that own this world. Faction markings, wreckage, patrols, the occasional still-functioning unit. Hostile, indifferent, or — rarely and dangerously — *interested in the cargo*. The mech mostly avoids, hides, or, last resort, fights. Hiding a large mech is its own design problem.

### Creatures
- Fantastical — not grounded animals, something stranger
- Some are gigantic
- Behaviour is either **indifferent** or **hostile** — nothing is friendly
- They exist for their own reasons, unrelated to the war; the mech is an intruder in their world
- Avoiding, hiding, or fighting are all valid responses — the mech has weapons but is not a combat machine

---

## The Mech

The mech is not a vehicle — it is home, burden, and means of survival. It is also a *someone*: the player's mind, in a damaged industrial body it only half-remembers.

- Every physical component (engine, wire bundles, actuators, screens, sensors, the data cores that hold its memory) is a node in a **component graph**
- Each component has: health, mass, power consumption/output, and a functionality float (0.0–1.0)
- **Damage propagates** through the graph — severed wires cut power to downstream components
- Component mass feeds into a center-of-mass calculation that drives the stability system
- Built from salvage — components are replaceable and customizable; light weaponry is found and bolted on, with real mass and power cost
- The component graph is the primary systemic layer: power routing, loadout choices, and repair decisions open different approaches to the same obstacle — and recovering certain components recovers memory

### Shape
Proposal, pending the 3D identity tests: a **digitigrade biped "porter"** — chicken-walker legs, hunched, load-bearing, the protected cargo compartment in the chest/belly. Reads as a worker, not a soldier, while staying person-shaped enough that the mech reads as a *someone*. A quadruped is an option only if "low, animal, pack-machine" becomes the desired read. (Rationale: **Worldbuilding.md**.)

---

## Locomotion & Physics

- Chassis: `CharacterBody3D` (kinematic) — owns movement, collision, and the capsule; decides where the mech can physically go
- **Procedural leg rig**: a driven `Node3D` rig parented to the chassis — `Pelvis` → `Torso` → two digitigrade ("chicken-walker") IK legs (`thigh → shin → cannon → foot`). The legs *follow* the chassis; they do not hold the mech up. The cockpit camera and mesh mount on `Torso` so all of it reaches the player. A body-less camera can fake jiggle but not *contact* — the moment the view slides over the rock the player's foot expected to plant on, the illusion breaks.
  - **Gait planner**: world-space foot targets, each PLANTED or STEPPING. A planted foot that drifts past `step_trigger_dist` from its ideal spot (hip socket projected forward by `velocity * step_lead_time`, raycast down to ground) starts a step — lerp old→new over `step_duration` with a `sin(t·π)·step_height` arc; never step both feet at once. Re-plant on large yaw delta so turn-in-place doesn't swivel like a tripod. Foot raycasts must exclude the chassis's own capsule.
  - **Pelvis solve**: `pelvis.y` clamped between leg-hyperextend and leg-fully-compressed from the two foot positions; horizontal position follows the chassis through a spring-damper (the lag *is* the weight); subtle roll/pitch toward the support foot.
  - **Digitigrade IK** per leg: analytic 2-bone solve (law of cosines, forward pole) on `thigh+shin` targeting the *hock* (= `foot` target offset up-and-back by the cannon length, oriented by foot pitch) → the stifle bends forward and the hock falls out pointing back; then `cannon` look-ats from hock to `foot`, and `foot`/`toe` aligns to the ground normal. Deterministic, not iterative — no FABRIK. Bone names are a contract the rig script reads: `thigh.L/R → shin.L/R → cannon.L/R → foot.L/R` (+ optional `toe`); rest pose authored in the digitigrade Z-fold.
  - **Torso/camera**: inertia lean lives on `Torso`, fed by horizontal *and* vertical accel; the camera keeps mouse look plus a dialed-down stride oscillator as high-frequency tremor. The big low-frequency motion comes from the pelvis riding the gait.
- **Stride oscillator** (implemented): a sine wave driven by velocity that parametrizes camera bob and sway, sharpened with `pow()` for footstep contrast. Survives the rig change as the high-frequency layer under the procedural leg motion. Damaged leg components warp amplitude/frequency or introduce asymmetry (limp).
- Leg components expose `functionality: float`; the gait planner reads it to degrade feel — longer steps, lower lift, limp asymmetry, a knee that won't fully straighten
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — landing must feel weighty
- **Active ragdoll** (`PhysicalBone3D` + joint motors chasing the procedural target pose) is a documented **phase 2** — the rig's target pose is exactly what the motors need as a drive target, so phase-1 work isn't throwaway. Not started; requires reworking parts of the movement/collision model.

---

## Camera & Perspective

All views are **diegetic** — the player only ever sees what the mech can see.

| View | Description |
|---|---|
| **Cockpit (primary)** | First-person interior, mounted on the procedural rig's `Torso` — where the player lives; the gait → pelvis → torso chain drives camera feel, with bob layered on top |
| **Sensor cluster** | Head rotates for situational awareness (arc-limited); damage narrows FOV |
| **Drone** | Stationary workshop camera — deploy it, it stays put; used for repair, upgrade, and inspection; the rig stands and the mech plays an idle clip on top |

No free third-person camera. The drone is a workshop tool, not a spectator camera — the mech does not walk while the drone is active.

---

## UI

Fully **diegetic** — no HUD.

- Cockpit screens are `SubViewport` nodes rendered onto 3D meshes inside the cockpit
- A damaged screen goes dark or shows static — the information is physically lost
- Signal tracking, maps, component graphs, cargo status — all on physical screens the player looks at

---

## Art Direction

Unresolved — needs testing in Blender and Godot before committing to a direction. Mech-identity tests (scale, silhouette, cockpit framing, biped vs. quad) are the immediate exploratory step, before the procedural leg rig is built.

---

## Key Systems

| System | Status | Notes |
|---|---|---|
| Component graph | Not started | Core of everything — build first |
| Cockpit camera + stride oscillator | Prototyped | Body-less camera feel; the floor it set, not the ceiling |
| Procedural leg rig | Not started | Driven pelvis/torso/2-bone-IK legs on the kinematic chassis; camera on the torso; validate mech identity first |
| Mech mesh + idle animation | Not started | Leg geometry the rig can drive; idle layered on the standing pose |
| Drone view | Not started | Stationary workshop camera; repair/upgrade UI |
| Physics handoff | Not started | Kinematic ↔ RigidBody on falls/impacts |
| Diegetic UI (screens) | Not started | SubViewport on mesh |
| World / scavenging | Not started | After core mech systems are solid |
| Creatures + robot factions | Not started | After world exists |
| Active ragdoll | Phase 2 | Deferred; motors chase the procedural target pose |

---

## Scope Guards

- No free third-person camera — drone is the only external view and it is diegetic
- No human pilot model or animation — there isn't one; the mech is the character. (The cargo, revealed at the end, is the only human and is not a playable or character-animated figure.)
- No traditional HUD — screens only
- Leg IK is analytic 2-bone (solving `thigh+shin` to the hock) plus a deterministic `cannon`/`foot` solve — no FABRIK, no iterative solvers, no full-skeleton retarget IK rigs. All biped mechs share the digitigrade topology; a humanoid/plantigrade or quadruped variant would be a separate rig script
- No baked walk cycle — the mech's gait is procedural (gait planner + IK); a baked *idle* clip may layer micro-movement on top. The drone is a workshop tool, not a spectator camera
- No full active ragdoll yet — kinematic chassis + driven procedural rig now; `PhysicalBone3D` active ragdoll is a documented phase 2, plus the impact→`RigidBody3D` handoff
- Combat stays rare, ugly, and costly — not a shooter; the mech is a utility machine, not a war machine
- World and creature systems come after component graph and cockpit are solid
- This version focuses on mech gameplay — narrative and world depth scale up in the larger project later
