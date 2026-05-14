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
3. **Procedural leg rig** *(on hold — explored, walks but doesn't feel believable; a different approach is being tried next)* — `MechDigitigradeRig` (`scripts/mech_digitigrade_rig.gd`, a `SkeletonModifier3D`) driving the imported skeleton on the kinematic chassis; two digitigrade ("chicken-walker") IK legs. Started from the premise that body-less camera bob isn't enough — the moment the view slides past a rock the foot expected to plant on, the illusion breaks.
   - **Skeleton (mk2)**: `mech-mk2-rigged.glb` — `ground` (root) → `pelvis` → `torso`; per leg `thigh.L/R → shin.L/R → cannon.L/R → foot.L/R`. The `ground` bone carries the rest 180° Y rotation so the imported model faces chassis-forward (-Z) **without** any scene-level rotation on the mech node. Earlier iterations split the hip into a `thigh_roll` ball + `thigh` hinge and the ankle into `ankle_pitch` + `ankle_roll`; both were collapsed back into single ball joints to simplify authoring and IK.
   - **Done**: foot-lock IK (feet raycast to ground, legs articulate as the chassis moves; debug spheres at hip/knee/hock/contact via `debug_draw`) + gait FSM (world-space foot targets, distance-threshold step trigger with a min-interval lockout, one foot at a time, yaw re-plant) + plane-constrained 2-bone analytic IK (`_solve_two_bone_plane`, knee held at the hock's X so the thigh has no yaw on straight stride and yaws naturally on strafing) + per-bone aim helpers (`_aim_bone_cone` for `thigh` and `foot` ball joints with cone safety-nets, `_aim_bone_hinge` for `shin` and `cannon` single-axis hinges) + horizontal `foot` bone aimed along chassis-forward projected onto the ground (lies flat on slopes) + the gait planner anchored on the **foot bone's rest world position** (not the hip) so the IK targets the rest stance width + cockpit camera on a `BoneAttachment3D` bound to the `torso` bone.
   - **Why it stops feeling believable** (the reasons we're trying something else):
     - **Pelvis isn't driven.** The body is a rigid pole above the hip — no vertical bob, no spring-lag horizontal follow, no roll toward the support foot. The chassis's `velocity` is set by `move_and_slide` independently of the gait, so the body glides at constant speed through stance: legs decorate, body doesn't carry the weight.
     - **Cannon's derived hock target doesn't match the rest hock.** `cannon_pitch_folded`/`extended` (55°/15°) interpolated against leg extension lands ~30° off the rest pose's actual cannon pitch at idle, so the cannon hinge sits visibly rotated from rest even when standing still.
     - **Stepping is reactive, not phase-based.** Lift-on-drift means the legs catch up to the body instead of driving it.
     - **`torso` bone is undriven.** Camera rides it at rest; inertia lean + the dialed-down stride oscillator are waiting on the bone being posed.
   - **What would resume this approach**: pelvis solve (height clamp from foot positions, spring-lag horizontal follow, support-foot roll/pitch) → drive the `torso` bone (inertia lean) and port the dialed-down oscillator onto it → re-derive `cannon_pitch_folded/extended` from the rest pose instead of hand-tuning → phase-based gait (cadence-driven foot lift, not drift-driven) → authoring tooling (`@tool` + live debug draw of trigger box / neutral foot / swing arc).
   - Validate mech identity (scale, silhouette, cockpit framing) and gait feel before moving on. The current rig stays in tree as the fallback / reference while the alternative is tried.
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
- **Procedural leg rig** (on hold — see Build Order #3): `MechDigitigradeRig`, a `SkeletonModifier3D` on the imported skeleton. Drives two digitigrade IK legs on the mk2 skeleton (bone contract below). The legs *follow* the chassis; they do not hold the mech up. Runs in `_process_modification()`; the Skeleton3D's `modifier_callback_mode_process` is set to Physics so it stays in lockstep with the chassis. Wall-clock delta via `Time.get_ticks_usec` (the modifier callback gets no delta and may fire off-frame).
  - **`foot_height` export** (`mech_digitigrade_rig.gd`): distance from the foot bone's sole to its head (the bone is horizontal, head at the ankle joint). `ankle_joint = contact + ground_normal * foot_height`. Tune per mech.
  - **Gait planner**: world-space foot targets, each PLANTED or STEPPING. A planted foot drifting past `step_trigger_dist` from its ideal spot starts a step — lerp old→new over `step_duration` with a `sin(t·π)·step_height` arc; never step both feet at once, `step_min_interval` lockout; re-plant on a `yaw_replant_deg` delta so turn-in-place doesn't swivel like a tripod. The **ideal spot is anchored on the foot bone's rest world position** (projected forward by `velocity * step_lead_time`, raycast down to ground), not the hip — using the hip collapses the stance because the rest pose fans the legs outward. Foot raycasts exclude the chassis capsule via a collision-layer exception (the capsule is on layer 2). Stepping is reactive (lift on drift) — not yet phase-based.
  - **Pelvis solve** (not started): `pelvis.y` clamped between leg-hyperextend and leg-fully-compressed from the two foot positions; horizontal position follows the chassis through a spring-damper (the lag *is* the weight); subtle roll/pitch toward the support foot. **This is the largest single source of "doesn't feel natural" in the current rig** — the body is a rigid pole above the hip, the chassis glides at constant velocity from `move_and_slide`, the legs decorate it.
  - **Per-leg IK** (one chain, mixed joint types — deterministic, not iterative, no FABRIK):
    - Derive the **hock** from the foot raycast: `ankle_joint = contact + ground_normal * foot_height`; then `hock = ankle_joint + (up*cos(pitch) + rearward*sin(pitch)) * len_cannon`, with `pitch = lerp(cannon_pitch_folded, cannon_pitch_extended, reach_ratio)` so the cannon folds under compression and straightens on the reach. **Known issue**: the curve constants don't match the rest pose's actual cannon pitch — at idle the cannon ends up rotated ~30° from rest.
    - **Plane-constrained 2-bone analytic IK** (`_solve_two_bone_plane`, law of cosines): projects the hip onto the plane perpendicular to skel-X through the hock, solves `thigh + shin` in that plane. `knee.X == hock.X` by construction, so the thigh has no yaw to introduce during straight stride (`hock.X` is constant) and yaws naturally on strafing (`hock.X` moves with the foot).
    - **`thigh`**: ball joint, `_aim_bone_cone` at the plane-constrained knee, `thigh_cone_deg` as a safety net.
    - **`shin`** and **`cannon`**: 1-DOF hinges, `_aim_bone_hinge` around `shin_hinge_axis` / `cannon_hinge_axis` (skel space, default `(1, 0, 0)`), clamped to per-bone `min/max_deg`.
    - **`foot`**: ball joint, `_aim_bone_cone` aiming along chassis-forward projected onto the ground plane (`pole − normal * pole.dot(normal)`), `foot_cone_deg` clamp. Bone lies flat on slopes.
  - **Torso/camera**: torso bone is undriven; camera rides it at rest via a `BoneAttachment3D`. Inertia lean and the dialed-down stride oscillator move onto the torso once the bone is driven. Look split (mouse yaw turns the `torso` bone within a range, then chassis past it) is also pending.
- **Stride oscillator** (implemented): sine wave driven by velocity; drives camera bob (`bob_amplitude_y`) and sway (`bob_amplitude_x`); sharpened with `pow()` for footstep contrast. Survives the rig change as the high-freq layer under the procedural leg motion.
- **Inertia lean** (implemented, needs tuning): pitch slightly forward when climbing, back when descending — derived from frame-to-frame Y position delta, not velocity.y. Migrates from the camera to `Torso` when the rig lands.
- **Active ragdoll — phase 2, deferred**: `PhysicalBone3D` chain + joint motors chasing the procedural target pose, for emergent balance / stumble / recovery (the "damaged mech" fantasy felt in the body, not read on a screen). The procedural rig's target pose is exactly what the motors need as a drive target, so phase-1 work isn't throwaway. Requires reworking parts of the movement/collision model — not started.
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — still planned
- Leg components expose `functionality: float`; the gait planner reads it to degrade feel — longer `step_duration`, lower `step_height`, more limp asymmetry, a knee that won't fully straighten

### Mech Variants & Rig
The player mech is one of many — patrol units, faction mechs, others fighting in the background — so the rig must generalise from day one.
- **Skeleton in Blender, driven in Godot**: bones, hierarchy, rest pose, vertex weights live in the `.glb`; IK / gait / pelvis solve is a `SkeletonModifier3D` subclass writing bone poses in `_process_modification()` (segment lengths are read from the rest pose, so the rig adapts to any mech using the same bone names). Godot does not import Blender IK constraints / control rigs — only the deform skeleton + (optionally) baked clips — so any terrain-reactive leg motion *has* to be solved at runtime in Godot regardless. No Blender IK constraints, no baked walk clip (Blender IK is the right tool for the *idle* clip only — pose it there, bake it, layer it on top later).
- **Bone naming is a contract** — the rig script looks bones up by name. Current mk2 skeleton (`mech-mk2-rigged.glb`): `ground` (root) → `pelvis` → `torso`; per leg `thigh.L/R → shin.L/R → cannon.L/R → foot.L/R`. The `ground` bone carries the rest 180° Y rotation so the imported model faces chassis-forward (-Z) without any scene-level transform on the mech node — earlier builds rotated the scene node instead and the legs ended up reading L↔R wrong from the cockpit POV. Joint roles in the current rig: `thigh` = hip **ball joint** with a cone safety-net (`thigh_cone_deg`) — yaw is held down by the plane-constrained IK, not by the cone; `shin` and `cannon` = 1-DOF **pitch hinges** around `shin_hinge_axis` / `cannon_hinge_axis` (skel-space, default `(1, 0, 0)`), clamped to per-bone `min/max_deg`; `foot` = horizontal ankle **ball joint** with cone (`foot_cone_deg`), bone +Y points along chassis-forward at rest with the sole `foot_height` below the bone (no `toe` bone). Author the rest pose in the digitigrade Z-fold — thigh down-forward, shin down-back, cannon down-forward to the ankle, stifle clearly bent forward, foot horizontal in chassis-forward direction; that rest pose *is* the IK pole hint and the default standing pose. The armature node is `mech_armature`. (Earlier iterations: `mech-rigged.glb` with `pelvis (root) + tigh.L/R → shin.L/R → cannon.L/R → foot.L/R` and no `torso`; an interim `mk2` that split the hip into `thigh_roll` + `thigh` and the ankle into `ankle_pitch` + `ankle_roll` to make every joint a single-axis hinge — both collapsed back to the four-bone-per-leg form because the explicit splits were brittle to author L/R-symmetric in Blender.)
- **Same topology across all biped mechs**: one rig script (`mech_digitigrade_rig.gd` / `MechDigitigradeRig`) drives every biped. Variation will live in a `MechConfig` resource (`@export`s for leg length, hip width, step parameters, mass, top speed, mount points); for now those are `@export`s straight on the rig. New mech = new mesh + new config, not a new script.
- **Scene layout**: the mech is split into `scenes/mech_mk_2_rigged.tscn` (the `.glb` instance with the `MechWiring` script + `MechDigitigradeRig` on `mech_armature/Skeleton3D` + two foot `RayCast3D`s + a `BoneAttachment3D` on the Skeleton3D bound to the `torso` bone carrying the cockpit `Camera3D`) and the `CharacterBody3D` in the level scene. `scripts/mech_wiring.gd` (`MechWiring`, a `Node3D`) is the glue — it holds references to `chassis`, `rig`, and `camera`, and wires `rig.chassis` in `_ready()`. `scripts/mech_config.gd` is a `Resource` (`MechConfig`) holding the IK + gait + constraint params, referenced by the rig via `@export var config`. The chassis pulls the camera from `mech_wiring.camera`. The body mesh is on render layer 2 with the camera's `cull_mask` excluding it (so you don't see the inside of your own hull). The mech node in `dev_walk.tscn` no longer needs a 180° Y rotation — that's now in the `ground` bone's rest, so `knee_pole = FORWARD` works directly.
- **Blender origin convention**: armature origin must be at foot-sole level in the rest pose (Y=0 = ground contact). This ensures the Skeleton3D sits at the correct height above the terrain in Godot with no manual Y offset needed. Apply all transforms on the armature on export (no import-scale fudge).
- **Controller is swappable**: `PlayerController` reads input, `AIController` produces target velocity/facing — both feed the same chassis + rig.
- **All biped mechs are digitigrade** — one topology for the whole mech population (one rig script, variation via `MechConfig`). Variety in the mech population comes from **drones** (floating workshop tool + sensor gimbal — no gait) and possibly **wheeled vehicles** (spinning wheels + suspension travel, kept kinematic like the mech chassis), not from different leg topologies. A humanoid/plantigrade war-mech or a quadruped/animal mech would be a *separate* rig script (different chain or gait pattern, not a config tweak) — but the intent is to *not* build those; share the analytic IK and foot-raycast as utilities if it ever happens.
- **Joints are mixed** — the "pure single-axis hinges everywhere" intent simplified out once we collapsed `thigh_roll` and the ankle pair back into single ball joints: the leg chain is hip ball (`thigh`) → knee hinge (`shin`) → metatarsal hinge (`cannon`) → ankle ball (`foot`). Hinges keep per-joint limits as trivial scalar min/max; balls use a cone clamp plus a plane constraint in the IK (`_solve_two_bone_plane`) to stop them from yawing when nothing wants them to — yaw appears only when the foot's X position moves laterally (strafing). Foot yaw is not a joint; turn-in-place re-plants the feet instead.
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
- Leg IK is analytic 2-bone (plane-constrained `_solve_two_bone_plane`, solving `thigh+shin` to the hock in a plane perpendicular to skel-X) plus a deterministic `cannon`/`foot` solve — no FABRIK, no iterative solvers, no full-skeleton retarget IK rigs
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
