extends Node3D
class_name MechMk3

@export var cockpit_camera:Camera3D
@export var cockpit_ext_mesh:GeometryInstance3D
@export var skeleton_driver:MechSkeletonDriver
@export var scan_raycast:RayCast3D

var physic_body:CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	physic_body = get_parent()

func display_cockpit_view():
	cockpit_ext_mesh.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

func display_exterior_view():
	cockpit_ext_mesh.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_ON
