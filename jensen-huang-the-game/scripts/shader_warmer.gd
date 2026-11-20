# Stops the "first fireball freezes the game" hitch, mainly in browsers.
#
# A shader is compiled the first time something using it is drawn. In WebGL that
# can freeze the game for a fraction of a second, and while the game is frozen
# the music stutters too. So while the intro video covers the screen, this node
# briefly shows one of everything in front of the camera: every shot effect
# (fully lit: cast, bolt, trail, explosion), one copy of each enemy type's model,
# and Alice. That compiles their shaders before gameplay starts. Then it removes
# everything again. You never see it, because the video is drawn on top.
#
# Without the intro (it only plays once), it does nothing.
extends Node

## Effect scenes to warm up (the Pixel Dreamer VFX the shots use). Only list
## effects some shot really uses: unused ones are left out of the export.
@export var effects : Array[PackedScene] = [
	preload("res://addons/pd_projectile_vfx/effects/Magic_Bullet_Cyan.tscn"),
	preload("res://addons/pd_projectile_vfx/effects/Fireball_Orange.tscn"),
]
## Groups whose members' "Visual" node gets copied once per enemy type.
@export var model_groups : Array[StringName] = [&"enemies"]
## Other models to copy (e.g. Alice, far away at the start).
@export var extra_models : Array[NodePath] = [^"../Alice/alice"]
## How many drawn frames the copies stay on screen. Shaders compile on the
## first one; the rest let particles emit and explosions reach their later stages.
@export var warm_frames : int = 20

var _holder : Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # the game is paused during the intro
	var intro := get_node_or_null("../IntroVideo")
	if intro == null or intro.is_queued_for_deletion():
		queue_free()                           # no intro = nothing to hide this behind
		return
	_intro = intro
	# Wait until the level (and MapBatcher's merging) has settled.
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		queue_free()
		return
	_holder = Node3D.new()
	_holder.name = "ShaderWarmup"
	_holder.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.add_child(_holder)
	_holder.position = Vector3(0, 0, -3)       # just in front of the camera

	var x := -1.5
	for scene in effects:
		if scene:
			_add_effect(scene.instantiate(), Vector3(x, 0, 0))
			x += 1.5
	var seen := {}
	for group in model_groups:
		for n in get_tree().get_nodes_in_group(group):
			var key : String = n.scene_file_path
			var visual := n.get_node_or_null("Visual") as Node3D
			if visual and not seen.has(key):
				seen[key] = true
				_add_model(visual, Vector3(-1.0 + seen.size() * 0.7, -0.8, -1))
	for path in extra_models:
		var m := get_node_or_null(path) as Node3D
		if m:
			_add_model(m, Vector3(0, -1.5, -2))

	# Remove it all after a moment, or as soon as the intro is skipped / ends.
	for i in warm_frames:
		await RenderingServer.frame_post_draw
		if _holder == null:
			return                             # intro was skipped: already cleaned up
	_cleanup()


var _intro : Node

func _process(_delta: float) -> void:
	if _holder and (not is_instance_valid(_intro) or _intro.get("_ending")):
		_cleanup()


func _add_effect(fx: Node3D, at: Vector3) -> void:
	_holder.add_child(fx)                      # its _ready() hides the bolt; undo that below
	fx.position = at
	fx.scale = Vector3.ONE * 0.3
	fx.set_process(false)                      # stay put: no flying, no hit checks
	fx.set_physics_process(false)
	for n in fx.find_children("*", "Node3D", true, false):
		if n is CollisionObject3D:
			n.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		n.visible = true
		if n is GPUParticles3D:
			n.emitting = true
			n.restart()


func _add_model(src: Node3D, at: Vector3) -> void:
	var copy := src.duplicate(0) as Node3D     # 0 = no scripts, signals or groups
	_holder.add_child(copy)
	copy.position = at
	copy.scale = Vector3.ONE * 0.5


func _cleanup() -> void:
	if is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	if not is_queued_for_deletion():
		print("ShaderWarmer: done")
		queue_free()
