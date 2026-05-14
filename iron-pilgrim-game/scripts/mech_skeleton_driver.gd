extends SkeletonModifier3D
class_name MechSkeletonDriver

class Leg:
	var foot_target: Node3D

	var thigh_name := ""
	var shin_name := ""
	var cannon_name := ""
	var foot_name := ""

	var thigh_id := -1
	var shin_id := -1
	var cannon_id := -1
	var foot_id := -1

	var thigh_length := 0.0
	var shin_length := 0.0
	var cannon_length := 0.0

	var thigh_aim_axis := Vector3.UP
	var shin_aim_axis := Vector3.UP

	var thigh_rotation_correction := Vector3.ZERO
	var shin_rotation_correction := Vector3.ZERO
	var cannon_rotation_correction := Vector3.ZERO
	var foot_rotation_correction := Vector3.ZERO


@export_category("Targets")
@export var pelvis_target: Node3D
@export var left_foot_target: Node3D
@export var right_foot_target: Node3D
@export var torso_target: Node3D

@export_category("Pelvis")
@export var pelvis_bone_name := "pelvis"

@export_category("Torso")
@export var torso_bone_name := "torso"
@export var torso_rotation_correction := Vector3.ZERO



@export_category("Left leg bones")
@export var left_thigh_bone_name := "thigh.L"
@export var left_shin_bone_name := "shin.L"
@export var left_cannon_bone_name := "cannon.L"
@export var left_foot_bone_name := "foot.L"

@export_category("Right leg bones")
@export var right_thigh_bone_name := "thigh.R"
@export var right_shin_bone_name := "shin.R"
@export var right_cannon_bone_name := "cannon.R"
@export var right_foot_bone_name := "foot.R"

@export_category("Shared config")
@export var foot_y_offset := 0.23
@export var thigh_aim_axis := Vector3.UP
@export var shin_aim_axis := Vector3.UP

@export_group("Left corrections")
@export var left_thigh_rotation_correction := Vector3.ZERO
@export var left_shin_rotation_correction := Vector3.ZERO
@export var left_cannon_rotation_correction := Vector3(0.0, 90.0, 0.0)
@export var left_foot_rotation_correction := Vector3(0.0, 0.0, -90.0)

@export_group("Right corrections")
@export var right_thigh_rotation_correction := Vector3.ZERO
@export var right_shin_rotation_correction := Vector3.ZERO
@export var right_cannon_rotation_correction := Vector3(0.0, 90.0, 0.0)
@export var right_foot_rotation_correction := Vector3(0.0, 0.0, -90.0)

@export_group("Other corrections")
@export var pelvis_rotation_correction := Vector3.ZERO

@export_category("Debug")
@export var draw_debug := true

var pelvis_bone_id := -1
var torso_bone_id := -1

var left_leg: Leg
var right_leg: Leg


func _ready() -> void:
	pelvis_bone_id = _find_bone_id(pelvis_bone_name)
	torso_bone_id = _find_bone_id(torso_bone_name)

	left_leg = _create_leg(
		left_foot_target,
		left_thigh_bone_name,
		left_shin_bone_name,
		left_cannon_bone_name,
		left_foot_bone_name,
		left_thigh_rotation_correction,
		left_shin_rotation_correction,
		left_cannon_rotation_correction,
		left_foot_rotation_correction
	)

	right_leg = _create_leg(
		right_foot_target,
		right_thigh_bone_name,
		right_shin_bone_name,
		right_cannon_bone_name,
		right_foot_bone_name,
		right_thigh_rotation_correction,
		right_shin_rotation_correction,
		right_cannon_rotation_correction,
		right_foot_rotation_correction
	)


func _process_modification() -> void:
	if pelvis_bone_id == -1 or pelvis_target == null:
		return

	_drive_pelvis()
	_drive_torso()
	_solve_leg(left_leg)
	_solve_leg(right_leg)

	if draw_debug:
		_debug_leg(left_leg, Color.RED, Color.YELLOW, Color.CYAN)
		_debug_leg(right_leg, Color.ORANGE, Color.GREEN, Color.BLUE)

