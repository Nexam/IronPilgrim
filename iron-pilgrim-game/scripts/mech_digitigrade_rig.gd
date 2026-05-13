extends SkeletonModifier3D
class_name MechDigitigradeRig

## Procedural digitigrade leg rig for the mk2 mech — gait FSM + analytic IK.
##
## Bone contract (look-ups by name; `.L` / `.R` per side):
##   body:  ground (root) -> pelvis -> torso          [pelvis/torso not driven yet]
##   leg:   thigh_roll -> thigh -> shin -> cannon -> ankle_pitch -> ankle_roll
##     - thigh_roll  : the hip ball joint — orients the whole leg-plane (aims it
##                     at the hock; its short rest offset puts the thigh joint on
##                     a sphere around the hip centre).
##     - thigh + shin : the two pitch hinges — classic 2-bone analytic IK (law of
##                      cosines), bending in that plane to reach the hock.
##     - cannon       : the metatarsal pitch hinge — aims hock -> ankle, with a
##                      *derived* pitch (folded when the leg is compressed,
##                      straighter when it reaches) so the stride keeps its length.
##     - ankle_pitch + ankle_roll : lay the foot flat along the ground normal.
## Foot yaw is not a joint — turn-in-place re-plants the feet (yaw_replant_deg).
## Segment lengths come from the rest pose, so this adapts to any mech using the
## same bone names; author the rest pose in the digitigrade Z-fold (that pose is
## the IK pole hint).
##
## Gait: each foot is a world-space target, PLANTED or STEPPING. A planted foot
## whose ideal spot (hip ground-projection led by velocity) has drifted past
## step_trigger_dist, or that has yawed past yaw_replant_deg since planting, lifts
## and swings to the new spot over step_duration on a sin(t*PI)*step_height arc.
## Only one foot swings at a time; a step_min_interval lockout stops stutter.
##
## The pelvis/torso bones are NOT driven yet (camera rides a BoneAttachment on
## `torso`); the pelvis solve is the next step — when it lands, swap the
## get_bone_global_rest hip look-up below for get_bone_global_pose.
##
## First pass on the mk2 skeleton — expect to flip a sign or two and tune exports
## in the editor. Knee bending backward -> flip `knee_pole`. Whole leg inside-out
## -> flip the rotation sign in `_solve_two_bone`.

# --- wiring (assign in the editor) ---------------------------------------
@export var chassis: CharacterBody3D
@export var foot_ray_l: RayCast3D
@export var foot_ray_r: RayCast3D

# --- bone names -----------------------------------------------------------
@export var seg_thigh_roll := "thigh_roll"
@export var seg_thigh := "thigh"
@export var seg_shin := "shin"
@export var seg_cannon := "cannon"
@export var seg_ankle_pitch := "ankle_pitch"
@export var seg_ankle_roll := "ankle_roll"
@export var suffix_l := ".L"
@export var suffix_r := ".R"

# --- leg / IK tuning ------------------------------------------------------
## Direction the stifle ("knee") bends, in chassis space. FORWARD = forward.
@export var knee_pole := Vector3.FORWARD
## How far a foot reaches straight down when the raycast finds no ground.
@export var max_drop := 3.0
## Height of the ankle joint above the sole (ground contact). The cannon aims to
## contact + up * foot_height so the ankle sits at the right elevation. Tune per mech.
@export_range(0.0, 1.5, 0.01) var foot_height := 0.2
## Cannon (metatarsal) lean from vertical when the leg is folded up under the body.
@export_range(0.0, 80.0, 1.0) var cannon_pitch_folded := 55.0
## Cannon lean from vertical when the leg is reaching near full extension.
@export_range(0.0, 80.0, 1.0) var cannon_pitch_extended := 15.0

# --- gait tuning ----------------------------------------------------------
## A planted foot this far (m) from its ideal spot triggers a step.
@export var step_trigger_dist := 0.45
## How long a swing takes (s).
@export var step_duration := 0.35
## Peak lift of the foot mid-swing (m).
@export var step_height := 0.35
## Predict the foot's plant point this far ahead by current velocity (s).
@export var step_lead_time := 0.15
## Minimum time between successive steps of the *same* foot (s) — anti-stutter.
@export var step_min_interval := 0.15
## Chassis yaw change (deg) since a foot planted that forces it to re-step,
## so turning in place re-plants the feet instead of pivoting like a tripod.
@export var yaw_replant_deg := 18.0

## Draw spheres: hip (white) / knee (green) / hock (blue) / foot target (red planted, yellow stepping).
@export var debug_draw := false

enum FootState { PLANTED, STEPPING }

