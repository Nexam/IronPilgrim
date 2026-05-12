# Iron Pilgrim — CLAUDE.md

## Project

3D exploration game in Godot 4. The player **is** the mech — not a pilot inside it but the machine itself: a damaged, half-amnesiac silicon AI carrying one sealed cargo (the last human — an infant) toward safety across a dying world of warring robots and stranger creatures. Not a war mech — a battered utility/scout machine with scavenged light weaponry. Story is told through the world and a final reveal (the cargo); no HUD, no third-person camera, no human pilot. Tone: bleak, slow, lonely. See `iron-pilgrim-gdd/Worldbuilding.md` for the full story spine.

**Stack**: Godot 4 · GDScript · Jolt physics (default in Godot 4.3+)

**Repository layout**:
- `iron-pilgrim-game/` — Godot project
- `iron-pilgrim-gdd/` — design documents

---

## Build Order

Work in this sequence. Do not start a later system until the earlier ones are solid.

1. **Component graph** — data schema first, propagation logic second
2. **Cockpit camera + stride oscillator** — movement feel before anything else *(done)*
3. **Procedural leg rig** *(in progress)* — `MechDigitigradeRig` (`scripts/mech_digitigrade_rig.gd`, a `SkeletonModifier3D`) driving the imported skeleton on the kinematic chassis; two digitigrade ("chicken-walker") IK legs. This is the answer to "is body-less camera bob enough?" — it isn't.
   - **Step 1 (done)**: foot-lock IK — feet raycast to ground, legs articulate as the chassis moves over terrain; debug spheres at hip/knee/hock/contact (`debug_draw`). Pelvis untouched; camera still rides the Skeleton3D node via the `torso` mesh.
   - **Next**: confirm it stands/articulates on the dev ramp → gait FSM (foot targets, step trigger, alternation, yaw re-plant) → pelvis solve + move the cockpit camera onto a `BoneAttachment3D` (needs a `torso` bone added in Blender) → port inertia lean / dialed-down oscillator onto the torso.
   - Validate mech identity (scale, silhouette, cockpit framing) and tune the gait before moving on.
4. **Mech mesh + idle animation** — leg geometry the procedural rig can drive; idle micro-movement layered on top of the standing pose; only needs to look right at rest
5. **Drone view** — stationary workshop camera, repair/upgrade UI
6. **World / scavenging** — after core mech systems are solid
7. **Creatures** — after world exists

---

## Core Systems

### Component Graph
- Every physical part of the mech (engine, actuators, wire bundles, sensors, screens) is a node in a directed graph
- Each component: `health`, `mass`, `power_consumption` / `power_output`, `functionality: float` (0.0–1.0)
- Damage propagates — severed wires cut power to downstream nodes
- Component mass feeds CoM calculation for the stability system
- Components are salvageable and replaceable; loadout choices open different approaches to obstacles

