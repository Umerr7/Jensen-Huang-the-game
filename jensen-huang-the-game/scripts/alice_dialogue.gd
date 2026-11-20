# Alice's chat box: her line at the top (typed out), Jensen's input underneath,
# and the "end it" button for the no-AI revenge ending.
extends CanvasLayer

signal message_sent(text: String)
signal attack_chosen

## Characters per second for the typewriter effect.
@export var type_speed : float = 45.0

@onready var _alice_text : RichTextLabel = %AliceText
@onready var _emotion : Label = %Emotion
@onready var _line_edit : LineEdit = %Input
@onready var _send : Button = %Send
@onready var _attack : Button = %Attack
@onready var _thinking : Label = %Thinking

var _messages_left := 0
var _busy := false
var _dots := 0.0


func _ready() -> void:
	_send.pressed.connect(_submit)
	_line_edit.text_submitted.connect(func(_t): _submit())
	_attack.pressed.connect(func(): GameAudio.sfx(self, "ui_click", null, -4.0); attack_chosen.emit())
	_thinking.visible = false


func open(first_line: String, messages: int) -> void:
	visible = true
	_messages_left = messages
	_show_text(first_line, "")
	_set_input_enabled(true)


func _input(event: InputEvent) -> void:
	# Esc = stop listening and attack (Ending 4).
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		attack_chosen.emit()


func _process(delta: float) -> void:
	if _thinking.visible:
		_dots += delta * 3.0
		_thinking.text = "Alice is thinking" + ".".repeat(int(_dots) % 4)
	if _alice_text.visible_ratio < 1.0:
		var total := maxf(_alice_text.get_total_character_count(), 1.0)
		_alice_text.visible_ratio = minf(1.0, _alice_text.visible_ratio + type_speed * delta / total)


func _submit() -> void:
	var text := _line_edit.text.strip_edges()
	if _busy or text == "" or _messages_left <= 0:
		return
	GameAudio.sfx(self, "ui_click", null, -4.0)
	_line_edit.text = ""
	message_sent.emit(text)


## Called while Gemma is working on a reply.
func set_thinking(on: bool, messages_left: int) -> void:
	_busy = on
	_messages_left = messages_left
	_thinking.visible = on
	_set_input_enabled(not on)


func show_alice_line(line: String, emotion: String, messages_left: int, is_final: bool) -> void:
	_busy = false
	_thinking.visible = false
	_messages_left = messages_left
	_show_text(line, emotion)
	if is_final or messages_left <= 0:
		_set_input_enabled(false)
		_attack.disabled = true
	else:
		_set_input_enabled(true)


func _show_text(line: String, emotion: String) -> void:
	_alice_text.text = line
	_alice_text.visible_ratio = 0.0
	_emotion.text = ("(" + emotion + ")") if emotion != "" else ""


func _set_input_enabled(on: bool) -> void:
	_line_edit.editable = on
	_send.disabled = not on
	_line_edit.placeholder_text = "Say Something to Alice... (Enter to send)" if on else ""
	if on:
		_line_edit.grab_focus.call_deferred()
