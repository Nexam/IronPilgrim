extends Resource
class_name MechConfig

@export_group("IK")
@export var knee_pole := Vector3.FORWARD
@export var max_drop := 3.0
@export_range(0.0, 1.5, 0.01) var foot_height := 0.23
@export_range(0.0, 80.0, 0.5) var cannon_pitch_folded := 55.0
@export_range(0.0, 80.0, 0.5) var cannon_pitch_extended := 15.0

@export_group("Gait")
@export var step_trigger_dist := 0.45
@export var step_duration := 0.35
@export var step_height := 0.35
@export var step_lead_time := 0.15
@export var step_min_interval := 0.15
@export var yaw_replant_deg := 18.0

# Hinge axes are in skeleton space.
# (1,0,0) = lateral X, (0,1,0) = up, (0,0,1) = +Z (rear, since -Z is forward).
@export_group("Constraint Axes")
@export var shin_hinge_axis   := Vector3(1, 0, 0)
@export var cannon_hinge_axis := Vector3(1, 0, 0)

# Ball joint at the hip. Yaw is *not* clamped by this cone — instead, the IK
# constrains the knee to a plane perpendicular to skel-X through the hock, so
# the thigh only yaws when the foot itself moves laterally (strafing). The cone
# is just a safety net against degenerate aims.
@export_group("Constraints / thigh")
@export_range(0.0, 180.0, 0.5) var thigh_cone_deg := 90.0

@export_group("Constraints / shin")
@export_range(-180.0, 180.0, 0.5) var shin_min_deg := -106.5
@export_range(-180.0, 180.0, 0.5) var shin_max_deg := 19.5

@export_group("Constraints / cannon")
@export_range(-180.0, 180.0, 0.5) var cannon_min_deg := -28.5
@export_range(-180.0, 180.0, 0.5) var cannon_max_deg := 119.5

# Ball joint at the ankle: aims along ground-tangent forward; cone limits tilt
# out of the (parent-rotated) rest direction so the foot doesn't whip on slopes.
@export_group("Constraints / foot")
@export_range(0.0, 180.0, 0.5) var foot_cone_deg := 60.0
