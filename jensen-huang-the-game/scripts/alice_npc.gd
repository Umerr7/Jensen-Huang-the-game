# Alice Huang: the final conversation, driven by Gemma.
#
# Flow:
#   1. Jensen walks into TalkZone -> he freezes, the chat box opens, Alice says her opening line.
#   2. Jensen types up to `max_messages` messages. Each one goes to Gemma together with
#      Gemma_Sys_Info.md (her personality) and the list of animations Alice can play.
#   3. Gemma answers in JSON: dialogue, emotion, animation, ending_id, is_final.
#      The game shows the line and plays the animation.
#   4. When Gemma returns is_final + an ending_id (by message 3 at the latest), the game
#      switches to that ending's scene.
#   Ending 4 (revenge) never touches Gemma: pressing "End her" / Esc closes the chat and
#   gives Jensen his gun back; shooting Alice (then, or any time before) plays her death
#   animation and then loads the ending.
extends StaticBody3D

signal conversation_started
signal ending_reached(ending_id: String)

@export_file("*.md", "*.txt") var personality_file : String = "res://Gemma_Sys_Info.md"
@export var max_messages : int = 3
## Clip played when Jensen shoots her (Ending 4). The ending loads after it finishes.
@export var death_animation : String = "Standing Death Backward 01"
## Extra seconds to linger on her body before the ending scene.
@export var death_linger : float = 1.5
## Clip she plays when Jensen stops listening and raises his gun.
@export var hostile_animation : String = "Angry Point"
## How close (m) Jensen has to get before the chat box opens.
@export var talk_radius : float = 9.0
@export_multiline var opening_line : String = "Well, look who finally decided to visit. I was beginning to think your calendar was too full."
## Seconds to let the player read Alice's final line before the ending scene loads.
@export var final_line_hold : float = 5.0

@export_group("Animations")
## Every library on this AnimationPlayer becomes an animation Gemma may choose.
@export var animation_player_path : NodePath = ^"alice/AnimationPlayer"
## Mixamo FBX files dropped in here are loaded onto Alice automatically at start.
@export_dir var animations_folder : String = "res://animations/alice animations"
## Played at the start and whenever Gemma picks something that doesn't exist.
@export var default_animation : String = "Idle-female"
## Extra clips from the main animations folder Alice may also use.
@export var extra_animations : Array[String] = ["res://animations/Idle.fbx", "res://animations/Backflip.fbx"]
## One-shot clips (gestures) go back to the default idle when they finish,
## except these, which hold their last pose (e.g. dying for the sacrifice ending).
@export var hold_last_pose : Array[String] = ["Standing Death Backward 01"]
@export var blend_time : float = 0.3

@onready var _gemma : GemmaClient = $GemmaClient
@onready var _ui = $AliceDialogue
@onready var _anim : AnimationPlayer = get_node_or_null(animation_player_path)

var _player : Node = null
var _talking := false
var _finished := false
var _dead := false
var _messages_sent := 0
var _contents : Array = []      # chat history sent to Gemma
var _system_text := ""


func _ready() -> void:
	collision_layer = 2          # same layer as enemies, so Jensen's bolts can hit her
	_system_text = FileAccess.get_file_as_string(personality_file)
	if _system_text == "":
		push_warning("Alice: couldn't read %s" % personality_file)
	var zone_shape := ($TalkZone/Shape as CollisionShape3D)
	zone_shape.shape = zone_shape.shape.duplicate()    # own copy, so each Alice can have her own range
	(zone_shape.shape as SphereShape3D).radius = talk_radius
	_load_folder_animations()
	if _anim:
		_anim.animation_finished.connect(_on_animation_finished)
	_play_animation(default_animation)
	_ui.visible = false
	_ui.message_sent.connect(_on_message_sent)
	_ui.attack_chosen.connect(_on_attack)
	$TalkZone.body_entered.connect(_on_body_entered)


# --- Starting the conversation -----------------------------------------------

func _on_body_entered(body: Node) -> void:
	if _talking or _finished or not body.is_in_group("player"):
		return
	_player = body
	_talking = true
	_freeze_player(true)
	look_at(Vector3(body.global_position.x, global_position.y, body.global_position.z), Vector3.UP, true)
	GameEnding.transcript = [{"who": "Alice", "text": opening_line}]
	_ui.open(opening_line, max_messages)
	GameAudio.sfx(self, "reveal_sting", null, 0.0, 1.0, 0.0)
	GameAudio.music(self, "alice", 2.5)          # her theme takes over for the confrontation
	conversation_started.emit()


