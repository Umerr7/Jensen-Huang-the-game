# A shot that does damage, using one of the Pixel Dreamer VFX scenes as its look.
#
# Both the player and the transistor enemies fire these. The VFX scene
# (addons/pd_projectile_vfx/effects/...) handles the visuals AND the flying/hit
# detection; this script just aims it and deals damage when it lands.
#
# Same launch() as the enemy's old EnergyProjectile, so TransistorEnemy can
# use it without any code changes.
extends Node3D

## Which effect to use (Magic_Bullet_Cyan, Fireball_Orange, Ice_Shard_Ice...).
@export var effect : PackedScene
## Metres per second.
@export var speed : float = 30.0
## Damage dealt to whatever it hits (if that thing has take_damage()).
@export var damage : float = 15.0
## How far it flies if it hits nothing.
@export var max_range : float = 60.0
## Delay before the bolt leaves the gun (the muzzle flash). 0 = instant.
@export var cast_time : float = 0.0
## Physics layers it can hit. 1 = world + player, 2 = enemies.
@export_flags_3d_physics var hit_mask : int = 1
## How fat the bolt is for hit detection, in metres (multiplied by this node's scale).
@export var hit_radius : float = 0.25
## Pitch of the firing / impact sounds (lower = heavier gun). 0 = silent.
@export var sound_pitch : float = 1.0

var _fx : Node3D


## Fire in a direction. `shooter` is never hit by its own shot.
func launch(direction: Vector3, shooter: Node = null, speed_override: float = -1.0, damage_override: float = -1.0) -> void:
	launch_at(global_position + direction.normalized() * max_range, shooter, speed_override, damage_override)


## Fire at a point in the world (e.g. exactly where the crosshair is pointing).
func launch_at(target: Vector3, shooter: Node = null, speed_override: float = -1.0, damage_override: float = -1.0) -> void:
	if speed_override > 0.0: speed = speed_override
	if damage_override > 0.0: damage = damage_override
	_fx = effect.instantiate()
	add_child(_fx)
	_fx.muzzle = Vector3.ZERO          # the bolt starts right here (this node sits at the gun barrel)
	_fx.speed = speed
	_fx.cast_time = cast_time
	_fx.hit_area = true                # let the effect stop at the first thing it touches
	_fx.hit_mask = hit_mask
	_fx.hit_radius = hit_radius
	_fx.hit_ignore = [shooter] if shooter else []
	_fx.hit_target.connect(_on_hit)
	# Aim THROUGH the target point, not at it: a bolt that ends its flight exactly on a
	# surface can finish before its hit check runs. It still stops at the first thing it touches.
	var dir := (target - global_position).normalized()
	var dist := maxf(global_position.distance_to(target) + 3.0, max_range)
	_fx.launch(global_position + dir * dist)
	if sound_pitch > 0.0:
		GameAudio.sfx(self, "laser_shot", global_position, -3.0, sound_pitch)


func _on_hit(_at: Vector3, what: Node) -> void:
	if sound_pitch > 0.0:
		GameAudio.sfx(self, "laser_hit", _at, -2.0, sound_pitch)
	if what and what.has_method("take_damage"):
		what.take_damage(damage)   # enemies lose `damage` health; Jensen loses 1 life whatever the number
	# let the explosion/sparks finish playing, then clean up
	get_tree().create_timer(2.0).timeout.connect(queue_free)
