@tool
extends SkeletonModifier3D
class_name MechDigitigradeRig

## Procedural digitigrade leg rig for the mk2 mech — gait FSM + analytic IK.
##
## Bone contract (look-ups by name; `.L` / `.R` per side):
##   body:  ground (root) -> pelvis -> torso          [pelvis/torso not driven yet]
##   leg:   thigh -> shin -> cannon -> foot
##     - thigh   : hip ball joint — `_aim_bone_cone` aims it at the knee from the
##                 plane-constrained 2-bone IK. Yaw is naturally minimal during
##                 straight stride (the knee stays at the hock's X), and appears
##                 only when the foot moves laterally. Cone is a safety net.
##     - shin    : 1-DOF hinge around `shin_hinge_axis` — aims at the hock,
##                 clamped to `[shin_min_deg, shin_max_deg]`.
##     - cannon  : 1-DOF hinge around `cannon_hinge_axis` — aims at the ankle joint.
##                 The hock target is *derived*: folded when the leg is compressed,
##                 straighter when it reaches, so the stride keeps its length.
##     - foot    : ankle ball joint — `_aim_bone_cone` aims it along chassis forward
##                 projected onto the ground plane, so the foot lies flat on slopes.
## Foot yaw is not a joint — turn-in-place re-plants the feet (yaw_replant_deg).
## Segment lengths come from the rest pose, so this adapts to any mech using the
## same bone names; author the rest pose in the digitigrade Z-fold (that pose is
## the IK pole hint and the natural standing pose).
##
## Gait: each foot is a world-space target, PLANTED or STEPPING. A planted foot
## whose ideal spot (hip ground-projection led by velocity) has drifted past
## step_trigger_dist, or that has yawed past yaw_replant_deg since planting, lifts
## and swings to the new spot over step_duration on a sin(t*PI)*step_height arc.
## Only one foot swings at a time; a step_min_interval lockout stops stutter.
##
## The pelvis/torso bones are NOT driven yet (camera rides a BoneAttachment on
## `torso`); the pelvis solve is the next step.

# Bone name contract — fixed across all biped mechs.
const BONE_THIGH  := "thigh"
const BONE_SHIN   := "shin"
const BONE_CANNON := "cannon"
const BONE_FOOT   := "foot"
const SUFFIX_L    := ".L"
const SUFFIX_R    := ".R"

# --- wiring ------------------------------------------------------------------
@export var chassis: CharacterBody3D
@export var foot_ray_l: RayCast3D
@export var foot_ray_r: RayCast3D

## Runtime debug spheres: hip (white) / knee (green) / hock (blue) /
## foot target (red planted, yellow stepping).
@export var debug_draw := false

var _config: MechConfig
@export var config: MechConfig:
	set(value):
		_config = value
	get:
		return _config

# --- runtime state -----------------------------------------------------------
enum FootState { PLANTED, STEPPING }

class Leg:
	var thigh := -1
	var shin := -1
	var cannon := -1
	var foot := -1
	var ray: RayCast3D
	var len_thigh := 0.0
	var len_shin := 0.0
	var len_cannon := 0.0
	var state: int = FootState.PLANTED
	var initialised := false
	var foot_pos := Vector3.ZERO
	var foot_normal := Vector3.UP
	var plant_yaw := 0.0
	var time_since_step := 999.0
	var step_from := Vector3.ZERO
	var step_to := Vector3.ZERO
	var step_to_normal := Vector3.UP
	var step_t := 0.0
	func ok() -> bool:
		return thigh >= 0 and shin >= 0 and cannon >= 0 and foot >= 0

var _legs: Array[Leg] = []
var _ready_ok := false
var _setup_done := false
var _dbg: Array[MeshInstance3D] = []
var _last_tick_usec := 0

# --- editor overlay ----------------------------------------------------------
var _overlay_mat: StandardMaterial3D
var _overlay_mesh: ImmediateMesh
var _overlay_instance: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_overlay()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild_overlay()


