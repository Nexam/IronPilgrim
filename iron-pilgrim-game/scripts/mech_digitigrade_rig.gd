extends SkeletonModifier3D
class_name MechDigitigradeRig

## Step 1 — foot-lock IK. Each update: raycast under each hip, plant the foot on
## the ground, and solve the digitigrade leg so it articulates as the chassis
## moves over terrain. The pelvis bone is NOT driven yet (the camera still rides
## the Skeleton3D node). The gait state machine and pelvis solve come next.
##
## Bone chain per side: tigh -> shin -> cannon -> foot.
##   - analytic 2-bone IK solves tigh+shin from the hip to the "hock"
##     (the joint at the top of the cannon),
##   - the cannon then aims from the hock to the ground contact,
##   - the foot lies along the ground.
## Segment lengths are read from the rest pose, so this adapts to any biped mech
## that uses the same bone names.
##
## This is a first pass — expect to flip a sign or two and tune the exports in
## the editor. If the stifle bends backward, flip `knee_pole`; if the whole leg
## looks inside-out, flip the rotation sign in `_solve_two_bone`.

# --- wiring (assign in the editor) ---------------------------------------
@export var chassis: CharacterBody3D
@export var foot_ray_l: RayCast3D
@export var foot_ray_r: RayCast3D

# --- bone names (match the current .glb; the armature uses "tigh", sic) ---
@export var seg_thigh := "thigh"
@export var seg_shin := "shin"
@export var seg_cannon := "cannon"
@export var seg_foot := "foot"
@export var suffix_l := ".L"
@export var suffix_r := ".R"

# --- tuning ---------------------------------------------------------------
## Cannon lean away from vertical. 0 = plantigrade-ish; ~30-45 = the digitigrade Z.
@export_range(0.0, 80.0, 1.0) var cannon_pitch_deg := 35.0
## Direction the stifle ("knee") bends, in chassis space. FORWARD = forward.
@export var knee_pole := Vector3.FORWARD
## How far a foot reaches straight down when the raycast finds no ground.
@export var max_drop := 3.0
## Height of the foot joint above the sole (ground contact). The cannon aims to
## contact + up * foot_height so the joint sits at the right elevation.
@export_range(0.0, 1.0, 0.01) var foot_height := 0.15
## Draw small spheres at each leg's hip (white) / knee (green) / hock (blue) / contact (red).
@export var debug_draw := false

class Leg:
	var thigh := -1
	var shin := -1
	var cannon := -1
	var foot := -1
	var ray: RayCast3D
	var len_thigh := 0.0
	var len_shin := 0.0
	var len_cannon := 0.0
	func ok() -> bool:
		return thigh >= 0 and shin >= 0 and cannon >= 0 and foot >= 0

# The armature currently uses the (sic) "tigh"; accept either spelling so the
# rig keeps working after a corrected re-export.
const _THIGH_ALIASES := ["tigh", "thigh"]

var _legs: Array[Leg] = []
var _ready_ok := false
var _setup_done := false
var _dbg: Array[MeshInstance3D] = []


func _find_seg(skel: Skeleton3D, base: String, sfx: String) -> int:
	var i := skel.find_bone(base + sfx)
	if i < 0 and base in _THIGH_ALIASES:
		for alt: String in _THIGH_ALIASES:
			i = skel.find_bone(alt + sfx)
			if i >= 0:
				break
	return i