### Locomotion & Physics
- Chassis: `CharacterBody3D` (kinematic) — owns movement, collision, and the capsule; decides where the mech can physically go. Unchanged by the rig work below.
- **Procedural leg rig** (in progress — `MechDigitigradeRig`, a `SkeletonModifier3D` on the imported skeleton): drives the `pelvis` + two digitigrade IK legs (`thigh → shin → cannon → foot`; the blockout armature has the `tigh` typo and no `torso` bone yet — the cockpit camera currently rides the Skeleton3D node via the `torso` *mesh*, to be moved onto a `BoneAttachment3D` once a `torso` bone exists). The legs *follow* the chassis; they do not hold the mech up. Rationale: a body-less camera can fake jiggle but not contact — the moment the view slides over a rock the player's foot expected to plant on, the illusion breaks. Runs in `_process_modification()`; set the Skeleton3D's `modifier_callback_mode_process` to Physics so it stays in lockstep with the chassis.
  - **`foot_height` export** (`mech_digitigrade_rig.gd`): lifts the cannon target above the raw raycast contact by the foot joint's height above the sole. The foot bone sits at the joint, not the ground; this offset reconciles the two. Tune per mech.
  - **Gait planner**: world-space foot targets, each PLANTED or STEPPING. A planted foot that drifts past `step_trigger_dist` from its ideal spot (hip socket projected forward by `velocity * step_lead_time`, raycast down to ground) starts a step — lerp old→new over `step_duration` with a `sin(t·π)·step_height` arc; never step both feet at once. Re-plant on large yaw delta so turn-in-place doesn't swivel like a tripod. Foot raycasts must exclude the chassis's own capsule.
  - **Pelvis solve**: `pelvis.y` clamped between leg-hyperextend and leg-fully-compressed from the two foot positions; horizontal position follows the chassis through a spring-damper (the lag *is* the weight); subtle roll/pitch toward the support foot.
  - **Digitigrade IK** per leg: analytic 2-bone solve (law of cosines, forward pole) on `thigh+shin` targeting the *hock* (= `foot` target offset up-and-back by the cannon length, oriented by foot pitch) → the stifle bends forward and the hock falls out pointing back; then `cannon` look-ats from hock to `foot`, and `foot`/`toe` aligns to the ground normal. Deterministic, not iterative — no FABRIK.
  - **Torso/camera**: inertia lean moves onto `Torso`, fed by horizontal *and* vertical accel; camera keeps mouse look plus a dialed-down stride oscillator as high-freq tremor. The big low-freq motion now comes from the pelvis riding the gait.
- **Stride oscillator** (implemented): sine wave driven by velocity; drives camera bob (`bob_amplitude_y`) and sway (`bob_amplitude_x`); sharpened with `pow()` for footstep contrast. Survives the rig change as the high-freq layer under the procedural leg motion.
- **Inertia lean** (implemented, needs tuning): pitch slightly forward when climbing, back when descending — derived from frame-to-frame Y position delta, not velocity.y. Migrates from the camera to `Torso` when the rig lands.
- **Active ragdoll — phase 2, deferred**: `PhysicalBone3D` chain + joint motors chasing the procedural target pose, for emergent balance / stumble / recovery (the "damaged mech" fantasy felt in the body, not read on a screen). The procedural rig's target pose is exactly what the motors need as a drive target, so phase-1 work isn't throwaway. Requires reworking parts of the movement/collision model — not started.
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — still planned
- Leg components expose `functionality: float`; the gait planner reads it to degrade feel — longer `step_duration`, lower `step_height`, more limp asymmetry, a knee that won't fully straighten

### Mech Variants & Rig
The player mech is one of many — patrol units, faction mechs, others fighting in the background — so the rig must generalise from day one.
- **Skeleton in Blender, driven in Godot**: bones, hierarchy, rest pose, vertex weights live in the `.glb`; IK / gait / pelvis solve is a `SkeletonModifier3D` subclass writing bone poses in `_process_modification()` (segment lengths are read from the rest pose, so the rig adapts to any mech using the same bone names). No Blender IK constraints, no baked walk clip (idle only, later).
- **Bone naming is a contract** — the rig script looks bones up by name: `pelvis` (root) → `torso` (+ optional `head`); `thigh.L/R` → `shin.L/R` → `cannon.L/R` → `foot.L/R` (+ optional `toe.L/R`). `cannon` is the metatarsal segment between hock and toe. Author the rest pose in the digitigrade Z-fold — thigh down-forward, shin down-back, cannon down-forward to the ground, foot flat, stifle clearly bent forward; that rest pose *is* the IK pole hint and the default standing pose. *Current blockout armature*: `pelvis` + `tigh.L/R → shin.L/R → cannon.L/R → foot.L/R` — no `torso`/`head` bone yet, and `tigh` is a typo (`thigh` intended); `mech_digitigrade_rig.gd` accepts either spelling, fix on the next re-export.
- **Same topology across all biped mechs**: one rig script (`mech_digitigrade_rig.gd` / `MechDigitigradeRig`) drives every biped. Variation will live in a `MechConfig` resource (`@export`s for leg length, hip width, step parameters, mass, top speed, mount points); for now those are `@export`s straight on the rig. New mech = new mesh + new config, not a new script.
- **Scene layout**: the mech is split into `scenes/mech_rigged.tscn` (the `.glb` instance + `MechDigitigradeRig` + foot raycasts) and the `CharacterBody3D` in the level scene. `scripts/mech_config.gd` (`MechConfig`, a `Node3D`) is the glue — it holds references to `chassis`, `rig`, and `camera`, and wires `rig.chassis` in `_ready()`. The chassis sets `mech_config = NodePath("mech-rigged")` and pulls the camera from `mech_config.camera`.
- **Blender origin convention**: armature origin must be at foot-sole level in the rest pose (Y=0 = ground contact). This ensures the Skeleton3D sits at the correct height above the terrain in Godot with no manual Y offset needed.
- **Controller is swappable**: `PlayerController` reads input, `AIController` produces target velocity/facing — both feed the same chassis + rig.
- **All biped mechs are digitigrade** — one topology for the whole mech population. A humanoid/plantigrade war-mech, or a quadruped/animal mech, would be a *separate* rig script (different chain or gait pattern, not a config tweak). Share the analytic IK and foot-raycast as utilities; don't write one rig that does all of them.
- **Component graph fidelity scales with role**: player mech has a full salvageable graph; NPC mechs use a stripped-down version (legs, sensors, weapons, core — each with `functionality`) so damage propagates without authoring hundreds of components per unit.
- The player's silhouette (hunched porter, chest cargo bulge) is the visual identity that keeps it distinct from patrol units sharing the same topology.

