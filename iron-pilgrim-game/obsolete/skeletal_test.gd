extends Skeleton3D

@export var bone_name:String = "torso"

func _ready() -> void:
	var bone_id := find_bone(bone_name)
	print("%s id: %s" %[bone_name, bone_id] )

	var pose := get_bone_pose(bone_id)
	pose.origin.y += 0.5
	set_bone_pose_position(bone_id, pose.origin)
