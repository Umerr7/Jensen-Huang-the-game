# Jensen's player script.
# Reuses all the movement from the ProtoController (walking, jumping, sprinting,
# mouse look) and adds: "which animation should be playing right now?"
extends "res://scripts/proto_controller.gd"


## The states Jensen can be in. Each one maps to an animation below.
enum State { IDLE, RUN, SPRINT, JUMP, FALL, FIRE }

@export_group("Animations")
## Library names exactly as they appear in the AnimationPlayer's library list.
@export var anim_idle : String = "Rifle Idle"
@export var anim_run : String = "Rifle Run"
@export var anim_sprint : String = "Rifle Sprint"
@export var anim_jump : String = "Rifle Jump"
@export var anim_fire : String = "Firing Rifle"
## How long (seconds) to crossfade from one animation into the next.
@export var blend_time : float = 0.2
## Below this horizontal speed (m/s) he counts as standing still.
@export var move_threshold : float = 0.5

@onready var anim_player : AnimationPlayer = $jensen/AnimationPlayer

var state : State = State.IDLE
var _current_anim : String = ""


func _physics_process(delta: float) -> void:
	super(delta)            # run the normal ProtoController movement first
	state = _pick_state()
	_play_for_state(state)


## Look at what the body is doing this frame and decide which state that is.
func _pick_state() -> State:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := horizontal_speed > move_threshold

	if not is_on_floor():
		return State.JUMP if velocity.y > 0.0 else State.FALL
	if not moving and _wants_to_fire():
		return State.FIRE
	if moving and can_sprint and Input.is_action_pressed(input_sprint):
		return State.SPRINT
	if moving:
		return State.RUN
	return State.IDLE


func _wants_to_fire() -> bool:
	# Only counts once the mouse is captured, so the click that captures it doesn't shoot.
	return mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _play_for_state(s: State) -> void:
	match s:
		State.IDLE:   _play(anim_idle)
		State.RUN:    _play(anim_run)
		State.SPRINT: _play(anim_sprint)
		State.FIRE:   _play(anim_fire)
		State.JUMP:   _play(anim_jump)
		State.FALL:   pass   # keep whatever is playing (the jump finishes, then holds its last pose)


## Crossfade into a library's clip, but only if it isn't already playing
## (calling play() every frame would restart it from the beginning).
func _play(library_name: String) -> void:
	if library_name == _current_anim:
		return
	var clip := _clip_in(library_name)
	if clip == "":
		return
	anim_player.play(clip, blend_time)
	_current_anim = library_name


## Mixamo libraries contain one clip (named "mixamo_com"); find its full
## "Library/clip" name so we don't have to hardcode it.
func _clip_in(library_name: String) -> String:
	if not anim_player.has_animation_library(library_name):
		push_warning("No animation library called '%s' on the AnimationPlayer" % library_name)
		return ""
	var clips := anim_player.get_animation_library(library_name).get_animation_list()
	if clips.is_empty():
		return ""
	return "%s/%s" % [library_name, clips[0]]
