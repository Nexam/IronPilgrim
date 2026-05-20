extends Node

const outline_material: Material = preload("uid://xevk2k2pdnvn")
const SCAN_OVERLAY:Material = preload("uid://c5rld2qkdoes4")

@export var mech: MechMk3

var scan_target: Node3D
var highlighted_meshes: Array[MeshInstance3D] = []


func _physics_process(_delta: float) -> void:
	var new_target: Node3D = null

	if mech.scan_raycast.is_colliding():
		var obj := mech.scan_raycast.get_collider()
		if obj is Node3D and obj.is_in_group("scannable"):
			new_target = obj as Node3D

	if new_target != scan_target:
		_clear_highlight()
		scan_target = new_target

		if scan_target:
			_apply_highlight(scan_target)


func _apply_highlight(root: Node3D) -> void:
	print(root)
	highlighted_meshes.clear()

	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.material_override = SCAN_OVERLAY
		highlighted_meshes.append(mi)


func _clear_highlight() -> void:
	for mi in highlighted_meshes:
		if is_instance_valid(mi):
			mi.material_override = null

	highlighted_meshes.clear()
