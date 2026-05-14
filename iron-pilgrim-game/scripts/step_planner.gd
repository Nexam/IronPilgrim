extends Node3D
class_name StepsPlanner

class Foot:
	var debug: Node3D
	var raycast: RayCast3D
	var offset: Marker3D

	var planted_pos: Vector3
	var step_from: Vector3
	var step_to: Vector3
	var t := 1.0
	var is_stepping := false
	var planted_normal := Vector3.UP
	var step_from_normal := Vector3.UP
	var step_to_normal := Vector3.UP


@onready var body: MechMk3 = $".."

@export_category("Feet config")
@export var left_debug: Node3D
@export var left_raycast: RayCast3D
@export var left_offset: Marker3D

@export var right_debug: Node3D
@export var right_raycast: RayCast3D
@export var right_offset: Marker3D

@export var pelvis_debug: Node3D

@export_category("Triggers")
@export var forward_trigger_dist := 0.85
@export var backward_trigger_dist := 1.1
@export var side_trigger_dist := 0.6

@export_category("Step config")
@export var step_duration := 0.38
@export var step_height := 0.45
@export var step_lead_distance := 0.8
@export var max_step_lead_speed := 5.0

@export_category("Pelvis debug")
@export var pelvis_height := 2.0
@export var pelvis_follow_speed := 8.0

var left_foot: Foot
var right_foot: Foot


func _ready() -> void:
	left_foot = _create_foot(left_debug, left_raycast, left_offset)
	right_foot = _create_foot(right_debug, right_raycast, right_offset)

	if pelvis_debug:
		pelvis_debug.global_position = _get_pelvis_target_position()


func _physics_process(delta: float) -> void:
	_update_foot(left_foot, right_foot, delta)
	_update_foot(right_foot, left_foot, delta)
	_update_pelvis_debug(delta)


func _create_foot(debug: Node3D, raycast: RayCast3D, offset: Marker3D) -> Foot:
	var foot := Foot.new()
	foot.debug = debug
	foot.raycast = raycast
	foot.offset = offset

	var start_pos := _raycast_ground_pos(foot, offset.global_position)

	foot.planted_pos = start_pos
	foot.step_from = start_pos
	foot.step_to = start_pos
	foot.debug.global_position = start_pos

	return foot


func _update_foot(foot: Foot, other_foot: Foot, delta: float) -> void:
	if foot.is_stepping:
		_continue_step(foot, delta)
		return

	foot.debug.global_position = foot.planted_pos

	if other_foot.is_stepping:
		return

	var neutral_ground_pos := _get_neutral_ground_pos(foot)

	if _should_step(foot, neutral_ground_pos):
		var lead_ground_pos := _get_lead_ground_pos(foot)
		_start_step(foot, lead_ground_pos)


func _should_step(foot: Foot, neutral_ground_pos: Vector3) -> bool:
	var local_error := _get_local_foot_error(foot.planted_pos, neutral_ground_pos)

	var forward_error := local_error.y
	var side_error := absf(local_error.x)

	if forward_error > forward_trigger_dist:
		return true

	if forward_error < -backward_trigger_dist:
		return true

	if side_error > side_trigger_dist:
		return true

	return false


func _start_step(foot: Foot, target_pos: Vector3) -> void:
	foot.is_stepping = true
	foot.t = 0.0
	foot.step_from = foot.planted_pos
	foot.step_to = target_pos

	foot.step_from_normal = foot.planted_normal
	foot.step_to_normal = _raycast_ground_normal(foot, target_pos)


func _continue_step(foot: Foot, delta: float) -> void:
	foot.t += delta / step_duration
	var t: float = clampf(foot.t, 0.0, 1.0)

	var pos := foot.step_from.lerp(foot.step_to, t)
	pos.y += sin(t * PI) * step_height
	
	var normal := foot.step_from_normal.slerp(foot.step_to_normal, t).normalized()
	_apply_foot_orientation(foot, normal)

	foot.debug.global_position = pos

	if t >= 1.0:
		foot.is_stepping = false
		foot.planted_pos = foot.step_to
		foot.debug.global_position = foot.planted_pos
		foot.planted_normal = foot.step_to_normal
		_apply_foot_orientation(foot, foot.planted_normal)


func _get_neutral_ground_pos(foot: Foot) -> Vector3:
	return _raycast_ground_pos(foot, foot.offset.global_position)


func _get_lead_ground_pos(foot: Foot) -> Vector3:
	var ideal_pos := foot.offset.global_position

	var velocity := body.physic_body.velocity
	velocity.y = 0.0

	if velocity.length() > 0.05:
		var speed_factor: float = clampf(velocity.length() / max_step_lead_speed, 0.0, 1.0)
		var move_dir := velocity.normalized()
		ideal_pos += move_dir * step_lead_distance * speed_factor

	return _raycast_ground_pos(foot, ideal_pos)


func _raycast_ground_pos(foot: Foot, from_pos: Vector3) -> Vector3:
	_update_ground_probe(foot, from_pos)

	if foot.raycast.is_colliding():
		return foot.raycast.get_collision_point()

	return from_pos


func _raycast_ground_normal(foot: Foot, from_pos: Vector3) -> Vector3:
	_update_ground_probe(foot, from_pos)

	if foot.raycast.is_colliding():
		return foot.raycast.get_collision_normal()

	return Vector3.UP


func _update_ground_probe(foot: Foot, from_pos: Vector3) -> void:
	foot.raycast.global_position = from_pos + Vector3.UP * 2.5
	foot.raycast.target_position = Vector3.DOWN * 5.0
	foot.raycast.force_raycast_update()


func _get_local_foot_error(from_pos: Vector3, to_pos: Vector3) -> Vector2:
	var delta := to_pos - from_pos

	var basis := body.global_transform.basis
	var right := basis.x.normalized()
	var forward := -basis.z.normalized()

	var side := delta.dot(right)
	var forward_amount := delta.dot(forward)

	return Vector2(side, forward_amount)

func _apply_foot_orientation(foot: Foot, ground_normal: Vector3) -> void:
	var forward := -body.global_transform.basis.z.normalized()

	# Remove any component going into the terrain normal.
	forward = (forward - ground_normal * forward.dot(ground_normal)).normalized()

	if forward.length() < 0.01:
		forward = -body.global_transform.basis.z.normalized()

	var right := forward.cross(ground_normal).normalized()
	var corrected_forward := ground_normal.cross(right).normalized()

	var basis := Basis(right, ground_normal, -corrected_forward)
	foot.debug.global_basis = basis

func _update_pelvis_debug(delta: float) -> void:
	if pelvis_debug == null:
		return

	var target := _get_pelvis_target_position()
	var weight := 1.0 - exp(-pelvis_follow_speed * delta)

	pelvis_debug.global_position = pelvis_debug.global_position.lerp(target, weight)


func _get_pelvis_target_position() -> Vector3:
	var left_pos := left_foot.debug.global_position
	var right_pos := right_foot.debug.global_position

	var midpoint := (left_pos + right_pos) * 0.5
	return midpoint + Vector3.UP * pelvis_height