func _setup(skel: Skeleton3D) -> void:
	_legs.clear()
	for spec: Array in [[suffix_l, foot_ray_l], [suffix_r, foot_ray_r]]:
		var sfx: String = spec[0]
		var leg := Leg.new()
		leg.thigh = _find_seg(skel, seg_thigh, sfx)
		leg.shin = _find_seg(skel, seg_shin, sfx)
		leg.cannon = _find_seg(skel, seg_cannon, sfx)
		leg.foot = _find_seg(skel, seg_foot, sfx)
		leg.ray = spec[1]
		if not leg.ok():
			push_warning("MechDigitigradeRig: missing leg bones for suffix '%s' (found tigh=%d shin=%d cannon=%d foot=%d)" % [sfx, leg.thigh, leg.shin, leg.cannon, leg.foot])
			continue
		# segment length = distance from this bone's joint to the next joint,
		# which is the child bone's rest offset along its parent.
		leg.len_thigh = skel.get_bone_rest(leg.shin).origin.length()
		leg.len_shin = skel.get_bone_rest(leg.cannon).origin.length()
		leg.len_cannon = skel.get_bone_rest(leg.foot).origin.length()
		_legs.append(leg)
	_ready_ok = _legs.size() > 0
	if _ready_ok:
		for i in _legs.size():
			var l := _legs[i]
			print("MechDigitigradeRig: leg %d bound — thigh=%d shin=%d cannon=%d foot=%d  lengths=(%.2f, %.2f, %.2f)" % [i, l.thigh, l.shin, l.cannon, l.foot, l.len_thigh, l.len_shin, l.len_cannon])


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

	var to_skel := skel.global_transform.affine_inverse() # world -> skeleton-local
	# stifle pole, in skeleton-local space
	var pole := Vector3.FORWARD
	if chassis != null:
		pole = (to_skel.basis * (chassis.global_transform.basis * knee_pole)).normalized()
	if pole.length() < 0.001:
		pole = Vector3.FORWARD

	for i in _legs.size():
		_solve_leg(skel, _legs[i], to_skel, pole, i)


func _solve_leg(skel: Skeleton3D, leg: Leg, to_skel: Transform3D, pole: Vector3, leg_index: int) -> void:
	# hip joint, skeleton-local. The pelvis is undriven, so rest == current.
	var hip := skel.get_bone_global_rest(leg.thigh).origin

	# ground contact + normal, skeleton-local
	var contact: Vector3
	var ground_n := skel.global_transform.basis.inverse() * Vector3.UP
	if leg.ray != null and leg.ray.is_colliding():
		contact = to_skel * leg.ray.get_collision_point()
		ground_n = (to_skel.basis * leg.ray.get_collision_normal()).normalized()
	else:
		var reach := minf(max_drop, leg.len_thigh + leg.len_shin + leg.len_cannon - 0.05)
		var hip_world := skel.global_transform * hip
		contact = to_skel * (hip_world + Vector3.DOWN * reach)

	# hock = up-and-rearward from the foot joint by the cannon, leaned by the pitch
	var pitch := deg_to_rad(cannon_pitch_deg)
	var up := skel.global_transform.basis.inverse() * Vector3.UP
	var rearward := -pole
	# foot_joint is the bone origin — above the sole by foot_height
	var foot_joint := contact + up * foot_height
	var hock := foot_joint + (up * cos(pitch) + rearward * sin(pitch)).normalized() * leg.len_cannon

	# 2-bone IK: tigh + shin from hip to hock
	var knee := _solve_two_bone(hip, hock, leg.len_thigh, leg.len_shin, pole)

	# write poses parent-first, accumulating global transforms ourselves so we
	# don't depend on get_bone_global_pose() reflecting writes mid-modification.
	var g_parent := skel.get_bone_global_pose(skel.get_bone_parent(leg.thigh))
	var g_thigh := _aim_bone(skel, leg.thigh, g_parent, hip, knee)
	var g_shin := _aim_bone(skel, leg.shin, g_thigh, knee, hock)
	var g_cannon := _aim_bone(skel, leg.cannon, g_shin, hock, foot_joint)
	# foot: lie along the ground (forward projected onto the ground plane)
	var foot_dir := (pole - ground_n * pole.dot(ground_n))
	if foot_dir.length() < 0.01:
		foot_dir = pole
	_aim_bone(skel, leg.foot, g_cannon, foot_joint, foot_joint + foot_dir.normalized())

	if debug_draw:
		var b := leg_index * 4
		_dbg_point(skel, b + 0, Color.WHITE, hip)
		_dbg_point(skel, b + 1, Color.GREEN, knee)
		_dbg_point(skel, b + 2, Color.DEEP_SKY_BLUE, hock)
		_dbg_point(skel, b + 3, Color.RED, contact)


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


# Places bone `b` so its local +Y points from `head` toward `tip` (all
# skeleton-local). Returns the bone's new skeleton-local transform for chaining.
func _aim_bone(skel: Skeleton3D, b: int, g_parent: Transform3D, head: Vector3, tip: Vector3) -> Transform3D:
	var rest_g := skel.get_bone_global_rest(b)
	var g := Transform3D(_basis_aim_y(tip - head, rest_g.basis), head)
	var local := g_parent.affine_inverse() * g
	skel.set_bone_pose_position(b, local.origin)
	skel.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
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
