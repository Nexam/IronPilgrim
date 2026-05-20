@tool
class_name TerminalPanel
extends Control

@export var LINE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
@export var BACKGROUND_COLOR := Color(0.06, 0.029, 0.025, 0.604)

@export var title := "SYS.MON"
@export var draw_title := true
@export var line_width := 1.0
@export var line_dash := 12.0

@export var draw_fill := true

@export var redraw:bool = false

func _ready() -> void:
	queue_redraw()
	
func _process(delta: float) -> void:
	if redraw:
		queue_redraw()
		redraw = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)

	if draw_fill:
		draw_rect(rect, BACKGROUND_COLOR, true)

	_draw_frame(rect)
	_draw_header(rect)

func _draw_frame(rect: Rect2) -> void:
	var aa := line_width >= 1.0
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y

	##Left
	draw_dashed_line( Vector2(x0,y0), Vector2(x0,y1), LINE_COLOR,line_width, line_dash,true, aa)
	##Right
	draw_dashed_line( Vector2(x1,y0), Vector2(x1,y1), LINE_COLOR,line_width, line_dash,true, aa)
	##Bottom
	draw_line( Vector2(x0,y1), Vector2(x1,y1), LINE_COLOR,line_width, aa)


func _draw_header(rect: Rect2) -> void:
	var aa := line_width >= 1.0
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	
	var title_offset = 16.0
	var title_padding = 4.0
	
	if draw_title:
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()*0.8
		var text := str("%s" % title)
		var text_size := font.get_string_size( text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size )

		draw_rect(Rect2( title_offset-title_padding,y0- text_size.y/4.0-title_padding ,text_size.x+title_padding*3.0, text_size.y/2.0),BACKGROUND_COLOR,true)
		draw_line(Vector2(x0,y0), Vector2(x0+title_offset - title_padding,y0), LINE_COLOR, line_width, aa)
		draw_string( font, Vector2(x0+title_offset+title_padding, y0+text_size.y/4.0), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, LINE_COLOR )
		draw_line(
			Vector2(x0+title_offset+title_padding+text_size.x+title_padding,y0), 
			Vector2(x1 ,y0), 
			LINE_COLOR, line_width, aa)	
			
	else:
		draw_line(Vector2(x0,y0), Vector2(x1,y0), LINE_COLOR, line_width, aa)