class Leg:
	var thigh_roll := -1
	var thigh := -1
	var shin := -1
	var cannon := -1
	var ankle_pitch := -1
	var ankle_roll := -1
	var ray: RayCast3D
	var len_thigh_roll := 0.0   # hip ball centre -> thigh pitch joint
	var len_thigh := 0.0        # thigh joint -> knee
	var len_shin := 0.0         # knee -> hock
	var len_cannon := 0.0       # hock -> ankle joint
	var len_ankle_pitch := 0.0  # ankle joint -> ankle_roll joint
	# gait state, world space
	var state: int = FootState.PLANTED
	var initialised := false
	var foot_pos := Vector3.ZERO        # current world target (sole contact)
	var foot_normal := Vector3.UP
	var plant_yaw := 0.0
	var time_since_step := 999.0
	var step_from := Vector3.ZERO
	var step_to := Vector3.ZERO
	var step_to_normal := Vector3.UP
	var step_t := 0.0
	func ok() -> bool:
		return thigh_roll >= 0 and thigh >= 0 and shin >= 0 and cannon >= 0 \
			and ankle_pitch >= 0 and ankle_roll >= 0

var _legs: Array[Leg] = []
var _ready_ok := false
var _setup_done := false
var _dbg: Array[MeshInstance3D] = []
var _last_tick_usec := 0


func _setup(skel: Skeleton3D) -> void:
	_legs.clear()
	for spec: Array in [[suffix_l, foot_ray_l], [suffix_r, foot_ray_r]]:
		var sfx: String = spec[0]
		var leg := Leg.new()
		leg.thigh_roll = skel.find_bone(seg_thigh_roll + sfx)
		leg.thigh = skel.find_bone(seg_thigh + sfx)
		leg.shin = skel.find_bone(seg_shin + sfx)
		leg.cannon = skel.find_bone(seg_cannon + sfx)
		leg.ankle_pitch = skel.find_bone(seg_ankle_pitch + sfx)
		leg.ankle_roll = skel.find_bone(seg_ankle_roll + sfx)
		leg.ray = spec[1]
		if not leg.ok():
			push_warning("MechDigitigradeRig: missing leg bones for suffix '%s' (thigh_roll=%d thigh=%d shin=%d cannon=%d ankle_pitch=%d ankle_roll=%d)" % [sfx, leg.thigh_roll, leg.thigh, leg.shin, leg.cannon, leg.ankle_pitch, leg.ankle_roll])
			continue
		# segment length = the child bone's rest offset from this bone's joint.
		leg.len_thigh_roll = skel.get_bone_rest(leg.thigh).origin.length()
		leg.len_thigh = skel.get_bone_rest(leg.shin).origin.length()
		leg.len_shin = skel.get_bone_rest(leg.cannon).origin.length()
		leg.len_cannon = skel.get_bone_rest(leg.ankle_pitch).origin.length()
		leg.len_ankle_pitch = skel.get_bone_rest(leg.ankle_roll).origin.length()
		# the foot rays now start up at hip height — inside the chassis capsule —
		# so they must ignore it (otherwise hit_from_inside reports the capsule).
		if leg.ray != null and chassis != null:
			leg.ray.add_exception(chassis)
		_legs.append(leg)
	_ready_ok = _legs.size() > 0
	if _ready_ok:
		for i in _legs.size():
			var l := _legs[i]
			print("MechDigitigradeRig: leg %d bound — lengths roll=%.2f thigh=%.2f shin=%.2f cannon=%.2f ankle=%.2f" % [i, l.len_thigh_roll, l.len_thigh, l.len_shin, l.len_cannon, l.len_ankle_pitch])


# Wall-clock delta, robust to whatever callback mode the Skeleton3D runs us in
# (and to being called more than once a frame). Clamped against hitches.
func _tick_delta() -> float:
	var now := Time.get_ticks_usec()
	if _last_tick_usec == 0:
		_last_tick_usec = now
		return get_physics_process_delta_time()
	var d := float(now - _last_tick_usec) / 1_000_000.0
	_last_tick_usec = now
	return clampf(d, 0.0, 0.1)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not _ready_ok:
		if _setup_done:
			return
		_setup(skel)
		_setup_done = true
		if not _ready_ok:
			return

	var delta := _tick_delta()
	_update_gait(skel, delta)

	var to_skel := skel.global_transform.affine_inverse() # world -> skeleton-local
	var pole := Vector3.FORWARD
	if chassis != null:
		pole = (to_skel.basis * (chassis.global_transform.basis * knee_pole)).normalized()
	if pole.length() < 0.001:
		pole = Vector3.FORWARD

	for i in _legs.size():
		_solve_leg(skel, _legs[i], to_skel, pole, i)


