# A blaster lying in the world. Spins and bobs; when the player walks into it,
# they get the weapon and this pickup disappears.
extends Area3D

## Degrees per second the pickup spins.
@export var spin_speed : float = 90.0
## How far (m) it floats up and down.
@export var bob_height : float = 0.15
## Bobs per second.
@export var bob_speed : float = 1.5

@onready var _model : Node3D = $Model
var _start_y : float
var _time : float = 0.0


func _ready() -> void:
	_start_y = _model.position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_model.rotate_y(deg_to_rad(spin_speed) * delta)
	_model.position.y = _start_y + sin(_time * TAU * bob_speed) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("pick_up_weapon"):
		body.pick_up_weapon()
		queue_free()
