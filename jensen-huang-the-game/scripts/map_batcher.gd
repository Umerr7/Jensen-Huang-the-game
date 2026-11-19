# Performance helper for the level. Add it as a child of the level and point
# `target` at the map. When the level starts it:
#
#   1. Merges every static mesh in the map that shares a material into ONE mesh.
#      The map is ~440 separate parts (so it stays editable), and each part costs
#      a draw call; in a browser that's what made the middle of the map run at
#      ~20 FPS. Merged, it's ~25 draw calls. The original parts are only hidden,
#      so their colliders keep working and the map stays editable in the editor.
#   2. Does the same for each enemy's model (a transistor is 18 pieces -> ~8).
#   3. In web builds, makes shadows cheaper (shorter range, smaller shadow map).
extends Node

## The map to merge (its static MeshInstance3D children).
@export var target : NodePath = ^"../MotherboardMap"
## Turn off to compare / debug: the map is then drawn part by part again.
@export var merge_meshes : bool = true

@export_group("Web shadows")
## Shadows only this far from the camera (m) in browser builds.
@export var web_shadow_distance : float = 45.0
## Shadow map resolution in browser builds (desktop keeps the project setting).
@export var web_shadow_size : int = 2048


func _ready() -> void:
	# Wait one frame so everything in the level has finished its own _ready().
	await get_tree().process_frame
	if OS.has_feature("web"):
		_cheaper_shadows()
	if merge_meshes:
		var map := get_node_or_null(target) as Node3D
		if map:
			_merge(map)
		# Enemy models: merged inside their "Visual" node, so they still move,
		# turn and pulse exactly as before.
		var enemy_parts := 0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var visual := enemy.get_node_or_null("Visual") as Node3D
			if visual:
				enemy_parts += _merge(visual, false)
		if enemy_parts > 0:
			print("MapBatcher: merged %d enemy model parts" % enemy_parts)


func _cheaper_shadows() -> void:
	RenderingServer.directional_shadow_atlas_set_size(web_shadow_size, true)
	for light in get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
		light.directional_shadow_max_distance = web_shadow_distance
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func _merge(map: Node3D, log_it := true) -> int:
	var to_map := map.global_transform.affine_inverse()
	var tools := {}        # material -> SurfaceTool collecting all its geometry
	var shadows := {}      # material -> cast_shadow setting
	var merged := 0
	for mi in map.find_children("*", "MeshInstance3D", true, false):
		if not _is_static(mi, map):
			continue
		var xf : Transform3D = to_map * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var mat : Material = mi.get_active_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				shadows[mat] = mi.cast_shadow
			tools[mat].append_from(mi.mesh, s, xf)
		mi.visible = false      # hidden, not deleted: its collider is a sibling and still works
		merged += 1
	var batches := 0
	for mat in tools:
		var st : SurfaceTool = tools[mat]
		st.set_material(mat)
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var batch := MeshInstance3D.new()
		batch.name = "Merged_%d" % batches
		batch.mesh = mesh
		batch.cast_shadow = shadows[mat]
		map.add_child(batch)
		batches += 1
	if log_it:
		print("MapBatcher: merged %d map parts into %d meshes" % [merged, batches])
	return merged


## Only plain, visible, non-moving map pieces get merged (not enemies, not
## anything inside a character or a moving body).
func _is_static(mi: MeshInstance3D, map: Node) -> bool:
	if mi.mesh == null or not mi.is_visible_in_tree() or mi.skin != null:
		return false
	var n : Node = mi.get_parent()
	while n and n != map:
		if n is RigidBody3D or n is AnimatableBody3D or n is Skeleton3D or (n is CharacterBody3D and n != map.get_parent()):
			return false
		n = n.get_parent()
	return true
