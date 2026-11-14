# Jensen's player script.
# Reuses all the movement from the ProtoController (walking, jumping, sprinting,
# mouse look) and adds: "which animation should be playing right now?"
extends "res://scripts/proto_controller.gd"


signal weapon_picked_up
signal health_changed(current: float, maximum: float)
signal died

## The states Jensen can be in. Each one maps to an animation below.
## IDLE_UNARMED and WALK are used before he has the blaster; everything else needs it.
enum State { IDLE_UNARMED, WALK, IDLE, RUN, SPRINT, STRAFE_LEFT, STRAFE_RIGHT, RUN_BACK, JUMP, FALL, FIRE }

## Does Jensen start the game holding the blaster? Off = he has to find it first.
@export var has_weapon : bool = false
## Walking speed (m/s) while unarmed. Armed he uses base_speed / sprint_speed.
@export var walk_speed : float = 2.0

@export_group("Health")
@export var max_health : float = 100.0

@export_group("EMP Gun")
## Damage per shot (transistors have 100 health, so 34 = 3 shots).
@export var shot_damage : float = 34.0
## Seconds between shots while the mouse is held.
@export var fire_cooldown : float = 0.25
## How far the shot reaches (m).
@export var shot_range : float = 80.0

@export_group("Animations")
## Library names exactly as they appear in the AnimationPlayer's library list.
## Unarmed:
@export var anim_idle_unarmed : String = "Idle"
@export var anim_walk : String = "Walking"
## Armed:
@export var anim_idle : String = "Rifle Idle"
@export var anim_run : String = "Rifle Run"
@export var anim_sprint : String = "Rifle Sprint"
@export var anim_strafe_left : String = "Rifle Strafe Left"
@export var anim_strafe_right : String = "Rifle Strafe Right"
@export var anim_run_back : String = "Rifle Run Backwards"
@export var anim_jump : String = "Rifle Jump"
@export var anim_fire : String = "Firing Rifle"
## How long (seconds) to crossfade from one animation into the next.
@export var blend_time : float = 0.2
## Below this horizontal speed (m/s) he counts as standing still.
@export var move_threshold : float = 0.5

@onready var anim_player : AnimationPlayer = $jensen/AnimationPlayer
@onready var held_weapon : Node3D = get_node_or_null("jensen/AvatarRoot/GeneralSkeleton/BoneAttachment3D/Blaster")
@onready var left_arm_ik : SkeletonModifier3D = get_node_or_null("jensen/AvatarRoot/GeneralSkeleton/LeftArmIK")

var state : State = State.IDLE_UNARMED
var _current_anim : String = ""
var _run_speed : float          # base_speed as set in the Inspector (armed running speed)
var _sprint_allowed : bool      # can_sprint as set in the Inspector
var health : float
var _fire_cooldown_left : float = 0.0
var _dead : bool = false
@onready var camera : Camera3D = $Head/Camera3D


func _ready() -> void:
	super()
	add_to_group("player")      # enemies look for this group to find their target
	collision_mask |= 2         # bump into enemies (they live on physics layer 2)
	health = max_health
	_run_speed = base_speed
	_sprint_allowed = can_sprint
	_apply_weapon_state()
	can_jump = false

## Call this when Jensen grabs the blaster (the WeaponPickup does this for you).
func pick_up_weapon() -> void:
	if has_weapon:
		return
	has_weapon = true
	can_jump = true	
	_apply_weapon_state()
	weapon_picked_up.emit()


## Show/hide the blaster in his hand, switch the left-hand IK and movement speeds.
func _apply_weapon_state() -> void:
	if held_weapon:
		held_weapon.visible = has_weapon
	if left_arm_ik:
		left_arm_ik.active = has_weapon
	base_speed = _run_speed if has_weapon else walk_speed
	can_sprint = _sprint_allowed and has_weapon
	_current_anim = ""   # force the right animation to start on the next frame


func _physics_process(delta: float) -> void:
	super(delta)            # run the normal ProtoController movement first
	state = _pick_state()
	_play_for_state(state)
	_fire_cooldown_left = maxf(_fire_cooldown_left - delta, 0.0)
	if _wants_to_fire() and _fire_cooldown_left <= 0.0:
		shoot()


## Enemy bolts call this when they hit Jensen.
func take_damage(amount: float) -> void:
	if _dead:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_dead = true
		died.emit()
		get_tree().reload_current_scene.call_deferred()   # simple jam death: restart the level


## Fire the EMP: an instant ray from the middle of the screen. Anything it hits
## that has take_damage() (the transistors) gets hurt.
func shoot() -> void:
	_fire_cooldown_left = fire_cooldown
	var from := camera.global_position
	var to := from + -camera.global_basis.z * shot_range
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)   # world + enemies
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(shot_damage)


## Look at what the body is doing this frame and decide which state that is.
func _pick_state() -> State:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := horizontal_speed > move_threshold

	# Unarmed: only idle and walk.
	if not has_weapon:
		if not is_on_floor():
			return State.FALL      # keep the current pose while in the air
		return State.WALK if moving else State.IDLE_UNARMED

	if not is_on_floor():
		return State.JUMP if velocity.y > 0.0 else State.FALL
	if not moving and _wants_to_fire():
		return State.FIRE
	if not moving:
		return State.IDLE

	# Turn world-space velocity into "relative to where Jensen is facing":
	#   local.x > 0 = moving right,  local.x < 0 = left
	#   local.z < 0 = moving forward, local.z > 0 = backward
	var local := global_basis.inverse() * velocity
	if absf(local.x) > absf(local.z):          # mostly sideways
		return State.STRAFE_RIGHT if local.x > 0.0 else State.STRAFE_LEFT
	if local.z > 0.0:                          # mostly backwards
		return State.RUN_BACK
	if can_sprint and Input.is_action_pressed(input_sprint):
		return State.SPRINT                    # sprint only when going forward
	return State.RUN


func _wants_to_fire() -> bool:
	# Only counts once the mouse is captured, so the click that captures it doesn't shoot.
	return has_weapon and mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _play_for_state(s: State) -> void:
	match s:
		State.IDLE_UNARMED: _play(anim_idle_unarmed)
		State.WALK:   _play(anim_walk)
		State.IDLE:   _play(anim_idle)
		State.RUN:    _play(anim_run)
		State.SPRINT: _play(anim_sprint)
		State.STRAFE_LEFT:  _play(anim_strafe_left)
		State.STRAFE_RIGHT: _play(anim_strafe_right)
		State.RUN_BACK:     _play(anim_run_back)
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