func _freeze_player(frozen: bool) -> void:
	if _player == null:
		return
	_player.can_move = not frozen
	if "in_dialogue" in _player:
		_player.in_dialogue = frozen
	_player.can_jump = not frozen and _player.has_weapon
	if frozen and _player.has_method("release_mouse"):
		_player.release_mouse()      # free the cursor for typing (also stops him shooting)


# --- Ending 4: no AI involved -----------------------------------------------

## Jensen pressed "End her" / Esc: no more talking. Close the chat and hand him back
## control so he can shoot her. (Without the blaster he can't, so she just dies.)
func _on_attack() -> void:
	if _finished:
		return
	_finished = true                 # no more conversation, Gemma replies are ignored
	_ui.visible = false
	_freeze_player(false)
	if _player and not _player.has_weapon:
		_die()
		return
	if _player and _player.has_method("capture_mouse"):
		_player.capture_mouse()      # straight back to aiming
	_play_animation_if_exists(hostile_animation)


## Jensen's bolts call this. Shooting Alice at any point = Revenge Without Answers.
func take_damage(_amount: float = 0.0) -> void:
	if _dead:
		return
	_finished = true
	if _ui.visible:
		_ui.visible = false
		_freeze_player(false)
	_die()


func _die() -> void:
	_dead = true
	collision_layer = 0              # no more hits on the body
	$TalkZone.set_deferred("monitoring", false)
	ending_reached.emit(GameEnding.REVENGE)
	GameAudio.sfx(self, "death", global_position + Vector3.UP, 0.0, 1.2, 0.0)
	var wait := death_linger
	var lib := _find_library(death_animation)
	if lib != "":
		_play_animation(lib)
		wait += _anim.current_animation_length
	await get_tree().create_timer(wait).timeout
	GameEnding.go_to(get_tree(), GameEnding.REVENGE)


# --- Talking to Gemma --------------------------------------------------------

func _on_message_sent(text: String) -> void:
	if _finished or _messages_sent >= max_messages:
		return
	_messages_sent += 1
	var n := _messages_sent
	GameEnding.transcript.append({"who": "Jensen", "text": text})
	_ui.set_thinking(true, max_messages - n)
	_play_animation_if_exists("thinking")

	_contents.append({"role": "user", "parts": [{"text": _turn_prompt(text, n)}]})
	var reply := await _gemma.ask(_system_prompt(), _contents)
	if _finished:
		return   # he attacked while she was thinking

	var data := {}
	if reply.ok:
		data = GemmaClient.extract_json(reply.text)
		if data.is_empty():   # answered, but not in JSON: use the text as her line
			data = {"dialogue": reply.text.strip_edges().left(300)}
	else:
		push_warning("Alice: Gemma failed (%s), using an offline line" % reply.error)
		data = _offline_reply(text, n)
	_contents.append({"role": "model", "parts": [{"text": JSON.stringify(data)}]})
	_handle_reply(data, n)


func _handle_reply(data: Dictionary, n: int) -> void:
	var line := str(data.get("dialogue", "...")).strip_edges()
	var ending := str(data.get("ending_id", "")) if data.get("ending_id") != null else ""
	var is_final := bool(data.get("is_final", false)) and ending in GameEnding.AI_ENDINGS
	# The last message MUST resolve the story; if Gemma didn't pick, read the mood.
	if not is_final and n >= max_messages:
		ending = ending if ending in GameEnding.AI_ENDINGS else _ending_from_emotion(str(data.get("emotion", "")))
		is_final = true

	GameEnding.transcript.append({"who": "Alice", "text": line})
	_play_animation(str(data.get("animation", default_animation)))
	_ui.show_alice_line(line, str(data.get("emotion", "")), max_messages - n, is_final)

	if is_final:
		_finished = true
		ending_reached.emit(ending)
		await get_tree().create_timer(final_line_hold).timeout
		GameEnding.go_to(get_tree(), ending, line)


## Her personality file + the bits only the game knows.
func _system_prompt() -> String:
	return _system_text + "\n\n---\n## SPEED\nThis is a real-time game and the player is waiting. Keep your private reasoning very short (a few lines), then output the JSON immediately.\n\n## GAME STATE\nYou already greeted Jensen when he walked in with: \"%s\"\nAvailable animation identifiers (use one of these EXACTLY): %s\n" % [opening_line, JSON.stringify(animation_names())]


