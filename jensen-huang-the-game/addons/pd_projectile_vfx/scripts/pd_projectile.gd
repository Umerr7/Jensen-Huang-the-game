extends Node3D
## Pixel Dreamer Projectile VFX - cast, fly and hit in one scene.
## Place the root at the caster's feet. The bolt leaves from `muzzle` (local offset, 1 m up by default).
##
## PDVFX lives in addons/pd_vfx_tools. Keep that folder in your project too.
##
##   var fx = PDVFX.spawn(preload("res://addons/pd_projectile_vfx/effects/Fireball_Orange.tscn"), self, global_position)
##   fx.launch(enemy.global_position + Vector3.UP)    # cast, fly to the target, play the hit
##   fx.hit.connect(func(at): enemy.take_damage(10))   # fires on impact
##
## No target position (first person, twin-stick)? Give a direction - the script casts the ray for you:
##
##   fx.hit_ignore = [self]                       # the caster's own body
##   fx.hit_target.connect(_on_fireball_hit)      # func _on_fireball_hit(at: Vector3, what: Node)
##   fx.launch_dir(-camera.global_basis.z, 30.0)  # flies to the first body on `hit_mask`, or 30 m
##
## `what` = the body the shot met (null = nothing in the way). Check it there:
##   if what and what.is_in_group("enemies"): what.take_damage(10)
##
## `hit_area = true`: the bolt also stops at the first body it touches on the way (moving targets),
## and carries an Area3D in the group "pd_projectile" that your own nodes can detect:
##   func _on_area_entered(area): if area.is_in_group("pd_projectile"): burn()
## `hit_body = true`: the same, but the bolt carries a small physics body, for targets that listen
## to body_entered instead:
##   func _on_body_entered(body): if body.is_in_group("pd_projectile"): burn()
## Both are off by default: the effect is visual only until you ask. A shot that blows up in your
## face is hitting the caster: add them to `hit_ignore`.
##
## play() shoots along the root's +X for `travel` meters (demo scenes, quick tests).
## Children: Cast (plays at the muzzle) - Bolt, Bolt2... (fly; children named Trail_* stay behind
## in world space) - Hit (plays at the target).

signal hit(at: Vector3)
## Fires right after `hit`. `what` = the body (or area) the shot met, found by launch_dir()'s ray
## or by the bolt's hit area. null = it reached the end without touching anything.
signal hit_target(at: Vector3, what: Node)

@export var speed := 10.0  ## meters per second
@export var travel := 6.0  ## play(): distance along the root's +X
@export var muzzle := Vector3(0, 1, 0)  ## launch point, local to the root
@export var cast_time := 0.25  ## delay between the cast flash and the launch
@export var arc_height := 0.0  ## > 0 = lobbed shot (rock, poison)
@export var curve := 0.0  ## sideways bend - with several Bolts each one bends a different way
@export var ground_hit := false  ## play(): land on the ground (y = 0) instead of at muzzle height
@export var from_sky := false  ## meteor: falls from sky_offset above the target
@export var sky_offset := Vector3(-3, 9, 0)
@export var free_after_hit := false  ## queue_free() 3 s after the hit
@export var repeat_every := 0.0  ## demo: replay on a timer
@export var play_on_ready := false

@export_group("Hit detection (optional)")
@export var hit_area := false  ## the bolt stops at the first body it touches, and carries an Area3D your targets can detect (area_entered)
@export var hit_body := false  ## the bolt stops at the first body it touches, and carries a small physics body your targets can detect (body_entered)
@export var hit_radius := 0.25  ## how fat the bolt is for hit detection, in meters
@export_flags_3d_physics var hit_mask := 1  ## physics layers the shot can hit (hit_area and launch_dir())
@export_flags_3d_physics var hit_layer := 1  ## physics layer the bolt's own Area3D and body sit on
@export var hit_areas := false  ## also stop at Area3D nodes (hurtboxes), not only bodies
@export var hit_group := "pd_projectile"  ## group of the bolt's Area3D and body, for targets that detect it themselves

## Nodes the shot passes through, e.g. [self] for the caster (bodies and areas inside them count too).
## A CharacterBody3D, RigidBody3D or Area3D above this node in the tree is skipped already.
var hit_ignore: Array = []

const _LINGER := 3  # physics frames the bolt stays detectable at the impact point

var _what: Node = null
var _areas: Array[Area3D] = []
var _bodies: Array[AnimatableBody3D] = []
var _linger := 0
var _fresh := false
var _skip: Array[RID] = []
var _prev: Array[Vector3] = []
var _ball := SphereShape3D.new()
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := -1.0
var _wait := 0.0
var _clock := 0.0
var _bolts: Array[Node3D] = []


func _ready() -> void:
	for c in get_children():
		if c is Node3D and String(c.name).begins_with("Bolt"):
			_bolts.append(c)
	_set_bolts(false)
	set_physics_process(false)
	if play_on_ready:
		play()


## Fire along +X for `travel` meters (or drop the meteor on the root).
func play() -> void:
	if from_sky:
		launch(global_position)
		return
	var end := muzzle + Vector3(travel, 0, 0)
	if ground_hit:
		end.y = 0.0
	launch(to_global(end))


