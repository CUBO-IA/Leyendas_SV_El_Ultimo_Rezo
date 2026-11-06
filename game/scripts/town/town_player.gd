class_name TownPlayer
extends CharacterBody2D
## Jugador top-down en 4 direcciones. Enfoca el Interactable más cercano a su alcance.

signal focus_changed(target: Interactable)

const SPEED := 72.0
const REACH := 20.0

var facing: String = "down"
var frozen: bool = false
var focus: Interactable = null
## Para pruebas automáticas: si no es cero, reemplaza al teclado.
var input_override: Vector2 = Vector2.ZERO

var _sprite: AnimatedSprite2D
var _reach: Area2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var feet: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(10, 6)
	feet.shape = rect
	feet.position = Vector2(0, -3)
	add_child(feet)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = CharSprites.frames_for("player")
	_sprite.offset = Vector2(0, -12)
	add_child(_sprite)
	_sprite.play("idle_down")

	_reach = Area2D.new()
	_reach.collision_layer = 0
	_reach.collision_mask = Interactable.LAYER
	var rs: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = REACH
	rs.shape = circle
	rs.position = Vector2(0, -6)
	_reach.add_child(rs)
	add_child(_reach)


func _physics_process(_delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if not frozen:
		dir = input_override if input_override != Vector2.ZERO else \
			Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 4 direcciones: gana el eje con más empuje.
	if absf(dir.x) > absf(dir.y):
		dir = Vector2(signf(dir.x), 0)
	elif dir.y != 0.0:
		dir = Vector2(0, signf(dir.y))
	velocity = dir * SPEED
	move_and_slide()

	if dir != Vector2.ZERO:
		facing = CharSprites.facing(Vector2.ZERO, dir)
		_sprite.play("walk_" + facing)
	else:
		_sprite.play("idle_" + facing)
	_update_focus()


func _update_focus() -> void:
	var best: Interactable = null
	var best_d: float = INF
	if not frozen:
		for a: Area2D in _reach.get_overlapping_areas():
			var it: Interactable = a as Interactable
			if it == null or not it.visible:
				continue
			var d: float = it.global_position.distance_squared_to(global_position)
			if d < best_d:
				best_d = d
				best = it
	if best != focus:
		focus = best
		focus_changed.emit(focus)