func _setup(skel: Skeleton3D) -> void:
	_legs.clear()
	for spec: Array in [[SUFFIX_L, foot_ray_l], [SUFFIX_R, foot_ray_r]]:
		var sfx: String = spec[0]
		var leg := Leg.new()
		leg.thigh  = skel.find_bone(BONE_THIGH  + sfx)
		leg.shin   = skel.find_bone(BONE_SHIN   + sfx)
		leg.cannon = skel.find_bone(BONE_CANNON + sfx)
		leg.foot   = skel.find_bone(BONE_FOOT   + sfx)
		leg.ray = spec[1]
		if not leg.ok():
			push_warning("MechDigitigradeRig: missing leg bones for suffix '%s' (thigh=%d shin=%d cannon=%d foot=%d)" % [sfx, leg.thigh, leg.shin, leg.cannon, leg.foot])
			continue
		# Each bone's length = its child's rest offset (parent-local distance).
		leg.len_thigh  = skel.get_bone_rest(leg.shin).origin.length()
		leg.len_shin   = skel.get_bone_rest(leg.cannon).origin.length()
		leg.len_cannon = skel.get_bone_rest(leg.foot).origin.length()
		if leg.ray != null and chassis != null:
			leg.ray.add_exception(chassis)
		_legs.append(leg)
	_ready_ok = _legs.size() > 0
	if _ready_ok:
		for i in _legs.size():
			var l := _legs[i]
			print("MechDigitigradeRig: leg %d bound — thigh=%.2f shin=%.2f cannon=%.2f" % [i, l.len_thigh, l.len_shin, l.len_cannon])


func _tick_delta() -> float:
	var now := Time.get_ticks_usec()
	if _last_tick_usec == 0:
		_last_tick_usec = now
		return get_physics_process_delta_time()
	var d := float(now - _last_tick_usec) / 1_000_000.0
	_last_tick_usec = now
	return clampf(d, 0.0, 0.1)


func _process_modification() -> void:
	if Engine.is_editor_hint():
		return
	if _config == null:
		return
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

	var to_skel := skel.global_transform.affine_inverse()
	var pole := Vector3.FORWARD
	if chassis != null:
		pole = (to_skel.basis * (chassis.global_transform.basis * _config.knee_pole)).normalized()
	if pole.length() < 0.001:
		pole = Vector3.FORWARD

	for i in _legs.size():
		_solve_leg(skel, _legs[i], to_skel, pole, i)


# --- gait FSM ----------------------------------------------------------------

func _update_gait(skel: Skeleton3D, delta: float) -> void:
	var vel_h := Vector3.ZERO
	var yaw := 0.0
	if chassis != null:
		var v := chassis.velocity
		vel_h = Vector3(v.x, 0.0, v.z)
		yaw = chassis.global_rotation.y

	var someone_stepping := false
	for leg in _legs:
		if leg.state == FootState.STEPPING:
			someone_stepping = true
			break

	for leg in _legs:
		leg.time_since_step += delta

		# Anchor at the foot's rest world position — that's where the foot wants
		# to be at idle. Using the hip's rest position instead would collapse the
		# stance to under-the-hip, which is narrower than the digitigrade rest.
		var stance_world: Vector3 = skel.global_transform * skel.get_bone_global_rest(leg.foot).origin
		var ideal_from := stance_world + vel_h * _config.step_lead_time
		var ground := _ground_under(leg.ray, ideal_from)
		var ideal_pos: Vector3 = ground[1] if ground[0] else Vector3(ideal_from.x, stance_world.y - _config.max_drop, ideal_from.z)
		var ideal_n: Vector3 = ground[2]

		if not leg.initialised:
			leg.foot_pos = ideal_pos
			leg.foot_normal = ideal_n
			leg.plant_yaw = yaw
			leg.initialised = true
			continue

		if leg.state == FootState.PLANTED:
			var drifted := leg.foot_pos.distance_to(ideal_pos) > _config.step_trigger_dist
			var yawed := absf(wrapf(yaw - leg.plant_yaw, -PI, PI)) > deg_to_rad(_config.yaw_replant_deg)
			if (drifted or yawed) and not someone_stepping and leg.time_since_step >= _config.step_min_interval:
				leg.state = FootState.STEPPING
				leg.step_from = leg.foot_pos
				leg.step_to = ideal_pos
				leg.step_to_normal = ideal_n
				leg.step_t = 0.0
				someone_stepping = true
		else:
			leg.step_t += delta / maxf(_config.step_duration, 0.01)
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
				leg.foot_pos = flat + Vector3.UP * (sin(leg.step_t * PI) * _config.step_height)
				leg.foot_normal = Vector3.UP.lerp(leg.step_to_normal, leg.step_t).normalized()


