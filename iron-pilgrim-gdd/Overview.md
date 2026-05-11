
# Iron Pilgrim — Game Summary

> A mech crossing a dying world, carrying something it doesn't understand, toward a signal it can't explain.

---

## Concept

Iron Pilgrim is a 3D exploration game built in Godot 4. The player **is** the mech — fused into it like a Warhammer 40k Dreadnought. There is no separate human pilot; the cockpit interior is the character space. The world is dying. The mech starts damaged. The tone is bleak, heavy, slow, and lonely.

Target length: **10–20 hours**. This project focuses on mech gameplay as a foundation for a larger game down the line.

**Stack**: Godot 4, GDScript, Jolt physics (default in Godot 4.3+)

---

## References

| Reference | What it contributes |
|---|---|
| Warhammer 40k Dreadnought | Pilot fused to the mech — it is home, burden, and body |
| Space Engineers | Component-based construction, tactile understanding of your machine |
| Immersive Sims | Systemic freedom, emergent problem solving, no single correct path |
| Elden Ring | Ambiance — ancient, indifferent world, beauty in ruin |

---

## Narrative & Goal

### The Hook
The mech wakes up already moving. It carries a sealed cargo — something it cannot open or identify. A signal pulses from somewhere ahead. The mech doesn't know what emits it, or why it's compelled to follow it. But it is.

### The Journey
The signal is the north star. Everything else — terrain, creatures, structural failure, missing components — is the cost of following it. The player is always oriented toward a goal, but the world constantly forces detours. Those detours are the game.

As the mech repairs sensors and progresses, the signal reveals itself slowly: a direction becomes a shape, a shape becomes a frequency, eventually something almost like a voice or an image. The signal is a slow reveal across the entire game.

### The End
The mech reaches the source. It delivers the cargo. What the cargo was, what the signal was, what happened to this world — the player gets answers. But the answers recontextualize the journey rather than close it. More questions than before, but the right kind.

### The Cargo
A silent mystery object. Never explained until the end. The player projects meaning onto it. It must be protected — losing or damaging it has consequences. It is the only thing the mech was given a reason to care about.

---

## Tone & Pacing

- **Slow and contemplative** by default — the world is vast, movement has weight, silence is deliberate
- **No dialogue** — story told through environment, ruins, creature behavior, recovered data fragments
- **Tension spikes** are occasional and earned — not a combat game, but pressure exists
- The mech itself is a source of tension: component failures, power rerouting, a limb starting to compensate mid-traverse

---

## Gameplay Loop

1. Follow the signal — it gives direction, not a map
2. The world blocks the path — terrain, creatures, structural gaps the damaged mech can't cross
3. Detour to scavenge — find components, recover data fragments, piece together what happened here
4. Repair and reconfigure — the component graph is a problem-solving tool, not just a health bar
5. Return to the path — now able to cross what you couldn't before
6. Repeat, with the signal growing clearer

---

## Creatures

- Fantastical — not grounded animals, something stranger
- Some are gigantic
- Behavior is either **indifferent** or **hostile** — nothing is friendly
- They exist for their own reasons; the mech is an intruder in their world
- Avoiding, hiding, or fighting are all valid responses — the mech has weapons but is not a combat machine

Hiding a large mech is its own interesting design problem.

---

## The Mech

The mech is not a vehicle — it is home, burden, and means of survival.

- Every physical component (engine, wire bundles, actuators, screens, sensors) is a node in a **component graph**
- Each component has: health, mass, power consumption/output, and a functionality float (0.0–1.0)
- **Damage propagates** through the graph — severed wires cut power to downstream components
- Component mass feeds into a center-of-mass calculation that drives the stability system
- Built from salvage — components are replaceable and customizable
- The component graph is the primary systemic layer: power routing, loadout choices, and repair decisions open different approaches to the same obstacle

---

## Locomotion & Physics

- Chassis uses `CharacterBody3D` (kinematic) under normal operation
- **No IK / FABRIK** — the player never sees legs from inside the cockpit; leg behavior is simulated through camera feel, not geometry
- **Stride oscillator**: a sine wave driven by velocity that parametrizes camera bob, sway, and tilt. Damaged leg components warp amplitude, frequency, or introduce asymmetry (limp effect)
- **Terrain alignment**: raycast down, align chassis to terrain normal — gives correct slope tilt without a stability polygon
- Leg components expose `functionality: float`; the stride oscillator reads this to degrade movement feel
- On large impacts or falls: hand off to `RigidBody3D`, detect settlement, resume kinematic — landing must feel weighty

---

## Camera & Perspective

All views are **diegetic** — the player only ever sees what the mech can see.

| View | Description |
|---|---|
| **Cockpit (primary)** | First-person interior — where the player lives; stride oscillator drives camera feel |
| **Sensor cluster** | Head rotates for situational awareness (arc-limited); damage narrows FOV |
| **Drone** | Stationary workshop camera — deploy it, it stays put; used for repair, upgrade, and inspection; mech plays idle animation only |

No free third-person camera. The drone is a workshop tool, not a spectator camera — the mech does not walk while the drone is active.

---

## UI

Fully **diegetic** — no HUD.

- Cockpit screens are `SubViewport` nodes rendered onto 3D meshes inside the cockpit
- A damaged screen goes dark or shows static — the information is physically lost
- Signal tracking, maps, component graphs, cargo status — all on physical screens the player looks at

---

## Art Direction

Unresolved — needs testing in Blender and Godot before committing to a direction.

---

## Key Systems

| System | Status | Notes |
|---|---|---|
| Component graph | Not started | Core of everything — build first |
| Cockpit camera + stride oscillator | Not started | Movement feel; no IK needed |
| Mech mesh + idle animation | Not started | Only needs to look right at rest |
| Drone view | Not started | Stationary workshop camera; repair/upgrade UI |
| Physics handoff | Not started | Kinematic ↔ RigidBody on falls/impacts |
| Diegetic UI (screens) | Not started | SubViewport on mesh |
| World / scavenging | Not started | After core mech systems are solid |
| Creatures | Not started | After world exists |

---

## Scope Guards

- No free third-person camera — drone is the only external view and it is diegetic
- No human pilot model or animation — there isn't one
- No traditional HUD — screens only
- No IK / FABRIK — locomotion feel comes from the stride oscillator, not leg geometry
- No walking animation on the mech mesh — idle only; the drone is a workshop tool, not a spectator camera
- Full active ragdoll is out of scope — kinematic + physics handoff only
- World and creature systems come after component graph and cockpit are solid
- This version focuses on mech gameplay — narrative and world depth are for the larger project later
