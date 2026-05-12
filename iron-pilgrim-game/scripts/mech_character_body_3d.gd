extends CharacterBody3D

# Chassis: movement, gravity, and look only. Camera feel (bob, sway, inertia lean)
# is handled by the procedural digitigrade rig that drives the skeleton — the
# camera rides the torso bone via BoneAttachment3D.

@export var move_speed := 5.0
@export var mouse_sensitivity := 0.003
@export var mech_config:MechConfig
var camera: Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mouse_pitch := 0.0

func _ready() -> void:
	camera = mech_config.camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_mouse_pitch -= event.relative.y * mouse_sensitivity
		_mouse_pitch = clamp(_mouse_pitch, -PI / 2, PI / 2)
		camera.rotation.x = _mouse_pitch

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