func _ground_under(ray: RayCast3D, at: Vector3) -> Array:
	if ray == null:
		return [false, at, Vector3.UP]
	ray.global_position = at + Vector3.UP * 0.5
	ray.target_position = Vector3.DOWN * (_config.max_drop + 1.0)
	ray.force_raycast_update()
	if ray.is_colliding():
		var n := ray.get_collision_normal()
		return [true, ray.get_collision_point(), n.normalized() if n.length() > 0.001 else Vector3.UP]
	return [false, at, Vector3.UP]


# --- leg IK ------------------------------------------------------------------

func _solve_leg(skel: Skeleton3D, leg: Leg, to_skel: Transform3D, pole: Vector3, leg_index: int) -> void:
	# Hip socket = thigh's rest head (pelvis isn't driven).
	var hip := skel.get_bone_global_rest(leg.thigh).origin

	var contact := to_skel * leg.foot_pos
	var ground_n := (to_skel.basis * leg.foot_normal).normalized()
	if ground_n.length() < 0.001:
		ground_n = (skel.global_transform.basis.inverse() * Vector3.UP).normalized()
	var up := (skel.global_transform.basis.inverse() * Vector3.UP).normalized()

	# Ankle joint = where the foot bone's head sits (foot_height above the sole).
	var ankle_joint := contact + ground_n * _config.foot_height

	# Derived hock pitch: folded under compression, straighter on the reach.
	var max_reach := leg.len_thigh + leg.len_shin + leg.len_cannon
	var t := clampf(((ankle_joint - hip).length() / max_reach - 0.5) / 0.45, 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(_config.cannon_pitch_folded, _config.cannon_pitch_extended, t))

	var rearward := -pole
	var hock := ankle_joint + (up * cos(pitch) + rearward * sin(pitch)).normalized() * leg.len_cannon

	# 2-bone IK with the knee constrained to the plane perpendicular to skel-X
	# through the hock. For straight stride hock.X is constant, so knee.X is
	# constant and the thigh has no yaw variation. Strafing moves hock.X, the
	# knee follows, and the thigh yaws naturally — exactly the desired feel.
	var knee := _solve_two_bone_plane(hip, hock, leg.len_thigh, leg.len_shin, pole, Vector3(1, 0, 0))

	# Thigh: ball-cone aim at the (plane-constrained) knee.
	# Shin / cannon: 1-DOF hinges around the authored axes (skel space).
	var g_pelvis := skel.get_bone_global_rest(skel.get_bone_parent(leg.thigh))
	var g_thigh  := _aim_bone_cone(skel, leg.thigh, g_pelvis, knee, _config.thigh_cone_deg)
	var g_shin   := _aim_bone_hinge(skel, leg.shin,   g_thigh, hock,        _config.shin_hinge_axis,   _config.shin_min_deg,   _config.shin_max_deg)
	var g_cannon := _aim_bone_hinge(skel, leg.cannon, g_shin,  ankle_joint, _config.cannon_hinge_axis, _config.cannon_min_deg, _config.cannon_max_deg)

	# Foot (ball): aim along chassis forward, projected onto the ground plane,
	# so the bone lies flat along the slope. Target distance is arbitrary —
	# `_aim_bone_cone` only uses the direction.
	var foot_fwd := pole - ground_n * pole.dot(ground_n)
	if foot_fwd.length() < 0.001:
		foot_fwd = pole
	foot_fwd = foot_fwd.normalized()
	_aim_bone_cone(skel, leg.foot, g_cannon, ankle_joint + foot_fwd, _config.foot_cone_deg)

	if debug_draw:
		var b := leg_index * 4
		_dbg_point(skel, b + 0, Color.WHITE,         hip)
		_dbg_point(skel, b + 1, Color.GREEN,         knee)
		_dbg_point(skel, b + 2, Color.DEEP_SKY_BLUE, hock)
		_dbg_point(skel, b + 3, Color.YELLOW if leg.state == FootState.STEPPING else Color.RED, contact)


