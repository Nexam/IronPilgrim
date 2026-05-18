@tool
extends Control

@export var corner_radius:float = 2.0
@export var corner_res:int = 8
@export var corner_lenght:float = 40.0
@export var line_color:Color = Color.YELLOW
@export var line_width:float= -1.0
@export var queue_redraw_hud:bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	queue_redraw()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if queue_redraw_hud:
		queue_redraw_hud = false
		queue_redraw()

func _draw() -> void:
	var local_rect := Rect2(Vector2.ZERO, size)
	var aa := line_width >= 1.0
	# TOP LEFT
	draw_arc( 
		Vector2(corner_radius,corner_radius), 
		corner_radius, 
		deg_to_rad(180), 
		deg_to_rad(270.0),
		corner_res,
		line_color,
		line_width,
		aa
	)
	if corner_lenght > corner_radius:
		draw_line( Vector2(corner_radius,0), Vector2(corner_lenght,0),line_color, line_width, aa)
		draw_line( Vector2(0,corner_radius), Vector2(0,corner_lenght),line_color, line_width, aa)
	
	# TOP RIGHT
	draw_arc(
		Vector2(size.x - corner_radius, corner_radius),
		corner_radius,
		deg_to_rad(270),
		deg_to_rad(360),
		corner_res,
		line_color,
		line_width,
		aa
	)

	if corner_lenght > corner_radius:
		draw_line(
			Vector2(size.x - corner_radius, 0),
			Vector2(size.x - corner_lenght, 0),
			line_color,
			line_width,
			aa
		)

		draw_line(
			Vector2(size.x, corner_radius),
			Vector2(size.x, corner_lenght),
			line_color,
			line_width,
			aa
		)

	# BOTTOM RIGHT
	draw_arc(
		Vector2(size.x - corner_radius, size.y - corner_radius),
		corner_radius,
		deg_to_rad(0),
		deg_to_rad(90),
		corner_res,
		line_color,
		line_width,
		aa
	)

	if corner_lenght > corner_radius:
		draw_line(
			Vector2(size.x - corner_radius, size.y),
			Vector2(size.x - corner_lenght, size.y),
			line_color,
			line_width,
			aa
		)

		draw_line(
			Vector2(size.x, size.y - corner_radius),
			Vector2(size.x, size.y - corner_lenght),
			line_color,
			line_width,
			aa
		)

	# BOTTOM LEFT
	draw_arc(
		Vector2(corner_radius, size.y - corner_radius),
		corner_radius,
		deg_to_rad(90),
		deg_to_rad(180),
		corner_res,
		line_color,
		line_width,
		aa
	)

	if corner_lenght > corner_radius:
		draw_line(
			Vector2(corner_radius, size.y),
			Vector2(corner_lenght, size.y),
			line_color,
			line_width,
			aa
		)

		draw_line(
			Vector2(0, size.y - corner_radius),
			Vector2(0, size.y - corner_lenght),
			line_color,
			line_width,
			aa
		)
