extends Node3D
class_name MechWiring

@export var chassis: CharacterBody3D
@export var rig: MechDigitigradeRig
@export var camera: Camera3D

func _ready() -> void:
	if rig and chassis:
		rig.chassis = chassis