## Cast at the muzzle, then fly to `target` (world position) and play the hit there.
func launch(target: Vector3) -> void:
	_what = null
	_to = target
	_from = target + sky_offset * _s() if from_sky else to_global(muzzle)
	var cast := get_node_or_null("Cast") as Node3D
	if cast:
		cast.global_position = target if from_sky else _from
		_restart(cast)
	_sync_detect()
	_set_bolts(false)
	_detectable(false)
	for b in _bolts:
		b.global_position = _from
	_skip = _skip_rids()
	_prev.clear()
	_linger = 0
	_fresh = false
	set_physics_process(hit_area or hit_body)
	_t = 0.0
	_wait = cast_time
	if _wait <= 0.0:
		_go()


## Cast, then fly along `dir` (world space) until the shot meets a body on `hit_mask`, or for
## `max_range` meters. Returns what the ray found (null = nothing in the way); the same node
## arrives in `hit_target` on impact.
func launch_dir(dir: Vector3, max_range: float = 30.0) -> Node:
	if dir.length() < 0.0001:
		return null
	var from := to_global(muzzle)
	var to := from + dir.normalized() * max_range
	var q := PhysicsRayQueryParameters3D.create(from, to, hit_mask, _skip_rids())
	q.collide_with_areas = hit_areas
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		to = r.position
	launch(to)
	_what = r.collider as Node if not r.is_empty() else null
	return _what


# hit_area / hit_body: every physics frame, sweep from where each bolt was to where it is now (a
# ray, so thin walls and fast shots are caught), then check a sphere of hit_radius around it.
func _physics_process(_delta: float) -> void:
	if _linger > 0:
		_linger -= 1
		if _linger == 0:
			_detectable(false)  # a hidden bolt must not be detected
		return
	if not (hit_area or hit_body) or _t < 0.0 or _wait > 0.0 or _prev.size() != _bolts.size():
		return
	var space := get_world_3d().direct_space_state
	for i in _bolts.size():
		var p := _bolts[i].global_position
		var at := p
		var found: Object = null
		if _fresh:  # what the bolt already overlaps where it starts (a caster that is not ignored)
			found = _touch(space, _prev[i])
			if found:
				at = _prev[i]
		if found == null and not p.is_equal_approx(_prev[i]):
			var q := PhysicsRayQueryParameters3D.create(_prev[i], p, hit_mask, _skip)
			q.collide_with_areas = hit_areas
			var r := space.intersect_ray(q)
			if not r.is_empty():
				found = r.collider
				at = r.position
		if found == null:
			found = _touch(space, p)
		_prev[i] = p
		if found is Node and hit_group != "" and (found as Node).is_in_group(hit_group):
			_skip.append((found as CollisionObject3D).get_rid())  # another projectile: fly through it
			found = null
		if found:
			_to = at
			_what = found as Node
			_impact(_fresh)
			return
	if _fresh:
		_fresh = false
		_detectable(true)  # clear of the muzzle: targets can detect the bolt from here on


# The first body (or area, with hit_areas) within hit_radius of `pos`. 2 cm fatter than the bolt's
# own Area3D / body, so a character that walks into the bolt is hit instead of leaning on it.
func _touch(space: PhysicsDirectSpaceState3D, pos: Vector3) -> Object:
	var s := PhysicsShapeQueryParameters3D.new()
	_ball.radius = hit_radius * _s() + 0.02
	s.shape = _ball
	s.transform = Transform3D(Basis.IDENTITY, pos)
	s.collision_mask = hit_mask
	s.exclude = _skip
	s.collide_with_areas = hit_areas
	var near := space.intersect_shape(s, 1)
	return near[0].collider if not near.is_empty() else null


func _process(delta: float) -> void:
	if repeat_every > 0.0:
		_clock += delta
		if _clock >= repeat_every:
			_clock = 0.0
			play()
	if _t < 0.0:
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_go()
		return
	_t = minf(1.0, _t + delta * speed * _s() / maxf(_from.distance_to(_to), 0.01))
	_place(_t)
	if _t >= 1.0:
		_impact()


func _go() -> void:
	_wait = 0.0
	_place(0.0)
	_prev.clear()
	for b in _bolts:
		_prev.append(b.global_position)
	_set_bolts(true)
	_fresh = true  # _physics_process switches the bolt's Area3D / body on once it is clear of the muzzle


func _pos(i: int, t: float) -> Vector3:
	var d := (_to - _from).normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(d)
	var bend := 4.0 * t * (1.0 - t)
	var a := TAU * float(i) / float(maxi(_bolts.size(), 1))
	return _from.lerp(_to, t) + (Vector3.UP * arc_height + (side * cos(a) + up * sin(a)) * curve) * bend * _s()


func _place(t: float) -> void:
	for i in _bolts.size():
		var p := _pos(i, t)
		var v := _pos(i, minf(t + 0.02, 1.0)) - p if t < 0.98 else p - _pos(i, t - 0.02)
		_bolts[i].global_position = p
		if v.length() > 0.0001:
			_face(_bolts[i], v.normalized())


