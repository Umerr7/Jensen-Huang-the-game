# Top-left HUD: one graphics card per life.
# A full (RGB) card = a life left, a burnt card = a life lost.
# Finds the player through the "player" group and listens to its
# health_changed signal, so it works in any level that has Jensen in it.
extends CanvasLayer

@export var card_full : Texture2D = preload("res://assets/heart-full.png")
@export var card_gone : Texture2D = preload("res://assets/heart-gone.png")
## On-screen size of each card, in pixels.
@export var card_size : Vector2 = Vector2(80, 30)

@onready var _row : HBoxContainer = $Margin/Cards
var _cards : Array[TextureRect] = []
var _shown_lives : int = -1


func _ready() -> void:
	# Wait one frame so the player has run its own _ready() and set its health.
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("LivesHUD: no node in the 'player' group")
		return
	_build(int(player.max_health))
	_show(int(player.health), false)
	player.health_changed.connect(func(current, _maximum): _show(int(current), true))


func _build(count: int) -> void:
	for c in _row.get_children():
		c.queue_free()
	_cards.clear()
	for i in count:
		var card := TextureRect.new()
		card.texture = card_full
		card.custom_minimum_size = card_size
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.pivot_offset = card_size / 2.0
		_row.add_child(card)
		_cards.append(card)


func _show(lives: int, animate: bool) -> void:
	for i in _cards.size():
		var alive := i < lives
		var was_alive := i < _shown_lives
		_cards[i].texture = card_full if alive else card_gone
		_cards[i].modulate = Color.WHITE if alive else Color(1, 1, 1, 0.75)
		if animate and was_alive and not alive:
			_pop(_cards[i])          # this card just burnt out
	_shown_lives = lives


## Quick "fried" shake: flash red, jolt bigger, settle back.
func _pop(card: TextureRect) -> void:
	var tw := create_tween()
	card.scale = Vector2(1.35, 1.35)
	card.self_modulate = Color(1, 0.35, 0.35)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "self_modulate", Color.WHITE, 0.5)
