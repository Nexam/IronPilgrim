extends Node3D
class_name MechMk3

var physic_body:CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	physic_body = get_parent()
