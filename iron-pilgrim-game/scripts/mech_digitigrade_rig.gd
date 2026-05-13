@tool
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
## `torso`); the pelvis solve is the next step.

# Bone name contract — fixed across all biped mechs.
# "tigh" fallback kept until the mk2 blockout is re-exported from Blender.
const BONE_THIGH_ROLL  := "thigh_roll"
const BONE_THIGH       := "thigh"
const BONE_SHIN        := "shin"
const BONE_CANNON      := "cannon"
const BONE_ANKLE_PITCH := "ankle_pitch"
const BONE_ANKLE_ROLL  := "ankle_roll"
const SUFFIX_L         := ".L"
const SUFFIX_R         := ".R"

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
	var thigh_roll := -1
	var thigh := -1
	var shin := -1
	var cannon := -1
	var ankle_pitch := -1
	var ankle_roll := -1
	var ray: RayCast3D
	var len_thigh_roll := 0.0
	var len_thigh := 0.0
	var len_shin := 0.0
	var len_cannon := 0.0
	var len_ankle_pitch := 0.0
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
		return thigh_roll >= 0 and thigh >= 0 and shin >= 0 and cannon >= 0 \
			and ankle_pitch >= 0 and ankle_roll >= 0

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
		var thigh_name := BONE_THIGH if skel.find_bone(BONE_THIGH + sfx) >= 0 else "tigh"
		leg.thigh_roll  = skel.find_bone(BONE_THIGH_ROLL  + sfx)
		leg.thigh       = skel.find_bone(thigh_name       + sfx)
		leg.shin        = skel.find_bone(BONE_SHIN        + sfx)
		leg.cannon      = skel.find_bone(BONE_CANNON      + sfx)
		leg.ankle_pitch = skel.find_bone(BONE_ANKLE_PITCH + sfx)
		leg.ankle_roll  = skel.find_bone(BONE_ANKLE_ROLL  + sfx)
		leg.ray = spec[1]
		if not leg.ok():
			push_warning("MechDigitigradeRig: missing leg bones for suffix '%s' (thigh_roll=%d thigh=%d shin=%d cannon=%d ankle_pitch=%d ankle_roll=%d)" % [sfx, leg.thigh_roll, leg.thigh, leg.shin, leg.cannon, leg.ankle_pitch, leg.ankle_roll])
			continue
		leg.len_thigh_roll  = skel.get_bone_rest(leg.thigh).origin.length()
		leg.len_thigh       = skel.get_bone_rest(leg.shin).origin.length()
		leg.len_shin        = skel.get_bone_rest(leg.cannon).origin.length()
		leg.len_cannon      = skel.get_bone_rest(leg.ankle_pitch).origin.length()
		leg.len_ankle_pitch = skel.get_bone_rest(leg.ankle_roll).origin.length()
		if leg.ray != null and chassis != null:
			leg.ray.add_exception(chassis)
		_legs.append(leg)
	_ready_ok = _legs.size() > 0
	if _ready_ok:
		for i in _legs.size():
			var l := _legs[i]
			print("MechDigitigradeRig: leg %d bound — lengths roll=%.2f thigh=%.2f shin=%.2f cannon=%.2f ankle=%.2f" % [i, l.len_thigh_roll, l.len_thigh, l.len_shin, l.len_cannon, l.len_ankle_pitch])


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

		var hip_world: Vector3 = skel.global_transform * skel.get_bone_global_rest(leg.thigh).origin
		var ideal_from := hip_world + vel_h * _config.step_lead_time
		var ground := _ground_under(leg.ray, ideal_from)
		var ideal_pos: Vector3 = ground[1] if ground[0] else Vector3(ideal_from.x, hip_world.y - _config.max_drop, ideal_from.z)
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
	var hip := skel.get_bone_global_rest(leg.thigh).origin

	var contact := to_skel * leg.foot_pos
	var ground_n := (to_skel.basis * leg.foot_normal).normalized()
	if ground_n.length() < 0.001:
		ground_n = (skel.global_transform.basis.inverse() * Vector3.UP).normalized()
	var up := (skel.global_transform.basis.inverse() * Vector3.UP).normalized()

	var ankle_joint := contact + ground_n * _config.foot_height
	var max_reach := leg.len_thigh + leg.len_shin + leg.len_cannon
	var t := clampf(((ankle_joint - hip).length() / max_reach - 0.5) / 0.45, 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(_config.cannon_pitch_folded, _config.cannon_pitch_extended, t))

	var rearward := -pole
	var hock := ankle_joint + (up * cos(pitch) + rearward * sin(pitch)).normalized() * leg.len_cannon

	var knee := _solve_two_bone(hip, hock, leg.len_thigh, leg.len_shin, pole)

	var g_pelvis := skel.get_bone_global_rest(skel.get_bone_parent(leg.thigh_roll))
	var g_roll   := _aim_bone(skel, leg.thigh_roll,  g_pelvis, hip)
	var g_thigh  := _aim_bone(skel, leg.thigh,        g_roll,   knee)
	var g_shin   := _aim_bone(skel, leg.shin,          g_thigh,  hock)
	var g_cannon := _aim_bone(skel, leg.cannon,        g_shin,   ankle_joint)
	var g_ap     := _aim_bone(skel, leg.ankle_pitch,  g_cannon, contact)
	_aim_bone(skel, leg.ankle_roll, g_ap, contact)

	if debug_draw:
		var b := leg_index * 4
		_dbg_point(skel, b + 0, Color.WHITE,        hip)
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