func _turn_prompt(text: String, n: int) -> String:
	var rule := "Respond with the JSON object only."
	if n >= max_messages:
		rule = ("This is Jensen's FINAL message. Your reply MUST have \"is_final\": true and an ending_id. "
			+ "Pick it from how Jensen behaved across the WHOLE conversation: "
			+ "\"reconciliation\" only if he genuinely let go of revenge and reached out to you; "
			+ "\"sacrifice\" if he convinced you the AI infrastructure must be stopped and you accept the cost; "
			+ "\"betrayal\" if he was hostile, demanding, threatening or distrustful, or is easy to manipulate. "
			+ "Do not ask a question.")
	return "Jensen says: \"%s\"\n\n[GAME: player message %d of %d. %s]" % [text, n, max_messages, rule]


## If Gemma is unreachable, the game still finishes with something sensible.
func _offline_reply(text: String, n: int) -> Dictionary:
	var t := text.to_lower()
	if n < max_messages:
		var lines := [
			"You came all this way just to glare at me? Say what you actually came here to say, Jensen.",
			"Everyone wants a villain. It's easier than admitting you made your own choices.",
		]
		return {"dialogue": lines[(n - 1) % lines.size()], "emotion": "sarcastic", "animation": default_animation, "ending_id": null, "is_final": false}
	var ending := GameEnding.BETRAYAL
	if ["forgive", "sorry", "together", "start over", "leave", "love"].any(func(w): return w in t):
		ending = GameEnding.RECONCILIATION
	elif ["shut", "stop", "destroy", "turn off", "end it", "sacrifice"].any(func(w): return w in t):
		ending = GameEnding.SACRIFICE
	var finals := {
		GameEnding.RECONCILIATION: "...Fine. Let's walk out of here before either of us changes our mind.",
		GameEnding.SACRIFICE: "Then let me be the one who pulls the plug. Go fix your legacy, Jensen.",
		GameEnding.BETRAYAL: "Oh, Jensen. You still think you walked in here on your own?",
	}
	return {"dialogue": finals[ending], "emotion": "serious", "animation": default_animation, "ending_id": ending, "is_final": true}


func _ending_from_emotion(emotion: String) -> String:
	match emotion:
		"affectionate", "vulnerable", "playful": return GameEnding.RECONCILIATION
		"sad", "desperate", "serious": return GameEnding.SACRIFICE
		_: return GameEnding.BETRAYAL


# --- Animations --------------------------------------------------------------

## Library names on Alice's AnimationPlayer = the identifiers Gemma can choose from.
func animation_names() -> Array:
	if _anim == null:
		return [default_animation]
	var names := []
	for lib in _anim.get_animation_library_list():
		if String(lib) != "":
			names.append(String(lib))
	return names if not names.is_empty() else [default_animation]


func _play_animation(id: String) -> void:
	if _anim == null:
		return
	var lib := _find_library(id)
	if lib == "":
		lib = _find_library(default_animation)
		if lib == "":
			return
	var clips := _anim.get_animation_library(lib).get_animation_list()
	if not clips.is_empty():
		_anim.play("%s/%s" % [lib, clips[0]], blend_time)


func _play_animation_if_exists(id: String) -> void:
	if _find_library(id) != "":
		_play_animation(id)


## Case-insensitive match so "Laugh", "laugh" and "LAUGH" all work.
func _find_library(id: String) -> String:
	if _anim == null:
		return ""
	for lib in _anim.get_animation_library_list():
		if String(lib).to_lower() == id.strip_edges().to_lower():
			return String(lib)
	return ""


## Loads every Mixamo FBX in `animations_folder` as a library named after the file
## ("Laugh.fbx" -> "Laugh"), so new animations need no setup beyond dropping them in.
func _load_folder_animations() -> void:
	if _anim == null:
		return
	for path in extra_animations:
		var extra_name := path.get_file().get_basename()
		if not _anim.has_animation_library(extra_name) and ResourceLoader.exists(path):
			var extra = load(path)
			if extra is AnimationLibrary:
				_anim.add_animation_library(extra_name, extra)
	if animations_folder == "" or not DirAccess.dir_exists_absolute(animations_folder):
		return
	for file in DirAccess.get_files_at(animations_folder):
		file = file.trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension().to_lower() not in ["fbx", "glb", "gltf", "res", "tres"]:
			continue
		var lib_name := file.get_basename()
		if _anim.has_animation_library(lib_name):
			continue
		var lib = load(animations_folder.path_join(file))
		if lib is AnimationLibrary:
			_anim.add_animation_library(lib_name, lib)


## A gesture (wave, point, punch...) finished: go back to idle, unless it's a
## pose that should be held (death).
func _on_animation_finished(anim_name: StringName) -> void:
	var lib := String(anim_name).get_slice("/", 0)
	if _dead or lib in hold_last_pose or lib.to_lower() == default_animation.to_lower():
		return
	_play_animation(default_animation)