# --- gait FSM -------------------------------------------------------------

func _update_gait(skel: Skeleton3D, delta: float) -> void:
	var vel_h := Vector3.ZERO
	var yaw := 0.0
	if chassis != null:
		var v := chassis.velocity
		vel_h = Vector3(v.x, 0.0, v.z)
		yaw = chassis.global_rotation.y

	# only one foot may swing at a time
	var someone_stepping := false
	for leg in _legs:
		if leg.state == FootState.STEPPING:
			someone_stepping = true
			break

	for leg in _legs:
		leg.time_since_step += delta

		# ideal world-space plant spot: hip-socket ground-projection, led by
		# velocity. (pelvis/thigh_roll undriven, so global_rest == current pose.)
		var hip_world: Vector3 = skel.global_transform * skel.get_bone_global_rest(leg.thigh).origin
		var ideal_from := hip_world + vel_h * step_lead_time
		var ground := _ground_under(leg.ray, ideal_from)
		var ideal_pos: Vector3 = ground[1] if ground[0] else Vector3(ideal_from.x, hip_world.y - max_drop, ideal_from.z)
		var ideal_n: Vector3 = ground[2]

		if not leg.initialised:
			leg.foot_pos = ideal_pos
			leg.foot_normal = ideal_n
			leg.plant_yaw = yaw
			leg.initialised = true
			continue

		if leg.state == FootState.PLANTED:
			var drifted := leg.foot_pos.distance_to(ideal_pos) > step_trigger_dist
			var yawed := absf(wrapf(yaw - leg.plant_yaw, -PI, PI)) > deg_to_rad(yaw_replant_deg)
			if (drifted or yawed) and not someone_stepping and leg.time_since_step >= step_min_interval:
				leg.state = FootState.STEPPING
				leg.step_from = leg.foot_pos
				leg.step_to = ideal_pos
				leg.step_to_normal = ideal_n
				leg.step_t = 0.0
				someone_stepping = true
		else: # STEPPING
			leg.step_t += delta / maxf(step_duration, 0.01)
			# chase a moving target a little while the swing is young
			if leg.step_t < 0.5:
				leg.step_to = leg.step_to.lerp(ideal_pos, 0.2)
				leg.step_to_normal = ideal_n
			if leg.step_t >= 1.0:
				leg.state = FootState.PLANTED
				leg.foot_pos = leg.step_to
				leg.foot_normal = leg.step_to_normal
				leg.plant_yaw = yaw
				leg.time_since_step = 0.0
			else:
				var flat := leg.step_from.lerp(leg.step_to, leg.step_t)
				leg.foot_pos = flat + Vector3.UP * (sin(leg.step_t * PI) * step_height)
				leg.foot_normal = Vector3.UP.lerp(leg.step_to_normal, leg.step_t).normalized()


# Raycast straight down through `at` to find the ground. Repositions `ray`,
# updates it immediately, and returns [hit: bool, point: Vector3, normal: Vector3].
func _ground_under(ray: RayCast3D, at: Vector3) -> Array:
	if ray == null:
		return [false, at, Vector3.UP]
	ray.global_position = at + Vector3.UP * 0.5
	ray.target_position = Vector3.DOWN * (max_drop + 1.0)
	ray.force_raycast_update()
	if ray.is_colliding():
		var n := ray.get_collision_normal()
		return [true, ray.get_collision_point(), n.normalized() if n.length() > 0.001 else Vector3.UP]
	return [false, at, Vector3.UP]


# --- leg IK ---------------------------------------------------------------

