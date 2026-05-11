extends CharacterBody3D

@export var move_speed := 5.0
@export var mouse_sensitivity := 0.003
@export var bob_frequency := 1.8
@export var bob_amplitude_y := 0.05
@export var bob_amplitude_x := 0.03
@export var bob_sharpness := 1.0
@export var inertia_lean_amount := 0.03   # scale: vertical units/s → radians
@export var inertia_lean_speed := 4.0     # how fast the lean settles

@onready var camera := $Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _bob_phase := 0.0
var _camera_rest_y: float
var _mouse_pitch := 0.0
var _lean_pitch := 0.0
var _prev_y := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_rest_y = camera.position.y
	_prev_y = global_position.y

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_mouse_pitch -= event.relative.y * mouse_sensitivity
		_mouse_pitch = clamp(_mouse_pitch, -PI / 2, PI / 2)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	move_and_slide()

	var vertical_speed := (global_position.y - _prev_y) / delta
	_prev_y = global_position.y

	_update_stride(delta)
	_apply_inertia_lean(vertical_speed, delta)

func _shape(x: float) -> float:
	return sign(x) * pow(abs(x), bob_sharpness)

func _update_stride(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := horizontal_speed / move_speed

	if horizontal_speed > 0.1:
		_bob_phase += delta * bob_frequency * TAU

	var target_y := _camera_rest_y + _shape(sin(_bob_phase)) * bob_amplitude_y * speed_ratio
	var target_x := sin(_bob_phase * 0.5) * bob_amplitude_x * speed_ratio

	camera.position.y = lerp(camera.position.y, target_y, delta * 10.0)
	camera.position.x = lerp(camera.position.x, target_x, delta * 10.0)

func _apply_inertia_lean(vertical_speed: float, delta: float) -> void:
	# going up = lean forward (negative pitch), going down = lean back (positive pitch)
	var target_lean := clampf(-vertical_speed * inertia_lean_amount, -0.12, 0.12)
	_lean_pitch = lerp(_lean_pitch, target_lean, delta * inertia_lean_speed)
	camera.rotation.x = _mouse_pitch + _lean_pitch
	camera.rotation.z = 0.0