func _dbg_point(skel: Skeleton3D, idx: int, color: Color, local_pos: Vector3) -> void:
	while _dbg.size() <= idx:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08; sm.height = 0.16; sm.radial_segments = 8; sm.rings = 4
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


# Free aim with the swing clamped to a cone around the bone's rest direction.
# Used for the thigh and foot ball joints.
func _aim_bone_cone(skel: Skeleton3D, b: int, g_parent: Transform3D, tip: Vector3, cone_deg: float) -> Transform3D:
	var rest_local := skel.get_bone_rest(b)
	var head: Vector3 = g_parent * rest_local.origin
	var rest_aim := (g_parent.basis * (rest_local.basis * Vector3.UP)).normalized()
	var to_tip := tip - head
	var dir := to_tip.normalized() if to_tip.length() > 0.0001 else rest_aim

	var cos_lim := cos(deg_to_rad(maxf(cone_deg, 0.0)))
	var cos_cur := clampf(rest_aim.dot(dir), -1.0, 1.0)
	if cos_cur < cos_lim:
		var axis := rest_aim.cross(dir)
		if axis.length() > 0.0001:
			dir = rest_aim.rotated(axis.normalized(), deg_to_rad(cone_deg))
		else:
			dir = rest_aim

	var aimed_basis := _basis_aim_y(dir, skel.get_bone_global_rest(b).basis)
	var g := Transform3D(aimed_basis, head)
	skel.set_bone_pose_position(b, rest_local.origin)
	skel.set_bone_pose_rotation(b, (g_parent.affine_inverse() * g).basis.get_rotation_quaternion())
	skel.set_bone_pose_scale(b, Vector3.ONE)
	return g


# Single-axis hinge aim: the bone rotates only around hinge_axis_skel (expressed
# in skeleton space, per MechConfig). The angle is chosen to best aim its rest
# +Y at `tip`, then clamped to [min_deg, max_deg] (relative to rest = 0°).
# Targets out of the hinge plane project onto it — i.e. the bone aims as close
# as a hinge can.
func _aim_bone_hinge(skel: Skeleton3D, b: int, g_parent: Transform3D, tip: Vector3,
		hinge_axis_skel: Vector3, min_deg: float, max_deg: float) -> Transform3D:
	var rest_local := skel.get_bone_rest(b)
	var head: Vector3 = g_parent * rest_local.origin

	var axis_skel := hinge_axis_skel
	if axis_skel.length() < 0.0001:
		axis_skel = Vector3.RIGHT
	axis_skel = axis_skel.normalized()

	var rest_aim := (g_parent.basis * (rest_local.basis * Vector3.UP)).normalized()
	var desired := tip - head
	desired = desired.normalized() if desired.length() > 0.0001 else rest_aim

	# Project rest and desired onto the plane perpendicular to the hinge axis,
	# then take the signed angle between them around that axis.
	var proj_rest := rest_aim - axis_skel * rest_aim.dot(axis_skel)
	var proj_des  := desired   - axis_skel * desired.dot(axis_skel)
	var theta := 0.0
	if proj_rest.length() > 0.0001 and proj_des.length() > 0.0001:
		proj_rest = proj_rest.normalized()
		proj_des  = proj_des.normalized()
		theta = atan2(axis_skel.dot(proj_rest.cross(proj_des)), proj_rest.dot(proj_des))
	theta = clampf(theta, deg_to_rad(min_deg), deg_to_rad(max_deg))

	# Compose: rest_quat (rest local rotation) then hinge rotation, both in the
	# parent's current local frame. axis is moved into parent-local first.
	var axis_parent_local := (g_parent.basis.inverse() * axis_skel).normalized()
	var rest_quat := rest_local.basis.get_rotation_quaternion()
	var pose_rot := Quaternion(axis_parent_local, theta) * rest_quat

	skel.set_bone_pose_position(b, rest_local.origin)
	skel.set_bone_pose_rotation(b, pose_rot)
	skel.set_bone_pose_scale(b, Vector3.ONE)

	return Transform3D(g_parent.basis * Basis(pose_rot), head)


