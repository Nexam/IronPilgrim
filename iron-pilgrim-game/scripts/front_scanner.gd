extends Node

const outline_material:Material = preload("uid://xevk2k2pdnvn")

@export var mech:MechMk3
var scan_target:Node3D
var prev_ouline:Material

func _physics_process(delta: float) -> void:
	if mech.scan_raycast.is_colliding():
		var obj = mech.scan_raycast.get_collider()
		if obj is Node3D:
			if obj != scan_target:
				if scan_target:
					_highlight_scannable(false)
				scan_target = obj as Node3D
				_highlight_scannable(true)
	else:
		if scan_target:
			_highlight_scannable(false)
		scan_target = null
		
func _highlight_scannable(highlight:bool):
	print( "hightlight (%s): %s "%[highlight, scan_target])
	for c in scan_target.get_children():
		if c is MeshInstance3D:
			var mi = c as MeshInstance3D
			var mat = mi.get_surface_override_material(0)
			if not mat:
				continue
			if highlight:
				if mat.next_pass:
					prev_ouline = mat.next_pass
				mat.next_pass = outline_material
			else:
				if not mat:
					continue
				if prev_ouline:
					mat.next_pass = prev_ouline
				else:
					mat.next_pass = null
				prev_ouline = null
			
