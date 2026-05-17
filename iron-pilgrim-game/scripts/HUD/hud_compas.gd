extends HSlider

@export var to_track:Node3D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if to_track:
		if to_track.rotation_degrees.y > 0 and to_track.rotation_degrees.y < 180:
			value = to_track.rotation_degrees.y