func _face(b: Node3D, x: Vector3) -> void:
	var ref := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var z := x.cross(ref).normalized()
	b.global_basis = Basis(x, z.cross(x), z).scaled(Vector3.ONE * _s())


func _impact(at_muzzle := false) -> void:
	_t = -1.0
	_fresh = false
	_set_bolts(false)
	if at_muzzle or not is_physics_processing() or (_areas.is_empty() and _bodies.is_empty()):
		_detectable(false)
	else:
		_detectable(true)
		_radius(hit_radius + 0.06 / maxf(_s(), 0.01))  # reach a target the bolt stopped a hair short of
		_linger = _LINGER  # the target at the impact point gets a moment to notice the bolt
	var h := get_node_or_null("Hit") as Node3D
	if h:
		h.global_position = _to
		_restart(h)
	var what: Node = _what if is_instance_valid(_what) else null
	_what = null
	hit.emit(_to)
	hit_target.emit(_to, what)
	if free_after_hit:
		get_tree().create_timer(3.0).timeout.connect(queue_free)


# hit_area / hit_body: one sphere Area3D / AnimatableBody3D per bolt, made on the first launch that
# asks for it. They only let other nodes detect the bolt (area_entered / body_entered); the bolt
# finds its own hits in _physics_process.
func _sync_detect() -> void:
	if hit_area and _areas.is_empty():
		for b in _bolts:
			var a := Area3D.new()
			a.name = "HitArea"
			a.monitoring = false
			a.monitorable = false
			a.collision_mask = 0
			a.add_child(_ball_shape(false))
			b.add_child(a)
			_areas.append(a)
	if hit_body and _bodies.is_empty():
		for b in _bolts:
			var k := AnimatableBody3D.new()
			k.name = "HitBody"
			k.sync_to_physics = false  # it rides the bolt node
			k.collision_mask = 0
			k.add_child(_ball_shape(true))
			b.add_child(k)
			_bodies.append(k)
	_radius(hit_radius)
	for o in _detectors():
		o.collision_layer = hit_layer
		if hit_group != "" and not o.is_in_group(hit_group):
			o.add_to_group(hit_group)
	if _bodies.is_empty():
		return
	var skip := _ignored()  # the bolt's body never shoves what the shot passes through
	for k in _bodies:
		for e in k.get_collision_exceptions():
			k.remove_collision_exception_with(e)
		for n in skip:
			if n is PhysicsBody3D and n != k:
				k.add_collision_exception_with(n)


func _ball_shape(off: bool) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = SphereShape3D.new()
	cs.disabled = off
	return cs


func _radius(r: float) -> void:
	for o in _detectors():
		((o.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius = r


func _detectors() -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	for a in _areas:
		out.append(a)
	for k in _bodies:
		out.append(k)
	return out


# Bolts are only detectable while they fly (and for a moment at the impact point).
func _detectable(on: bool) -> void:
	for a in _areas:
		a.set_deferred("monitorable", on and hit_area)
	for k in _bodies:
		(k.get_child(0) as CollisionShape3D).set_deferred("disabled", not (on and hit_body))


# Nodes the shot passes through: hit_ignore (with the bodies and areas inside those nodes) and
# the caster when the projectile is its child.
func _ignored() -> Array[CollisionObject3D]:
	var nodes: Array = hit_ignore.filter(func(n): return is_instance_valid(n) and n is Node)
	var p := get_parent()
	while p:
		if p is CollisionObject3D and not p is StaticBody3D:
			nodes.append(p)
		p = p.get_parent()
	var out: Array[CollisionObject3D] = []
	for n in nodes:
		if n is CollisionObject3D:
			out.append(n as CollisionObject3D)
		for c in (n as Node).find_children("*", "CollisionObject3D", true, false):
			out.append(c as CollisionObject3D)
	return out


# What the shot never hits: its own area and body, other projectiles (hit_group) and _ignored().
func _skip_rids() -> Array[RID]:
	var out: Array[RID] = []
	for o in _detectors():
		out.append(o.get_rid())
	if hit_group != "" and is_inside_tree():
		for n in get_tree().get_nodes_in_group(hit_group):
			if n is CollisionObject3D:
				out.append((n as CollisionObject3D).get_rid())
	for o in _ignored():
		out.append(o.get_rid())
	return out


func _set_bolts(on: bool) -> void:
	for b in _bolts:
		for c in b.get_children():
			if c is CollisionObject3D:
				continue  # HitArea / HitBody: see _detectable()
			if String(c.name).begins_with("Trail") and c is GPUParticles3D:
				var p := c as GPUParticles3D
				if on:
					p.local_coords = false  # the trail stays behind, even after PDVFX.set_scale()
					p.restart()
					p.emitting = true
				else:
					p.emitting = false
			elif c is Node3D:
				(c as Node3D).visible = on
				if on and c is GPUParticles3D:
					(c as GPUParticles3D).restart()


func _restart(n: Node) -> void:
	for p in n.find_children("*", "GPUParticles3D", true, false):
		p.restart()


func _s() -> float:
	return global_basis.get_scale().x
