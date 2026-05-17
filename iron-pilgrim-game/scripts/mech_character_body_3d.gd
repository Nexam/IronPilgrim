extends CharacterBody3D

# Chassis: movement, gravity, and look only. Camera feel (bob, sway, inertia lean)
# is handled by the procedural digitigrade rig that drives the skeleton — the
# camera rides the torso bone via BoneAttachment3D.

@export var move_speed := 5.0
@export var mouse_sensitivity := 0.003
@export var mech: MechMk3
@export var ext_camera:Camera3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mouse_pitch := 0.0

var current_cam:Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_cam = mech.cockpit_camera
	mech.cockpit_camera.make_current()
	mech.display_cockpit_view()

func _unhandled_input(event: InputEvent) -> void:
	#if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		#rotate_y(-event.relative.x * mouse_sensitivity)
		#_mouse_pitch -= event.relative.y * mouse_sensitivity
		#_mouse_pitch = clamp(_mouse_pitch, -PI / 2, PI / 2)
		#current_cam.rotation.x = _mouse_pitch

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	if event.is_action_pressed("switch_view"):
		if ext_camera.current:
			current_cam = mech.cockpit_camera
			mech.cockpit_camera.make_current()
			mech.display_cockpit_view()
		else:
			current_cam = ext_camera
			ext_camera.make_current()
			mech.display_exterior_view()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	var input_view := Input.get_vector("view_right", "view_left", "view_up", "view_down")
	var view_dir := (transform.basis * Vector3(0, input_view.x,0)).normalized()
	rotate(view_dir, delta)
	
	mech.skeleton_driver.torso_pitch -= input_view.y

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed_mult = 1.0
	
	if Input.is_action_pressed("sprint"):
		speed_mult = 2.0
		
	if input_dir.y > 0:
		speed_mult *= 0.5
	
	velocity.x = direction.x * move_speed * speed_mult
	velocity.z = direction.z * move_speed * speed_mult

	move_and_slide()
