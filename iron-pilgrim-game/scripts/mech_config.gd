extends Resource
class_name MechConfig

@export_group("IK")
@export var knee_pole := Vector3.FORWARD
@export var max_drop := 3.0
@export_range(0.0, 1.5, 0.01) var foot_height := 0.2
@export_range(0.0, 80.0, 0.5) var cannon_pitch_folded := 55.0
@export_range(0.0, 80.0, 0.5) var cannon_pitch_extended := 15.0

@export_group("Gait")
@export var step_trigger_dist := 0.45
@export var step_duration := 0.35
@export var step_height := 0.35
@export var step_lead_time := 0.15
@export var step_min_interval := 0.15
@export var yaw_replant_deg := 18.0

# Angles are relative to each bone's rest pose (+Y direction = 0°).
# Hinge axes are in local bone space: (1,0,0) = local X, (0,1,0) = local Y,
# (0,0,1) = local Z. Adjust axes until the arcs match in-game joint motion.

@export_group("Constraint Axes")
# Axes are in skeleton space (the skeleton node's local frame), not bone-local.
# (1,0,0) = skeleton X (lateral),  (0,1,0) = skeleton Y (up),
# (0,0,1) = skeleton Z (forward).  Negate to flip the arc's positive direction.
# The ball-joint cone is always centred on the bone's rest direction — no axis needed.
@export var thigh_hinge_axis       := Vector3(1, 0, 0)
@export var shin_hinge_axis        := Vector3(1, 0, 0)
@export var cannon_hinge_axis      := Vector3(1, 0, 0)
@export var ankle_pitch_hinge_axis := Vector3(1, 0, 0)
@export var ankle_roll_hinge_axis  := Vector3(0, 0, 1)

@export_group("Constraints / thigh_roll")
@export_range(0.0, 90.0, 0.5) var thigh_roll_cone_deg := 40.0
@export_range(-90.0, 0.0, 0.5) var thigh_roll_twist_min_deg := -20.0
@export_range(0.0, 90.0, 0.5) var thigh_roll_twist_max_deg := 20.0

@export_group("Constraints / thigh")
@export_range(-180.0, 180.0, 0.5) var thigh_min_deg := -120.0
@export_range(-180.0, 180.0, 0.5) var thigh_max_deg := 30.0

@export_group("Constraints / shin")
@export_range(-180.0, 180.0, 0.5) var shin_min_deg := 0.0
@export_range(-180.0, 180.0, 0.5) var shin_max_deg := 150.0

@export_group("Constraints / cannon")
@export_range(-180.0, 180.0, 0.5) var cannon_min_deg := -60.0
@export_range(-180.0, 180.0, 0.5) var cannon_max_deg := 60.0

@export_group("Constraints / ankle_pitch")
@export_range(-90.0, 90.0, 0.5) var ankle_pitch_min_deg := -30.0
@export_range(-90.0, 90.0, 0.5) var ankle_pitch_max_deg := 30.0

@export_group("Constraints / ankle_roll")
# ankle_roll rotates around the bone's local Z (forward) axis, not X.
@export_range(-90.0, 90.0, 0.5) var ankle_roll_min_deg := -25.0
@export_range(-90.0, 90.0, 0.5) var ankle_roll_max_deg := 25.0
