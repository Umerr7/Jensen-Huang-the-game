# All the game's sound in one place. No autoload needed - call it from anywhere:
#
#   GameAudio.sfx(self, "laser_shot")                      # flat 2D sound (UI, player)
#   GameAudio.sfx(self, "laser_hit", hit_position)         # 3D sound at a point in the world
#   GameAudio.loop_on(self, "enemy_hum")                   # looping 3D sound that follows a node
#   GameAudio.music(self, "gameplay")                      # crossfades to a music track
#
# Music and ambience players live on the scene tree root, so they keep playing
# across scene changes (main -> ending screen). Volumes: Audio bus panel at the
# bottom of the editor has "Music" and "SFX" buses (default_bus_layout.tres).
class_name GameAudio
extends RefCounted

const SOUNDS := {
	# player
	"footstep_1": preload("res://audio/Player/Footsteps/footstep_01.wav"),
	"footstep_2": preload("res://audio/Player/Footsteps/footstep_02.wav"),
	"footstep_3": preload("res://audio/Player/Footsteps/footstep_03.wav"),
	"jump": preload("res://audio/Player/jump.wav"),
	"land": preload("res://audio/Player/land.wav"),
	"hurt": preload("res://audio/Player/hurt.wav"),
	"death": preload("res://audio/Player/death.wav"),
	# weapons
	"laser_shot": preload("res://audio/Weapons/laser_shot.wav"),
	"laser_hit": preload("res://audio/Weapons/laser_hit.wav"),
	"pickup": preload("res://audio/Weapons/powerup_pickup.wav"),
	# enemies
	"enemy_pop": preload("res://audio/Enemies/enemy_destroyed_pop.wav"),
	"enemy_hum": preload("res://audio/Enemies/enemy_hum_loop.ogg"),
	# story / scene
	"wake_gasp": preload("res://audio/Scene/wake_gasp.wav"),
	"reveal_sting": preload("res://audio/Scene/reveal_sting.wav"),
	"door_open": preload("res://audio/Scene/door_open.wav"),
	# ui
	"ui_click": preload("res://audio/UI/ui_click.wav"),
}

const MUSIC := {
	"gameplay": "res://audio/Music/music_loop.ogg",
	"alice": "res://audio/Music/The Lily of steel.ogg",   # the confrontation + endings
	"board_hum": "res://audio/Ambience/board_hum_loop.ogg",
}

static var _music_player : AudioStreamPlayer
static var _music_key := ""
static var _ambience_player : AudioStreamPlayer
static var _music_cache := {}        # key -> loaded AudioStream (kept, so switching back is instant)
static var _music_requested := {}    # key -> true while loading in the background


## One-shot sound. `at` = world position for a 3D sound, or null for a flat one.
## `pitch_jitter` randomises pitch a bit so repeated sounds don't feel robotic.
static func sfx(from: Node, key: String, at = null, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if from == null or not from.is_inside_tree() or not SOUNDS.has(key):
		return
	var p : Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 8.0
		p3.max_distance = 70.0
		p3.volume_db = volume_db
		p3.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
		p3.stream = SOUNDS[key]
		p3.bus = &"SFX"
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.volume_db = volume_db
		p2.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
		p2.stream = SOUNDS[key]
		p2.bus = &"SFX"
		p = p2
	# Parent to the current scene (not the caller) so the sound survives the caller dying.
	var parent : Node = from.get_tree().current_scene if from.get_tree().current_scene else from.get_tree().root
	p.finished.connect(p.queue_free)
	if parent.is_node_ready():
		parent.add_child(p)
		_start(p, at)
	else:
		# The scene is still loading (e.g. a sound from a _ready()): add it once it's done.
		p.ready.connect(_start.bind(p, at), CONNECT_ONE_SHOT)
		parent.add_child.call_deferred(p)


static func _start(p: Node, at) -> void:
	if at is Vector3:
		(p as Node3D).global_position = at
	p.play()


## Looping 3D sound attached to a node (it moves and dies with the node).
static func loop_on(node: Node3D, key: String, volume_db := -10.0, unit_size := 5.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = SOUNDS.get(key)
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 35.0
	p.bus = &"SFX"
	node.add_child(p)
	p.play(randf() * 1.0)     # random start so several enemies don't hum in sync
	return p


## Crossfade to a music track ("gameplay" or "alice"). Same track = keep playing.
static func music(from: Node, key: String, fade := 1.5, volume_db := 0.0) -> void:
	if key == _music_key and is_instance_valid(_music_player) and _music_player.playing:
		return
	_music_key = key
	var tree := from.get_tree()
	var old := _music_player
	var p := AudioStreamPlayer.new()
	p.stream = _music_stream(key)
	p.bus = &"Music"
	p.volume_db = -40.0
	tree.root.add_child.call_deferred(p)
	_music_player = p
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(p):
		return
	p.play()
	tree.create_tween().tween_property(p, "volume_db", volume_db, fade)
	if is_instance_valid(old):
		var tw := tree.create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.queue_free)


## Starts loading a track in the background, so a later music(key) doesn't
## freeze the game while it loads (in a browser that freeze was very visible
## when Alice's chat opened). Call it early, e.g. when the level starts.
static func prefetch_music(key: String) -> void:
	if _music_cache.has(key) or _music_requested.has(key):
		return
	if ResourceLoader.load_threaded_request(MUSIC[key]) == OK:
		_music_requested[key] = true


static func _music_stream(key: String) -> AudioStream:
	if not _music_cache.has(key):
		if _music_requested.has(key):
			_music_requested.erase(key)
			_music_cache[key] = ResourceLoader.load_threaded_get(MUSIC[key])   # waits only if not finished yet
		else:
			_music_cache[key] = load(MUSIC[key])
	return _music_cache[key]


static func stop_music(from: Node, fade := 1.0) -> void:
	_music_key = ""
	if is_instance_valid(_music_player):
		var old := _music_player
		var tw := from.get_tree().create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.queue_free)
	_music_player = null


## Constant background hum of the circuit board (quiet, under the music).
static func ambience(from: Node, on := true, volume_db := -14.0) -> void:
	if on and not is_instance_valid(_ambience_player):
		_ambience_player = AudioStreamPlayer.new()
		_ambience_player.stream = load(MUSIC["board_hum"])
		_ambience_player.bus = &"SFX"
		_ambience_player.volume_db = volume_db
		from.get_tree().root.add_child.call_deferred(_ambience_player)
		_ambience_player.ready.connect(_ambience_player.play)
	elif not on and is_instance_valid(_ambience_player):
		_ambience_player.queue_free()
		_ambience_player = null