func _drive_torso() -> void:
	if torso_bone_id == -1 or torso_target == null:
		return

	var skeleton := get_skeleton()
	var skeleton_inv := skeleton.global_transform.affine_inverse()

	var target_basis_skeleton := skeleton_inv.basis * torso_target.global_transform.basis
	target_basis_skeleton *= _basis_from_degrees(torso_rotation_correction)

	var parent_id := skeleton.get_bone_parent(torso_bone_id)
	var parent_global_pose := Transform3D.IDENTITY

	if parent_id != -1:
		parent_global_pose = skeleton.get_bone_global_pose(parent_id)

	var current_global_pose := skeleton.get_bone_global_pose(torso_bone_id)
	current_global_pose.basis = target_basis_skeleton

	var local_pose := parent_global_pose.affine_inverse() * current_global_pose

	skeleton.set_bone_pose_rotation(
		torso_bone_id,
		local_pose.basis.get_rotation_quaternion()
	)
	
func _create_leg(
	foot_target: Node3D,
	thigh_name: String,
	shin_name: String,
	cannon_name: String,
	foot_name: String,
	thigh_correction: Vector3,
	shin_correction: Vector3,
	cannon_correction: Vector3,
	foot_correction: Vector3
) -> Leg:
	var leg := Leg.new()

	leg.foot_target = foot_target

	leg.thigh_name = thigh_name
	leg.shin_name = shin_name
	leg.cannon_name = cannon_name
	leg.foot_name = foot_name

	leg.thigh_id = _find_bone_id(thigh_name)
	leg.shin_id = _find_bone_id(shin_name)
	leg.cannon_id = _find_bone_id(cannon_name)
	leg.foot_id = _find_bone_id(foot_name)

	leg.thigh_length = _get_bone_length_to_child(leg.thigh_id, leg.shin_id)
	leg.shin_length = _get_bone_length_to_child(leg.shin_id, leg.cannon_id)
	leg.cannon_length = _get_bone_length_to_child(leg.cannon_id, leg.foot_id)

	leg.thigh_aim_axis = thigh_aim_axis
	leg.shin_aim_axis = shin_aim_axis

	leg.thigh_rotation_correction = thigh_correction
	leg.shin_rotation_correction = shin_correction
	leg.cannon_rotation_correction = cannon_correction
	leg.foot_rotation_correction = foot_correction

	print("%s lengths | thigh: %.3f shin: %.3f cannon: %.3f" % [
		thigh_name,
		leg.thigh_length,
		leg.shin_length,
		leg.cannon_length
	])

	return leg


func _solve_leg(leg: Leg) -> void:
	if leg == null or leg.foot_target == null:
		return

	if leg.thigh_id == -1 or leg.shin_id == -1 or leg.cannon_id == -1 or leg.foot_id == -1:
		return

	var thigh_pos := _get_bone_global_position(leg.thigh_id)
	var hock_target := _get_hock_target(leg)

	var pole_dir := -global_transform.basis.z.normalized()

	var knee_pos := _solve_two_bone_joint_position(
		thigh_pos,
		hock_target,
		leg.thigh_length,
		leg.shin_length,
		pole_dir
	)

	_aim_bone_at(
		leg.thigh_id,
		knee_pos,
		leg.thigh_aim_axis,
		leg.thigh_rotation_correction
	)

	_aim_bone_at(
		leg.shin_id,
		hock_target,
		leg.shin_aim_axis,
		leg.shin_rotation_correction
	)

	var foot_offset := leg.foot_target.global_transform.basis.y.normalized() * foot_y_offset
	var foot_bone_target := leg.foot_target.global_position + foot_offset

	_look_at_bone_y_axis(
		leg.cannon_id,
		foot_bone_target,
		leg.cannon_rotation_correction
	)

	_drive_bone_position(leg.foot_id, leg.foot_target, foot_offset)
	_drive_bone_rotation_from_target(
		leg.foot_id,
		leg.foot_target,
		leg.foot_rotation_correction
	)


func _get_hock_target(leg: Leg) -> Vector3:
	var foot_pos := leg.foot_target.global_position
	var foot_up := leg.foot_target.global_transform.basis.y.normalized()
	return foot_pos + foot_up * leg.cannon_length


