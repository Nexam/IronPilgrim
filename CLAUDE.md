# Iron Pilgrim — CLAUDE.md

## Project

3D exploration game in Godot 4. The player **is** the mech — no separate human pilot, no third-person camera, no traditional HUD. The world is dying. The mech starts damaged. Tone: bleak, slow, lonely.

**Stack**: Godot 4 · GDScript · Jolt physics (default in Godot 4.3+)

**Repository layout**:
- `iron-pilgrim-game/` — Godot project
- `iron-pilgrim-gdd/` — design documents

---

## Build Order

Work in this sequence. Do not start a later system until the earlier ones are solid.

1. **Component graph** — data schema first, propagation logic second
2. **Cockpit camera + stride oscillator** — movement feel before anything else
3. **Mech mesh + idle animation** — only needs to look right at rest
4. **Drone view** — stationary workshop camera, repair/upgrade UI
5. **World / scavenging** — after core mech systems are solid
6. **Creatures** — after world exists

---

## Core Systems

### Component Graph
- Every physical part of the mech (engine, actuators, wire bundles, sensors, screens) is a node in a directed graph
- Each component: `health`, `mass`, `power_consumption` / `power_output`, `functionality: float` (0.0–1.0)
- Damage propagates — severed wires cut power to downstream nodes
- Component mass feeds CoM calculation for the stability system
- Components are salvageable and replaceable; loadout choices open different approaches to obstacles

### Locomotion & Physics
- Chassis: `CharacterBody3D` (kinematic)
- **Stride oscillator** (implemented): sine wave driven by velocity; drives camera bob (`bob_amplitude_y`) and sway (`bob_amplitude_x`); sharpened with `pow()` for footstep contrast
- **Inertia lean** (implemented, needs tuning): pitch camera slightly forward when climbing, back when descending — derived from frame-to-frame Y position delta, not velocity.y
- **Slope feel is an open problem**: full terrain alignment feels like a car (wrong for a biped); pure inertia lean is closer but not convincing yet. Options under consideration:
  - Lightweight leg simulation (minimal IK, just enough for body sway)
  - Alternative locomotion (monowheel or 4-wheel — easier to implement correctly, less biped fantasy)
  - Deeper inertia/momentum model on the camera rig
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — still planned
- Leg components expose `functionality: float`; the oscillator reads this to degrade feel

### Drone View & Mech Mesh
- Drone is a **stationary workshop tool** — deploy it, it stays put; used for repair, upgrade, and inspection
- The mech mesh only needs to look correct **at rest** — no walking animation required
- **Idle animation only**: subtle hydraulic micro-movements, weight shifts, a damaged limb hanging slightly wrong
- Idle animation can reflect damage state (a broken limb hangs differently) without any locomotion system

### Camera & Perspective
All views are diegetic — the player only sees what the mech can see.

| View | Mechanic | Animation |
|---|---|---|
| Cockpit (primary) | First-person interior; stride oscillator drives camera feel | None — camera only |
| Sensor cluster | Head rotates for situational awareness; damage narrows FOV | Arc rotation only |
| Drone | Stationary workshop camera; deploy and it stays put | Mech plays idle only |

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
- No IK / FABRIK for now — but lightweight leg simulation may be needed for convincing slope feel; decision pending
- No walking animation on the mech mesh — idle only; drone view is a workshop tool, not a spectator camera
- No full active ragdoll — kinematic + physics handoff only
- World and creature systems wait until component graph and cockpit are solid
- Narrative depth and world detail are deferred to a larger project later

---

## GDScript Conventions

- Snake_case for variables and functions, PascalCase for classes/nodes
- Prefer `@export` over direct node path strings where possible
- Keep physics logic out of `_process`; use `_physics_process` for anything touching `CharacterBody3D` or forces
- Component graph nodes should be loosely coupled — communicate via signals, not direct references where possible
