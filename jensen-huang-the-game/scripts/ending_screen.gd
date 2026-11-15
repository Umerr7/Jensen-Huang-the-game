# Placeholder ending screen: a title, a short epilogue, Alice's last line,
# and Play again / Quit. One scene per ending (endings/*.tscn) sets the text.
# No ending number or ending name is shown, so players can't tell how many
# endings exist or which one they got.
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
	%Quit.pressed.connect(func(): get_tree().quit())
	# fade in
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 1.2)