func _drive_pelvis() -> void:
	var skeleton := get_skeleton()
	var skeleton_inv := skeleton.global_transform.affine_inverse()

	var target_in_skeleton_space := skeleton_inv * pelvis_target.global_position

	var parent_id := skeleton.get_bone_parent(pelvis_bone_id)
	var parent_global_pose := Transform3D.IDENTITY

	if parent_id != -1:
		parent_global_pose = skeleton.get_bone_global_pose(parent_id)

	var target_global_pose := skeleton.get_bone_global_pose(pelvis_bone_id)
	target_global_pose.origin = target_in_skeleton_space
	target_global_pose.basis = skeleton_inv.basis * pelvis_target.global_transform.basis
	target_global_pose.basis  *= _basis_from_degrees(pelvis_rotation_correction)

	var local_pose := parent_global_pose.affine_inverse() * target_global_pose
	skeleton.set_bone_pose_position(pelvis_bone_id, local_pose.origin)
	skeleton.set_bone_pose_rotation(pelvis_bone_id,	local_pose.basis.get_rotation_quaternion())

func _solve_two_bone_joint_position(
	root_pos: Vector3,
	target_pos: Vector3,
	len_a: float,
	len_b: float,
	pole_dir: Vector3
) -> Vector3:
	var to_target := target_pos - root_pos
	var dist := to_target.length()

	if dist < 0.001:
		return root_pos + pole_dir.normalized() * len_a

	dist = clampf(dist, 0.001, len_a + len_b - 0.001)

	var dir := to_target.normalized()

	var x := (len_a * len_a - len_b * len_b + dist * dist) / (2.0 * dist)
	var h_sq := maxf(len_a * len_a - x * x, 0.0)
	var h := sqrt(h_sq)

	var pole := pole_dir - dir * pole_dir.dot(dir)

	if pole.length() < 0.001:
		pole = Vector3.UP

	pole = pole.normalized()

	return root_pos + dir * x + pole * h


func _aim_bone_at(
	bone_id: int,
	target_global_pos: Vector3,
	local_aim_axis: Vector3,
	rotation_correction := Vector3.ZERO
) -> void:
	if bone_id == -1:
		return

	var skeleton := get_skeleton()
	var skeleton_inv := skeleton.global_transform.affine_inverse()

	var target_pos := skeleton_inv * target_global_pos
	var bone_global_pose := skeleton.get_bone_global_pose(bone_id)

	var bone_pos := bone_global_pose.origin
	var target_dir := target_pos - bone_pos

	if target_dir.length() < 0.001:
		return

	target_dir = target_dir.normalized()

	var current_axis := bone_global_pose.basis * local_aim_axis.normalized()
	current_axis = current_axis.normalized()

	var rotation := Quaternion(current_axis, target_dir)

	var new_global_pose := bone_global_pose
	new_global_pose.basis = Basis(rotation) * bone_global_pose.basis
	new_global_pose.basis *= _basis_from_degrees(rotation_correction)

	var parent_id := skeleton.get_bone_parent(bone_id)
	var parent_global_pose := Transform3D.IDENTITY

	if parent_id != -1:
		parent_global_pose = skeleton.get_bone_global_pose(parent_id)

	var local_pose := parent_global_pose.affine_inverse() * new_global_pose

	skeleton.set_bone_pose_rotation(
		bone_id,
		local_pose.basis.get_rotation_quaternion()
	)


func _look_at_bone_y_axis(
	bone_id: int,
	target_global_pos: Vector3,
	rotation_correction: Vector3
) -> void:
	if bone_id == -1:
		return

	var skeleton := get_skeleton()
	var skeleton_inv := skeleton.global_transform.affine_inverse()

	var target_pos := skeleton_inv * target_global_pos
	var bone_global_pose := skeleton.get_bone_global_pose(bone_id)

	var bone_pos := bone_global_pose.origin
	var dir := target_pos - bone_pos

	if dir.length() < 0.001:
		return

	dir = dir.normalized()

	var forward := -body_forward_skeleton_space()
	var right := forward.cross(dir).normalized()

	if right.length() < 0.001:
		right = Vector3.RIGHT

	var corrected_forward := dir.cross(right).normalized()

	var new_basis := Basis(right, dir, -corrected_forward)
	new_basis *= _basis_from_degrees(rotation_correction)

	var parent_id := skeleton.get_bone_parent(bone_id)
	var parent_global_pose := Transform3D.IDENTITY

	if parent_id != -1:
		parent_global_pose = skeleton.get_bone_global_pose(parent_id)

	var new_global_pose := bone_global_pose
	new_global_pose.basis = new_basis

	var local_pose := parent_global_pose.affine_inverse() * new_global_pose
	skeleton.set_bone_pose_rotation(
		bone_id,
		local_pose.basis.get_rotation_quaternion()
	)