# --- math helpers ------------------------------------------------------------

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
	return root + dir.rotated(axis, angle) * l1


# Like _solve_two_bone, but the knee is constrained to the plane perpendicular
# to `plane_axis` passing through `target` (the hock). The thigh spends its
# `plane_axis`-component traversing from root to the plane; the in-plane bone
# IK then places the knee. Keeps the knee's `plane_axis`-coordinate equal to
# the target's, which is what stops yaw from creeping in during straight stride.
static func _solve_two_bone_plane(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3, plane_axis: Vector3) -> Vector3:
	var n := plane_axis.normalized()
	if n.length() < 0.001:
		return _solve_two_bone(root, target, l1, l2, pole)

	# Signed distance from root to the plane (through target with normal n).
	var off := n.dot(root - target)
	var root_proj := root - n * off

	# Effective thigh length *in the plane* — 3D distance from root to knee
	# stays l1 because the bone spends `off` traversing out of plane.
	var eff_l1_sq := l1 * l1 - off * off
	if eff_l1_sq <= 0.0:
		return _solve_two_bone(root, target, l1, l2, pole)
	var eff_l1: float = sqrt(eff_l1_sq)

	var to_t := target - root_proj
	var dist := clampf(to_t.length(), absf(eff_l1 - l2) + 0.001, eff_l1 + l2 - 0.001)
	var dir := to_t.normalized()
	var cos_a := clampf((eff_l1 * eff_l1 + dist * dist - l2 * l2) / (2.0 * eff_l1 * dist), -1.0, 1.0)
	var angle := acos(cos_a)

	# Pole projected onto the plane — the knee bends toward this in-plane pole.
	var pole_in := pole - n * pole.dot(n)
	if pole_in.length() < 0.001:
		pole_in = pole
	pole_in = pole_in.normalized()

	var axis := dir.cross(pole_in)
	if axis.length() < 0.001:
		axis = n
	axis = axis.normalized()
	return root_proj + dir.rotated(axis, angle) * eff_l1


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


# --- editor overlay ----------------------------------------------------------
# Draws constraint arcs and gait zones directly into an ImmediateMesh child.
# Only exists at edit time; no-depth-test so it always renders on top.

