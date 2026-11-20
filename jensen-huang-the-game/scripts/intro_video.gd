# Plays the opening cutscene over the level the first time the game starts.
# The game is paused underneath (music, Jensen, enemies all wait), then it
# unpauses and removes itself. Dying / replaying doesn't show it again.
# Space, Enter, Esc or a click skips it.
extends CanvasLayer

@export var video : VideoStream = preload("res://video/intro.ogv")
## Music played over the intro (the video itself has no sound). Empty = silent.
@export var song : AudioStream
## Song volume in dB.
@export var song_volume_db : float = -6.0
## Seconds the song takes to fade out when the intro ends or is skipped.
@export var song_fade_out : float = 1.6
## Seconds before skipping is allowed (stops an accidental instant skip).
@export var skip_delay : float = 0.6

static var played := false

@onready var _player : VideoStreamPlayer = $Video
@onready var _hint : Label = $SkipHint
var _age := 0.0
var _ending := false
var _song_player : AudioStreamPlayer


func _ready() -> void:
	if played:
		queue_free()
		return
	played = true
	process_mode = Node.PROCESS_MODE_ALWAYS     # keep running while the game is paused
	get_tree().paused = true
	_player.stream = video
	_player.finished.connect(_finish)
	_player.play()
	if song:
		_song_player = AudioStreamPlayer.new()
		_song_player.stream = song
		_song_player.volume_db = song_volume_db
		_song_player.bus = &"Music"
		add_child(_song_player)
		_song_player.play()


func _process(delta: float) -> void:
	_age += delta
	_hint.modulate.a = clampf((_age - 2.0) * 0.8, 0.0, 0.6)    # hint fades in after 2 s


func _input(event: InputEvent) -> void:
	if _age < skip_delay or _ending:
		return
	var skip : bool = (event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]) \
		or (event is InputEventMouseButton and event.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _ending:
		return
	_ending = true
	_player.stop()
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property($Fade, "color:a", 0.0, 0.6).from(1.0)
	if _song_player:                           # fade the song out with the picture
		tw.parallel().tween_property(_song_player, "volume_db", -60.0, song_fade_out)
	_player.visible = false
	_hint.visible = false
	tw.tween_callback(queue_free)
