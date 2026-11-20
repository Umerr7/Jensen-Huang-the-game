# Placeholder ending screen: a title, a short epilogue, Alice's last line,
# and a Play again button. One scene per ending (endings/*.tscn) sets the text.
# From the second playthrough on, the bottom-right corner counts how many
# different endings the player has reached (no total, so they can't tell how
# many there are).
extends Control

@export var title : String = "The Unexpected Comeback"
@export_multiline var epilogue : String = ""
@export var accent : Color = Color(0.46, 0.73, 0.0)
@export_file("*.tscn") var replay_scene : String = "res://main.tscn"


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	%Title.text = title
	%Epilogue.text = epilogue
	%Title.add_theme_color_override("font_color", accent)
	var line := GameEnding.final_line
	%Quote.visible = line != ""
	%Quote.text = "\u201c%s\u201d  \u2014 Alice" % line
	%Replay.pressed.connect(func():
		GameAudio.sfx(self, "ui_click", null, -4.0)
		get_tree().change_scene_to_file.call_deferred(replay_scene))
	_add_endings_counter()
	# fade in
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 1.2)


func _add_endings_counter() -> void:
	if GameEnding.playthroughs() < 2:
		return                     # first playthrough: keep the mystery
	var label := Label.new()
	label.name = "EndingsReached"
	label.text = "Endings reached: %d" % GameEnding.reached_count()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.6, 0.66, 0.64))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
