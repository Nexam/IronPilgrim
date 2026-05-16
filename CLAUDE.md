# Iron Pilgrim — CLAUDE.md

## Project

3D exploration game in Godot 4. The player **is** the mech — not a pilot inside it but the machine itself: a damaged, half-amnesiac silicon AI carrying one sealed cargo (the last human — an infant) toward safety across a dying world of warring robots and stranger creatures. Not a war mech — a battered utility/scout machine with scavenged light weaponry. Story is told through the world and a final reveal (the cargo); no HUD, no third-person camera, no human pilot. Tone: bleak, slow, lonely. See `iron-pilgrim-gdd/Worldbuilding.md` for the full story spine.

**Stack**: Godot 4 · GDScript · Jolt physics (default in Godot 4.3+)

**Repository layout**:
- `iron-pilgrim-game/` — Godot project
- `iron-pilgrim-gdd/` — design documents

---

## Build Order

Work in this sequence. Do not start a later system until the earlier ones are solid. See `iron-pilgrim-gdd/Immediate Priorities.md` for the current short-term breakdown and reasoning.

1. **Component graph** — schema design on paper first (node properties, edge types, damage state model — `functionality: float` alone is insufficient; see Repair doc for the qualitative failure modes it needs to express), then implementation. Everything downstream depends on this.
2. **Cockpit camera + stride oscillator** — movement feel before anything else. Stride oscillator and inertia lean were prototyped in the old rig but **not yet ported** to the new torso-driven system. Port is the immediate next code task — the torso bone is now the right home and was always the intended destination.
3. **Procedural leg rig** *(active — rewritten from scratch)* — previous `MechDigitigradeRig` approach is in `obsolete/`. The new system splits responsibilities cleanly: `StepsPlanner` owns all gait/body logic and moves `Node3D` marker nodes around the scene; `MechSkeletonDriver` (a `SkeletonModifier3D`) reads those markers and drives bones to match. The two scripts know nothing about each other except through the shared marker nodes.
   - **Skeleton (mk2)**: same `.glb` and bone contract — `mech-mk2-rigged.glb`, `ground` (root) → `pelvis` → `torso`; per leg `thigh.L/R → shin.L/R → cannon.L/R → foot.L/R`. `ground` bone still carries the 180° Y rest rotation.
   - **`StepsPlanner`** (`scripts/step_planner.gd`, `Node3D`, runs in `_physics_process`): owns the full gait FSM plus pelvis and torso positioning. References the `MechMk3` root via `$".."`.
     - **Gait FSM**: each foot is PLANTED or STEPPING. Step is triggered when the planted position drifts past **asymmetric thresholds**: `forward_trigger_dist` / `backward_trigger_dist` / `side_trigger_dist` (separate forward-back-side values, checked in chassis-local space). Only one foot steps at a time. The step arc lerps position and slerps ground normals from lift to plant (`sin(t·π)·step_height`), so the foot arrives aligned to the landing surface. Raycasts are repositioned dynamically per probe each frame — not static nodes. Stepping is still **reactive** (lift on drift), not phase-based.
     - **Lead position**: `step_lead_distance` scaled by `clamp(speed / max_step_lead_speed, 0, 1)`, raycast down from there — velocity-proportional anticipation without overshoot.
     - **Neutral foot position**: `Marker3D` nodes (`foot_offset_L/R`) parented to the mech root define rest stance; raycasting from their world position anchors the stance width correctly (not from the hip).
     - **Pelvis solve** (now implemented): target position = foot midpoint + support-foot shift (`pelvis_support_shift` lerp toward the planted foot when one is stepping) + velocity-lag offset (`-velocity.normalized() * pelvis_velocity_lag`) + `Vector3.UP * (pelvis_height + step_lift)`; smoothed with exponential `pelvis_follow_speed`. Rotation: roll toward planted foot (`pelvis_roll_amount` deg) when one foot is stepping; pitch forward at speed (`pelvis_pitch_amount` deg × speed_factor); smoothed with `pelvis_rotation_follow_speed`.
     - **Torso solve** (now implemented): hard-pinned to pelvis Y + `torso_height` (no sliding). Rotation slerped between the pelvis basis and a world-leveled basis by `torso_horizon_stabilization` (0 = pure pelvis tilt, 1 = fully horizon-locked); smoothed with `torso_rotation_follow_speed`.
     - Marker nodes (`foot_debug_L/R`, `Pelvis Debug`, `torso_debug`) are the interface to `MechSkeletonDriver` — their transforms are the IK targets.
   - **`MechSkeletonDriver`** (`scripts/mech_skeleton_driver.gd`, `SkeletonModifier3D` on `mech_armature/Skeleton3D`, runs in `_process_modification`):
     - **Pelvis**: position + rotation copied directly from `pelvis_target` Node3D (plus `pelvis_rotation_correction`).
     - **Torso**: rotation copied from `torso_target` Node3D (plus `torso_rotation_correction`).
     - **Per-leg IK** (`_solve_leg`):
       - Ankle target: `foot_target.global_position + foot_target.global_basis.y * ankle_height`.
       - Hock target: ankle + `cannon_preferred_dir_local` (world-transformed, then projected onto sagittal plane via `pole × UP`) × `cannon_length`. This replaces the old `cannon_pitch_folded/extended` interpolation — the preferred direction is a tunable export, not a derived angle, so it stays aligned at rest.
       - Knee position: analytic 2-bone (`_solve_two_bone_joint_position`, law of cosines) from thigh to hock with `knee_pole_dir_local` as the pole direction (world-space, simple dot-project, not the old skel-X plane constraint).
       - `thigh`: aimed at knee via `_aim_bone_at` (rotates the local aim axis toward target).
       - `shin`: aimed at hock via `_aim_bone_at`.
       - `cannon`: `_look_at_bone_y_axis` (builds a Basis from forward/right/dir so the bone's Y points at the ankle).
       - `foot`: position driven to ankle target (`_drive_bone_position_to_global`); rotation copied from `foot_target` transform (`_drive_bone_rotation_from_target`) — so the foot bone exactly matches the StepsPlanner's orientation (flat on slope, facing chassis-forward).
     - Per-bone `rotation_correction` exports (Vector3 degrees) compensate for Blender→Godot axis differences without touching the rest pose.
     - Segment lengths read from rest pose at `_ready` — rig auto-adapts to any mech with the same bone names.
   - **What's still pending**: stride oscillator and inertia lean not yet ported to new system (next code task); rough leg geometry in Blender needed to validate gait visually — can't judge proportion, knee travel, or cannon angle from debug spheres alone; phase-based gait (cadence-driven lift instead of drift-triggered) deferred until geometry validation reveals what actually looks wrong; `@tool` authoring helpers for tuning trigger boxes and neutral foot markers; active ragdoll (phase 2, deferred).
   - **Gait tuning order**: port oscillator/lean → add rough geometry → validate visually → then decide if phase-based gait is needed. Do not rewrite the planner before seeing the rig with a mesh.
4. **Mech mesh + idle animation** — rough leg geometry first (validate rig), then final mesh; idle micro-movement layered on top of the standing pose; only needs to look right at rest
5. **Drone view** — design decision required before build: stationary workshop tool (current CLAUDE.md/Overview assumption) vs. mobile short-range flying unit (Repair doc). Decide before this enters the queue. See `iron-pilgrim-gdd/Immediate Priorities.md` §3.
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
- **Chassis** (`scripts/mech_character_body_3d.gd`, `CharacterBody3D`): kinematic body — owns movement, collision, capsule, gravity, and mouse-look. `move_and_slide` in `_physics_process`. Also handles cockpit/exterior camera switching via the `switch_view` action. The chassis is the parent of the mech visual scene in `dev_walk.tscn`.
- **Procedural leg rig** — see Build Order #3 for full detail. Two scripts, clean separation:
  - `StepsPlanner` (`scripts/step_planner.gd`): `Node3D` child of the mech visual root, runs in `_physics_process`. Owns the gait FSM and drives `Node3D` marker nodes for feet, pelvis, and torso.
  - `MechSkeletonDriver` (`scripts/mech_skeleton_driver.gd`): `SkeletonModifier3D` on the `Skeleton3D`. Reads the marker nodes from `StepsPlanner` and drives bone poses in `_process_modification()`. No physics logic — pure skeleton driving.
  - The legs *follow* the chassis; they do not hold the mech up.
- **Pelvis and torso are now fully driven** by `StepsPlanner` — no longer rigid poles. Pelvis springs toward foot midpoint with support-foot shift, velocity lag, and step lift. Torso is pinned above pelvis and horizon-stabilized. Camera rides the `torso` bone via `BoneAttachment3D` and gets organic body motion for free.
- **Stride oscillator and inertia lean**: not yet ported to the new system (were in the old `MechDigitigradeRig`). Planned to layer on top of the driven torso.
- **Active ragdoll — phase 2, deferred**: `PhysicalBone3D` chain + joint motors chasing the procedural target pose, for emergent balance / stumble / recovery. The marker-driven architecture makes the target pose trivially available. Requires reworking collision model — not started.
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — still planned.
- Leg components expose `functionality: float`; the gait planner reads it to degrade feel — longer `step_duration`, lower `step_height`, more limp asymmetry, a knee that won't fully straighten.

### Mech Variants & Rig
The player mech is one of many — patrol units, faction mechs, others fighting in the background — so the rig must generalise from day one.
- **Skeleton in Blender, driven in Godot**: bones, hierarchy, rest pose, vertex weights live in the `.glb`; IK / gait / pelvis solve is a `SkeletonModifier3D` subclass writing bone poses in `_process_modification()` (segment lengths are read from the rest pose, so the rig adapts to any mech using the same bone names). Godot does not import Blender IK constraints / control rigs — only the deform skeleton + (optionally) baked clips — so any terrain-reactive leg motion *has* to be solved at runtime in Godot regardless. No Blender IK constraints, no baked walk clip (Blender IK is the right tool for the *idle* clip only — pose it there, bake it, layer it on top later).
- **Bone naming is a contract** — the rig script looks bones up by name. Current mk2 skeleton (`mech-mk2-rigged.glb`): `ground` (root) → `pelvis` → `torso`; per leg `thigh.L/R → shin.L/R → cannon.L/R → foot.L/R`. The `ground` bone carries the rest 180° Y rotation so the imported model faces chassis-forward (-Z) without any scene-level transform on the mech node — earlier builds rotated the scene node instead and the legs ended up reading L↔R wrong from the cockpit POV. Joint roles in the current rig: `thigh` = hip **ball joint** with a cone safety-net (`thigh_cone_deg`) — yaw is held down by the plane-constrained IK, not by the cone; `shin` and `cannon` = 1-DOF **pitch hinges** around `shin_hinge_axis` / `cannon_hinge_axis` (skel-space, default `(1, 0, 0)`), clamped to per-bone `min/max_deg`; `foot` = horizontal ankle **ball joint** with cone (`foot_cone_deg`), bone +Y points along chassis-forward at rest with the sole `foot_height` below the bone (no `toe` bone). Author the rest pose in the digitigrade Z-fold — thigh down-forward, shin down-back, cannon down-forward to the ankle, stifle clearly bent forward, foot horizontal in chassis-forward direction; that rest pose *is* the IK pole hint and the default standing pose. The armature node is `mech_armature`. (Earlier iterations: `mech-rigged.glb` with `pelvis (root) + tigh.L/R → shin.L/R → cannon.L/R → foot.L/R` and no `torso`; an interim `mk2` that split the hip into `thigh_roll` + `thigh` and the ankle into `ankle_pitch` + `ankle_roll` to make every joint a single-axis hinge — both collapsed back to the four-bone-per-leg form because the explicit splits were brittle to author L/R-symmetric in Blender.)
- **Same topology across all biped mechs**: `MechSkeletonDriver` + `StepsPlanner` drive every biped. Config lives as `@export`s directly on the two scripts for now. No `MechConfig` resource yet — the old `mech_config.gd` is in `obsolete/`. New mech = new mesh + tuned exports, not a new script.
- **Scene layout**: `scenes/mech_mk_3.tscn` is the mech visual prefab — the `.glb` instance (`mech-mk2-rigged.glb`) with `MechMk3` script at root, `MechSkeletonDriver` on `mech_armature/Skeleton3D`, `BoneAttachment3D` on the torso bone carrying the cockpit `Camera3D`, `StepsPlanner` as a sibling Node3D, marker nodes (`foot_debug_L/R`, `Pelvis Debug`, `torso_debug`) as IK targets, `Marker3D` nodes (`foot_offset_L/R`) defining neutral stance width, and two `RayCast3D`s. The `CharacterBody3D` (with `mech_character_body_3d.gd`) lives in `dev_walk.tscn` as the parent. `scripts/mech_mk_3.gd` (`MechMk3`, a `Node3D`) is the lightweight mech root — holds the cockpit camera and exterior mesh refs and handles cockpit-vs-exterior shadow casting. Old `mech_wiring.gd` and `mech_config.gd` are in `obsolete/`. The body mesh is excluded from the cockpit camera's cull mask so you don't see the inside of your own hull.
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
- Leg IK is analytic 2-bone (`_solve_two_bone_joint_position`, law of cosines, pole-direction knee) plus a deterministic `cannon` (preferred-direction projection) and `foot` (copy target transform) solve — no FABRIK, no iterative solvers, no full-skeleton retarget IK rigs
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