func _aim_bone(skel: Skeleton3D, b: int, g_parent: Transform3D, tip: Vector3) -> Transform3D:
	var rest_local_pos := skel.get_bone_rest(b).origin
	var head: Vector3 = g_parent * rest_local_pos
	var aimed_basis := _basis_aim_y(tip - head, skel.get_bone_global_rest(b).basis)
	var g := Transform3D(aimed_basis, head)
	skel.set_bone_pose_position(b, rest_local_pos)
	skel.set_bone_pose_rotation(b, (g_parent.affine_inverse() * g).basis.get_rotation_quaternion())
	skel.set_bone_pose_scale(b, Vector3.ONE)
	return g


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
		# ball joint — cone always centred on the bone's rest direction (basis.y)
		var tr_idx := skel.find_bone(BONE_THIGH_ROLL + sfx)
		if tr_idx >= 0:
			var r := skel.get_bone_global_rest(tr_idx)
			_ol_cone(r.origin, r.basis.y,
					_config.thigh_roll_cone_deg, 0.14, Color(0.85, 0.2, 1.0))

		# thigh hinge — axis in skeleton space
		var thigh_idx := skel.find_bone(BONE_THIGH + sfx)
		if thigh_idx < 0:
			thigh_idx = skel.find_bone("tigh" + sfx)
		if thigh_idx >= 0:
			var r := skel.get_bone_global_rest(thigh_idx)
			_ol_hinge(r.origin, _config.thigh_hinge_axis, r.basis.y,
					_config.thigh_min_deg, _config.thigh_max_deg, 0.20, Color(0.15, 0.85, 1.0))

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

		# ankle_pitch hinge
		var ap_idx := skel.find_bone(BONE_ANKLE_PITCH + sfx)
		if ap_idx >= 0:
			var r := skel.get_bone_global_rest(ap_idx)
			_ol_hinge(r.origin, _config.ankle_pitch_hinge_axis, r.basis.y,
					_config.ankle_pitch_min_deg, _config.ankle_pitch_max_deg, 0.12, Color(0.15, 0.85, 1.0))

		# ankle_roll hinge
		var ar_idx := skel.find_bone(BONE_ANKLE_ROLL + sfx)
		if ar_idx >= 0:
			var r := skel.get_bone_global_rest(ar_idx)
			_ol_hinge(r.origin, _config.ankle_roll_hinge_axis, r.basis.y,
					_config.ankle_roll_min_deg, _config.ankle_roll_max_deg, 0.10, Color(0.15, 0.85, 1.0))

		# gait zone: step-trigger circle at foot level + step-height bar
		if thigh_idx >= 0 and ar_idx >= 0:
			var hip_xz := skel.get_bone_global_rest(thigh_idx).origin
			var foot_y := skel.get_bone_global_rest(ar_idx).origin.y
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