func _drive_bone_position(bone_id: int, target: Node3D, offset: Vector3) -> void:
	if bone_id == -1 or target == null:
		return

	var skeleton := get_skeleton()
	var skeleton_inv := skeleton.global_transform.affine_inverse()

	var target_pos_skeleton := skeleton_inv * (target.global_position + offset)

	var parent_id := skeleton.get_bone_parent(bone_id)
	var parent_global_pose := Transform3D.IDENTITY

	if parent_id != -1:
		parent_global_pose = skeleton.get_bone_global_pose(parent_id)

	var current_global_pose := skeleton.get_bone_global_pose(bone_id)
	current_global_pose.origin = target_pos_skeleton

	var local_pose := parent_global_pose.affine_inverse() * current_global_pose
	skeleton.set_bone_pose_position(bone_id, local_pose.origin)


func _drive_bone_rotation_from_target(
	bone_id: int,
	target: Node3D,
	rotation_correction: Vector3
) -> void:
	if bone_id == -1 or target == null:
		return

	var skeleton := get_skeleton()
	var skeleton_inv := skeleton.global_transform.affine_inverse()

	var target_basis_skeleton := skeleton_inv.basis * target.global_transform.basis
	target_basis_skeleton *= _basis_from_degrees(rotation_correction)

	var parent_id := skeleton.get_bone_parent(bone_id)
	var parent_global_pose := Transform3D.IDENTITY

	if parent_id != -1:
		parent_global_pose = skeleton.get_bone_global_pose(parent_id)

	var current_global_pose := skeleton.get_bone_global_pose(bone_id)
	current_global_pose.basis = target_basis_skeleton

	var local_pose := parent_global_pose.affine_inverse() * current_global_pose

	skeleton.set_bone_pose_rotation(
		bone_id,
		local_pose.basis.get_rotation_quaternion()
	)


func _find_bone_id(bone_name: String) -> int:
	var id := get_skeleton().find_bone(bone_name)

	if id == -1:
		push_error("Could not find '%s' bone" % bone_name)

	return id


func _get_rest_global_pose(bone_id: int) -> Transform3D:
	var skeleton := get_skeleton()
	var pose := skeleton.get_bone_rest(bone_id)

	var parent_id := skeleton.get_bone_parent(bone_id)

	while parent_id != -1:
		pose = skeleton.get_bone_rest(parent_id) * pose
		parent_id = skeleton.get_bone_parent(parent_id)

	return pose


func _get_bone_length_to_child(bone_id: int, child_id: int) -> float:
	if bone_id == -1 or child_id == -1:
		return 0.0

	var a := _get_rest_global_pose(bone_id).origin
	var b := _get_rest_global_pose(child_id).origin

	return a.distance_to(b)


func _get_bone_global_position(bone_id: int) -> Vector3:
	return get_skeleton().global_transform * get_skeleton().get_bone_global_pose(bone_id).origin


func body_forward_skeleton_space() -> Vector3:
	var skeleton := get_skeleton()
	var world_forward := -global_transform.basis.z.normalized()
	return skeleton.global_transform.basis.inverse() * world_forward


func _basis_from_degrees(degrees: Vector3) -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(degrees.x),
		deg_to_rad(degrees.y),
		deg_to_rad(degrees.z)
	))


func _debug_leg(
	leg: Leg,
	root_color: Color,
	knee_color: Color,
	hock_color: Color
) -> void:
	if leg == null or leg.foot_target == null:
		return

	var thigh_pos := _get_bone_global_position(leg.thigh_id)
	var hock_target := _get_hock_target(leg)
	var pole_dir := -global_transform.basis.z.normalized()

	var knee_pos := _solve_two_bone_joint_position(
		thigh_pos,
		hock_target,
		leg.thigh_length,
		leg.shin_length,
		pole_dir
	)

	DebugDraw3D.draw_sphere(thigh_pos, 0.08, root_color)
	DebugDraw3D.draw_sphere(knee_pos, 0.08, knee_color)
	DebugDraw3D.draw_sphere(hock_target, 0.08, hock_color)

	DebugDraw3D.draw_line(thigh_pos, knee_pos, knee_color)
	DebugDraw3D.draw_line(knee_pos, hock_target, knee_color)
	DebugDraw3D.draw_line(hock_target, leg.foot_target.global_position, Color.GRAY)
