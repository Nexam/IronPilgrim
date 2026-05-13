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
   - **Done**: foot-lock IK (feet raycast to ground, legs articulate as the chassis moves; debug spheres at hip/knee/hock/contact via `debug_draw`) + gait FSM (world-space foot targets, distance-threshold step trigger with a min-interval lockout, one foot at a time, yaw re-plant) + the mk2 skeleton (`mech-mk2-rigged.glb` — hips/torso split, hip ball joint, universal-joint ankle; see the bone contract below) + cockpit camera on a `BoneAttachment3D` bound to the `torso` bone.
   - **Known gaps in the current rig** (next-pass work): `thigh`/`shin` aren't yet true 1-DOF hinges — `_aim_bone` writes a full +Y aim and only roughly preserves roll, so `thigh` still behaves like a ball joint; the `thigh_roll` ball joint is held at its rest orientation (no abduction yet); feet plant straight under the hip sockets (no stance-width offset, so the stance is narrower than the rest pose); `cannon` pitch is derived from leg extension but the curve constants are hard-coded; the `torso` bone isn't driven yet (camera rides it at rest).
   - **Next**: per-joint constraint pass (make `thigh`/`shin`/`cannon`/ankle true hinges about their authored axes, with angle limits; `thigh_roll` cone+twist) → pelvis solve (height clamp from foot positions, spring-lag horizontal follow, support-foot roll/pitch) → drive the `torso` bone (inertia lean) + port the dialed-down oscillator onto it → gait-feel tuning (forward stride bias, separate Z/X trigger box, `thigh_roll` abduction for stance width) and authoring tooling (`@tool` + live debug draw of trigger box / neutral foot / swing arc; gait+leg params into a `MechConfig` resource).
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
- **Procedural leg rig** (in progress — `MechDigitigradeRig`, a `SkeletonModifier3D` on the imported skeleton): drives two digitigrade IK legs on the mk2 skeleton (bone contract below). The legs *follow* the chassis; they do not hold the mech up. Rationale: a body-less camera can fake jiggle but not contact — the moment the view slides over a rock the player's foot expected to plant on, the illusion breaks. Runs in `_process_modification()`; the Skeleton3D's `modifier_callback_mode_process` is set to Physics so it stays in lockstep with the chassis. `_aim_bone` rotates a bone's local +Y toward a target while keeping its rest *position* (joints don't slide — bones rotate) and roughly preserving roll; making the leg bones true single-axis hinges (so `thigh` stops behaving like a ball joint) is pending.
  - **`foot_height` export** (`mech_digitigrade_rig.gd`): the ankle joint sits above the sole by this much (the foot is a short vertical peg); the ankle target = `contact + ground_normal * foot_height`. Tune per mech.
  - **Gait planner**: world-space foot targets, each PLANTED or STEPPING. A planted foot that drifts past `step_trigger_dist` from its ideal spot (hip *socket* — `thigh`'s origin — projected forward by `velocity * step_lead_time`, raycast down to ground) starts a step — lerp old→new over `step_duration` with a `sin(t·π)·step_height` arc; never step both feet at once, with a `step_min_interval` lockout; re-plant on a `yaw_replant_deg` delta so turn-in-place doesn't swivel like a tripod. Foot raycasts must exclude the chassis's own capsule (the capsule is on collision layer 2, the rays mask it out). Wall-clock delta via `Time.get_ticks_usec` (the modifier callback gets no delta and may fire off-frame). Not yet: forward stride bias, separate Z/X trigger box.
  - **Pelvis solve** (not started): `pelvis.y` clamped between leg-hyperextend and leg-fully-compressed from the two foot positions; horizontal position follows the chassis through a spring-damper (the lag *is* the weight); subtle roll/pitch toward the support foot.
  - **Digitigrade IK** per leg: `thigh_roll` (the hip ball joint) is held at its rest orientation for now; `cannon` pitch is derived — `lerp(cannon_pitch_folded, cannon_pitch_extended, reach_ratio)` so the stride keeps its length (folded under the body, straighter when reaching) — and the hock is `ankle_joint` offset up-and-back from it by the cannon length; analytic 2-bone solve (law of cosines, forward pole) on `thigh+shin` from the hip socket to the hock → the stifle bends forward; `cannon` look-ats from hock to the ankle joint; `ankle_pitch` and `ankle_roll` both aim down at the contact point (rest orientation on flat ground, tilts to the surface on a slope — a proper pitch/roll split for terrain conform comes with the constraint pass). Deterministic, not iterative — no FABRIK.
  - **Torso/camera**: inertia lean moves onto the `torso` bone (currently undriven; camera rides it at rest via a `BoneAttachment3D`), fed by horizontal *and* vertical accel; camera keeps mouse look plus a dialed-down stride oscillator as high-freq tremor. The big low-freq motion will come from the pelvis riding the gait. Once the camera rides the driven `torso`, decide the look split: mouse yaw turns the `torso` bone within a range, then turns the whole chassis past it.
- **Stride oscillator** (implemented): sine wave driven by velocity; drives camera bob (`bob_amplitude_y`) and sway (`bob_amplitude_x`); sharpened with `pow()` for footstep contrast. Survives the rig change as the high-freq layer under the procedural leg motion.
- **Inertia lean** (implemented, needs tuning): pitch slightly forward when climbing, back when descending — derived from frame-to-frame Y position delta, not velocity.y. Migrates from the camera to `Torso` when the rig lands.
- **Active ragdoll — phase 2, deferred**: `PhysicalBone3D` chain + joint motors chasing the procedural target pose, for emergent balance / stumble / recovery (the "damaged mech" fantasy felt in the body, not read on a screen). The procedural rig's target pose is exactly what the motors need as a drive target, so phase-1 work isn't throwaway. Requires reworking parts of the movement/collision model — not started.
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — still planned
- Leg components expose `functionality: float`; the gait planner reads it to degrade feel — longer `step_duration`, lower `step_height`, more limp asymmetry, a knee that won't fully straighten

### Mech Variants & Rig
The player mech is one of many — patrol units, faction mechs, others fighting in the background — so the rig must generalise from day one.
- **Skeleton in Blender, driven in Godot**: bones, hierarchy, rest pose, vertex weights live in the `.glb`; IK / gait / pelvis solve is a `SkeletonModifier3D` subclass writing bone poses in `_process_modification()` (segment lengths are read from the rest pose, so the rig adapts to any mech using the same bone names). Godot does not import Blender IK constraints / control rigs — only the deform skeleton + (optionally) baked clips — so any terrain-reactive leg motion *has* to be solved at runtime in Godot regardless. No Blender IK constraints, no baked walk clip (Blender IK is the right tool for the *idle* clip only — pose it there, bake it, layer it on top later).
- **Bone naming is a contract** — the rig script looks bones up by name. Current mk2 skeleton (`mech-mk2-rigged.glb`): `ground` (root) → `pelvis` → `torso`; per leg `thigh_roll.L/R` → `thigh.L/R` → `shin.L/R` → `cannon.L/R` → `ankle_pitch.L/R` → `ankle_roll.L/R`. Joint roles: `thigh_roll` = the hip **ball joint** (short ~horizontal stub from the pelvis out to the hip socket; held at rest for now, will carry abduction); `thigh` + `shin` = the two **pitch hinges** (the 2-bone analytic IK pair — `thigh` is the femur, `shin` the knee, bending forward in the sagittal plane); `cannon` = the metatarsal **pitch hinge** (derived pitch); `ankle_pitch` + `ankle_roll` = a **universal-joint** ankle / short foot peg (rest +Y points straight down — the foot is a vertical stub, not a forward foot; no `toe` bone). Author the rest pose in the digitigrade Z-fold — thigh down-forward, shin down-back, cannon down-forward to the ground, stifle clearly bent forward; that rest pose *is* the IK pole hint and the default standing pose. Each hinge bone's local axes must line up with its intended rotation axis (matters once joint limits land). Origin convention below. The armature node is `mech_armature`. (The earlier blockout — `mech-rigged.glb`, `scenes/mech_rigged.tscn` — used `pelvis` (root) + `tigh.L/R → shin.L/R → cannon.L/R → foot.L/R` with no `torso`; superseded by mk2.)
- **Same topology across all biped mechs**: one rig script (`mech_digitigrade_rig.gd` / `MechDigitigradeRig`) drives every biped. Variation will live in a `MechConfig` resource (`@export`s for leg length, hip width, step parameters, mass, top speed, mount points); for now those are `@export`s straight on the rig. New mech = new mesh + new config, not a new script.
- **Scene layout**: the mech is split into `scenes/mech_mk_2_rigged.tscn` (the `.glb` instance with `MechConfig` on the root + `MechDigitigradeRig` on `mech_armature/Skeleton3D` + two foot `RayCast3D`s + a `BoneAttachment3D` on the Skeleton3D bound to the `torso` bone carrying the cockpit `Camera3D`) and the `CharacterBody3D` in the level scene. `scripts/mech_config.gd` (`MechConfig`, a `Node3D`) is the glue — it holds references to `chassis`, `rig`, and `camera`, and wires `rig.chassis` in `_ready()`. The chassis sets `mech_config = NodePath("mech-mk2-rigged")` and pulls the camera from `mech_config.camera`. The body mesh is on render layer 2 with the camera's `cull_mask` excluding it (so you don't see the inside of your own hull). In `dev_walk.tscn` the mech node carries a 180° Y rotation so the model faces chassis-forward; `knee_pole = FORWARD` is correct given that — flip if the orientation changes.
- **Blender origin convention**: armature origin must be at foot-sole level in the rest pose (Y=0 = ground contact). This ensures the Skeleton3D sits at the correct height above the terrain in Godot with no manual Y offset needed. Apply all transforms on the armature on export (no import-scale fudge).
- **Controller is swappable**: `PlayerController` reads input, `AIController` produces target velocity/facing — both feed the same chassis + rig.
- **All biped mechs are digitigrade** — one topology for the whole mech population (one rig script, variation via `MechConfig`). Variety in the mech population comes from **drones** (floating workshop tool + sensor gimbal — no gait) and possibly **wheeled vehicles** (spinning wheels + suspension travel, kept kinematic like the mech chassis), not from different leg topologies. A humanoid/plantigrade war-mech or a quadruped/animal mech would be a *separate* rig script (different chain or gait pattern, not a config tweak) — but the intent is to *not* build those; share the analytic IK and foot-raycast as utilities if it ever happens.
- **Joints are single-axis hinges** (it's a mech, not a creature): the leg chain is revolute hinges (`thigh`, `shin`, `cannon`, the ankle bones) plus a ball joint at the hip (`thigh_roll`) — a textbook robot leg. Hinges make per-joint angle limits a trivial scalar min/max; a free quaternion joint needs swing-twist decomposition. The rig doesn't *enforce* the single-axis constraint yet (see the leg-rig gaps in the Build Order) — that's the constraint pass. Foot yaw is not a joint; turn-in-place re-plants the feet instead.
- **Secondary-detail bones live outside the rig contract**: the leg solver looks up only the named leg/body bones and ignores everything else, so adding decoration never touches the gait. Planned (deferred) naming convention — **pistons**: `piston.<id>.a` / `piston.<id>.b` (a `SkeletonModifier3D` that makes the pair mutually look-at each other, passive); **cables/hoses**: a bone chain `cable.<id>.0 … .N` driven by a verlet pass in its own modifier. The `<id>` is the hook a component-graph node would reference later (severed cable goes slack, jammed piston freezes).
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