### Drone View & Mech Mesh
- Drone is a **stationary workshop tool** — deploy it, it stays put; used for repair, upgrade, and inspection
- The mech mesh needs leg geometry the procedural rig can drive; the *visible body* still only needs to look correct **at rest** for the drone view — no baked walk clip
- **Idle animation** layers on top of the rig's standing pose: subtle hydraulic micro-movements, weight shifts, a damaged limb hanging slightly wrong
- Idle animation can reflect damage state (a broken limb hangs differently) on top of the rig — separate from the gait planner's degradation

### Camera & Perspective
All views are diegetic — the player only sees what the mech can see.

| View | Mechanic | Animation |
|---|---|---|
| Cockpit (primary) | First-person interior; mounted on the procedural rig's `Torso` | Procedural leg rig (gait → pelvis → torso); camera bob layered on top |
| Sensor cluster | Head rotates for situational awareness; damage narrows FOV | Arc rotation only |
| Drone | Stationary workshop camera; deploy and it stays put | Procedural rig stands; mech plays idle clip on top |

### UI
Fully diegetic — no HUD overlays.
- Cockpit screens are `SubViewport` nodes rendered onto 3D meshes inside the cockpit
- A damaged screen goes dark or shows static — information is physically lost
- Signal tracking, maps, component graph, cargo status — all on physical cockpit screens

---

## Scope Guards

These are hard constraints — do not work around them:

- No free third-person camera (drone is the only external view, and it is diegetic)
- No human pilot model or character animation
- No HUD — screens only
- Leg IK is analytic 2-bone (solving `thigh+shin` to the hock) plus a deterministic `cannon`/`foot` solve — no FABRIK, no iterative solvers, no full-skeleton retarget IK rigs
- No baked walk cycle — the mech's gait is procedural (gait planner + IK); a baked *idle* clip may layer micro-movement on top. Drone view is still a workshop tool, not a spectator camera
- No full active ragdoll yet — kinematic chassis + driven procedural rig now; `PhysicalBone3D` active ragdoll is a documented phase 2, plus the impact→`RigidBody3D` handoff
- Combat stays rare, ugly, and costly — not a shooter; the mech is a utility machine, not a war machine
- World and creature systems wait until component graph and cockpit are solid
- The story spine is set (`iron-pilgrim-gdd/Worldbuilding.md`); narrative *depth* and world detail are still deferred to the larger project later

---

## GDScript Conventions

- Snake_case for variables and functions, PascalCase for classes/nodes
- Prefer `@export` over direct node path strings where possible
- Keep physics logic out of `_process`; use `_physics_process` for anything touching `CharacterBody3D` or forces
- Component graph nodes should be loosely coupled — communicate via signals, not direct references where possible
