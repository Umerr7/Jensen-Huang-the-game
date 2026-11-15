# Flashing objective text at the top of the screen. Shows every time the level
# loads (game start and after every death, since dying reloads the level).
# It waits for the intro video automatically because the game is paused then.
extends CanvasLayer

@export var text : String = "REACH THE SERVER ROOM TO DESTROY THE CHINESE MODEL"
## Delay after the level starts before it appears.
@export var start_delay : float = 0.8
## How many times it blinks.
@export var flashes : int = 4
## How long it stays fully visible after flashing.
@export var hold_time : float = 2.5

@onready var _panel : Control = $Banner
@onready var _label : Label = $Banner/Label


func _ready() -> void:
	_label.text = text
	_panel.modulate.a = 0.0
	show_objective()


## Can also be called again from anywhere (e.g. a new objective).
func show_objective(new_text: String = "") -> void:
	if new_text != "":
		_label.text = new_text
	var tw := create_tween()
	tw.tween_interval(start_delay)
	for i in flashes:
		tw.tween_property(_panel, "modulate:a", 1.0, 0.12)
		tw.tween_interval(0.28)
		tw.tween_property(_panel, "modulate:a", 0.15, 0.12)
		tw.tween_interval(0.12)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.12)
	tw.tween_interval(hold_time)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.8)