func _solve_leg(skel: Skeleton3D, leg: Leg, to_skel: Transform3D, pole: Vector3, leg_index: int) -> void:
	# hip socket (top of the femur = thigh's joint), skeleton-local. thigh_roll
	# and the pelvis are undriven, so rest == current pose.
	var hip := skel.get_bone_global_rest(leg.thigh).origin

	# foot target + ground normal, skeleton-local (from the gait FSM)
	var contact := to_skel * leg.foot_pos
	var ground_n := (to_skel.basis * leg.foot_normal).normalized()
	if ground_n.length() < 0.001:
		ground_n = (skel.global_transform.basis.inverse() * Vector3.UP).normalized()
	var up := (skel.global_transform.basis.inverse() * Vector3.UP).normalized()

	# ankle joint sits above the sole (foot is a short peg perpendicular to the
	# ground); cannon lean is derived from how far the leg is reaching — folded
	# when compressed, straighter near full extension.
	var ankle_joint := contact + ground_n * foot_height
	var max_reach := leg.len_thigh + leg.len_shin + leg.len_cannon
	var t := clampf(((ankle_joint - hip).length() / max_reach - 0.5) / 0.45, 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(cannon_pitch_folded, cannon_pitch_extended, t))

	# hock = up-and-rearward from the ankle joint by the cannon, leaned by pitch
	var rearward := -pole
	var hock := ankle_joint + (up * cos(pitch) + rearward * sin(pitch)).normalized() * leg.len_cannon

	# 2-bone analytic IK: thigh + shin (both pitch hinges) from the hip socket to
	# the hock, knee bending toward `pole` (forward) — the sagittal plane.
	var knee := _solve_two_bone(hip, hock, leg.len_thigh, leg.len_shin, pole)

	# write parent-first, accumulating global transforms ourselves. _aim_bone keeps
	# each bone's rest *position* (joints don't slide) and only rotates +Y at the
	# given target. thigh_roll stays at its rest orientation (aim it at the hip
	# socket's rest spot) — the ball-joint abduction is a later refinement; pelvis
	# is undriven, so its rest == its pose.
	var g_pelvis := skel.get_bone_global_rest(skel.get_bone_parent(leg.thigh_roll))
	var g_roll := _aim_bone(skel, leg.thigh_roll, g_pelvis, hip)
	var g_thigh := _aim_bone(skel, leg.thigh, g_roll, knee)
	var g_shin := _aim_bone(skel, leg.shin, g_thigh, hock)
	var g_cannon := _aim_bone(skel, leg.cannon, g_shin, ankle_joint)
	# foot peg: ankle_pitch and ankle_roll both aim down at the contact point —
	# on flat ground that's their rest orientation; on a slope it tilts to match.
	# (Proper pitch/roll split for terrain conform comes with the constraint pass.)
	var g_ap := _aim_bone(skel, leg.ankle_pitch, g_cannon, contact)
	_aim_bone(skel, leg.ankle_roll, g_ap, contact)

	if debug_draw:
		var b := leg_index * 4
		_dbg_point(skel, b + 0, Color.WHITE, hip)
		_dbg_point(skel, b + 1, Color.GREEN, knee)
		_dbg_point(skel, b + 2, Color.DEEP_SKY_BLUE, hock)
		_dbg_point(skel, b + 3, Color.YELLOW if leg.state == FootState.STEPPING else Color.RED, contact)


func _dbg_point(skel: Skeleton3D, idx: int, color: Color, local_pos: Vector3) -> void:
	while _dbg.size() <= idx:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skel.add_child(m)
		_dbg.append(m)
	var mi := _dbg[idx]
	(mi.material_override as StandardMaterial3D).albedo_color = color
	mi.position = local_pos


# Rotates bone `b` so its local +Y points toward `tip`, keeping its rest
# position (the joint stays put — bones rotate, they don't slide). `g_parent` is
# the bone's parent's skeleton-local transform; returns this bone's new one.
func _aim_bone(skel: Skeleton3D, b: int, g_parent: Transform3D, tip: Vector3) -> Transform3D:
	var rest_local_pos := skel.get_bone_rest(b).origin
	var head: Vector3 = g_parent * rest_local_pos
	var aimed_basis := _basis_aim_y(tip - head, skel.get_bone_global_rest(b).basis)
	var g := Transform3D(aimed_basis, head)
	skel.set_bone_pose_position(b, rest_local_pos)
	skel.set_bone_pose_rotation(b, (g_parent.affine_inverse() * g).basis.get_rotation_quaternion())
	skel.set_bone_pose_scale(b, Vector3.ONE)
	return g


# --- math helpers ---------------------------------------------------------

# Middle-joint position for a 2-bone chain from `root` to `target`, bending the
# joint toward `pole`. All vectors in the same space.
static func _solve_two_bone(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var to_t := target - root
	var dist := clampf(to_t.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_t.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var angle := acos(cos_a)
	var axis := dir.cross(pole)
	if axis.length() < 0.001:
		axis = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
	axis = axis.normalized()
	# rotate the straight-line direction toward the pole side by `angle`
	return root + dir.rotated(axis, angle) * l1


# Basis whose +Y points along `dir`, keeping roll as close to `ref` as possible.
static func _basis_aim_y(dir: Vector3, ref: Basis) -> Basis:
	var y := dir.normalized()
	if y.length() < 0.001:
		return ref
	var z := ref.z - y * y.dot(ref.z)
	if z.length() < 0.001:
		z = ref.x.cross(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	return Basis(x, y, z)