func _rebuild_overlay() -> void:
	if not Engine.is_editor_hint():
		return
	if not is_instance_valid(_overlay_instance):
		_overlay_mat = StandardMaterial3D.new()
		_overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay_mat.no_depth_test = true
		_overlay_mat.vertex_color_use_as_albedo = true
		_overlay_mat.disable_receive_shadows = true
		_overlay_mesh = ImmediateMesh.new()
		_overlay_instance = MeshInstance3D.new()
		_overlay_instance.mesh = _overlay_mesh
		_overlay_instance.material_override = _overlay_mat
		_overlay_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# INTERNAL_MODE_FRONT hides this from the scene tree panel
		add_child(_overlay_instance, false, Node.INTERNAL_MODE_FRONT)

	_overlay_mesh.clear_surfaces()
	var skel := get_skeleton()
	if skel == null or _config == null:
		return

	_overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for sfx: String in [SUFFIX_L, SUFFIX_R]:
		# thigh ball — cone centred on its rest +Y
		var thigh_idx := skel.find_bone(BONE_THIGH + sfx)
		if thigh_idx >= 0:
			var r := skel.get_bone_global_rest(thigh_idx)
			_ol_cone(r.origin, r.basis.y,
					_config.thigh_cone_deg, 0.18, Color(0.85, 0.2, 1.0))

		# shin hinge
		var shin_idx := skel.find_bone(BONE_SHIN + sfx)
		if shin_idx >= 0:
			var r := skel.get_bone_global_rest(shin_idx)
			_ol_hinge(r.origin, _config.shin_hinge_axis, r.basis.y,
					_config.shin_min_deg, _config.shin_max_deg, 0.18, Color(0.15, 0.85, 1.0))

		# cannon hinge
		var cannon_idx := skel.find_bone(BONE_CANNON + sfx)
		if cannon_idx >= 0:
			var r := skel.get_bone_global_rest(cannon_idx)
			_ol_hinge(r.origin, _config.cannon_hinge_axis, r.basis.y,
					_config.cannon_min_deg, _config.cannon_max_deg, 0.15, Color(0.15, 0.85, 1.0))

		# foot ball — cone centred on its rest +Y
		var foot_idx := skel.find_bone(BONE_FOOT + sfx)
		if foot_idx >= 0:
			var r := skel.get_bone_global_rest(foot_idx)
			_ol_cone(r.origin, r.basis.y,
					_config.foot_cone_deg, 0.12, Color(0.85, 0.2, 1.0))

		# gait zone: step-trigger circle at foot level + step-height bar
		if thigh_idx >= 0 and foot_idx >= 0:
			var hip_xz := skel.get_bone_global_rest(thigh_idx).origin
			var foot_y := skel.get_bone_global_rest(foot_idx).origin.y
			var zone   := Vector3(hip_xz.x, foot_y, hip_xz.z)
			_ol_circle_xz(zone, _config.step_trigger_dist, Color(1.0, 0.85, 0.1))
			_ol_line(zone, zone + Vector3.UP * _config.step_height, Color(1.0, 0.5, 0.1))

	_overlay_mesh.surface_end()


func _ol_line(a: Vector3, b: Vector3, c: Color) -> void:
	_overlay_mesh.surface_set_color(c)
	_overlay_mesh.surface_add_vertex(a)
	_overlay_mesh.surface_set_color(c)
	_overlay_mesh.surface_add_vertex(b)


# Fan arc: min_deg to max_deg around `axis`, rest direction at 0° is `rest_dir`.
func _ol_hinge(origin: Vector3, axis: Vector3, rest_dir: Vector3,
		min_deg: float, max_deg: float, radius: float, color: Color) -> void:
	const STEPS := 24
	var prev := origin + rest_dir.rotated(axis, deg_to_rad(min_deg)) * radius
	_ol_line(origin, prev, color)
	for i in range(1, STEPS + 1):
		var p := origin + rest_dir.rotated(axis, lerpf(deg_to_rad(min_deg), deg_to_rad(max_deg), float(i) / STEPS)) * radius
		_ol_line(prev, p, color)
		prev = p
	_ol_line(origin, prev, color)


# Cone ring at `cone_deg` from `axis`, four spokes back to origin.
func _ol_cone(origin: Vector3, axis: Vector3, cone_deg: float, radius: float, color: Color) -> void:
	const STEPS := 32
	var dir    := axis.normalized()
	var centre := origin + dir * (cos(deg_to_rad(cone_deg)) * radius)
	var cone_r := sin(deg_to_rad(cone_deg)) * radius
	var perp   := dir.cross(Vector3.UP)
	if perp.length() < 0.001:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var ring: Array[Vector3] = []
	for i in STEPS:
		ring.append(centre + perp.rotated(dir, float(i) / STEPS * TAU) * cone_r)
	for i in STEPS:
		_ol_line(ring[i], ring[(i + 1) % STEPS], color)
	for i in [0, STEPS / 4, STEPS / 2, (3 * STEPS) / 4]:
		_ol_line(origin, ring[i], color)


# Flat circle in the XZ plane.
func _ol_circle_xz(centre: Vector3, radius: float, color: Color) -> void:
	const STEPS := 32
	var prev := centre + Vector3(radius, 0.0, 0.0)
	for i in range(1, STEPS + 1):
		var a := float(i) / STEPS * TAU
		var p := centre + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		_ol_line(prev, p, color)
		prev = p
