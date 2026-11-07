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
# Caminar con el mouse: va al destino en 4 direcciones, primero por el eje más largo;
# si choca, prueba un rato por el otro eje y, si sigue atorado, se rinde.
var _target: Vector2
var _walking: bool = false
var _stuck_s: float = 0.0
var _detour_s: float = 0.0
var _give_up_s: float = 0.0
var _detour_sign: float = 1.0


## Camina hasta `point` (coordenadas del mundo). El teclado lo cancela.
func walk_to(point: Vector2) -> void:
	_target = point
	_walking = true
	_stuck_s = 0.0
	_detour_s = 0.0
	_give_up_s = 0.0


func stop_walking() -> void:
	_walking = false


func is_walking() -> bool:
	return _walking


func _auto_dir(delta: float) -> Vector2:
	var to: Vector2 = _target - global_position
	if to.length() < 2.5 or _give_up_s > 2.5:
		_walking = false
		return Vector2.ZERO
	var main_x: bool = absf(to.x) > absf(to.y)
	if _detour_s > 0.0:
		# Rodeo por el otro eje; si el destino ya está alineado en ese eje, hacia _detour_sign.
		_detour_s -= delta
		if main_x:
			return Vector2(0, signf(to.y) if absf(to.y) >= 1.5 else _detour_sign)
		return Vector2(signf(to.x) if absf(to.x) >= 1.5 else _detour_sign, 0)
	return Vector2(signf(to.x), 0) if main_x else Vector2(0, signf(to.y))


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


func _physics_process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if not frozen:
		dir = input_override if input_override != Vector2.ZERO else \
			Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if dir != Vector2.ZERO:
			_walking = false  # el teclado manda
		elif _walking:
			dir = _auto_dir(delta)
	else:
		_walking = false
	# 4 direcciones: gana el eje con más empuje.
	if absf(dir.x) > absf(dir.y):
		dir = Vector2(signf(dir.x), 0)
	elif dir.y != 0.0:
		dir = Vector2(0, signf(dir.y))
	velocity = dir * SPEED
	var before: Vector2 = global_position
	move_and_slide()
	if _walking and dir != Vector2.ZERO:
		if global_position.distance_to(before) < SPEED * delta * 0.3:
			_stuck_s += delta
			_give_up_s += delta
			if _stuck_s > 0.15:
				if _detour_s > 0.0:
					_detour_sign = -_detour_sign  # el rodeo también chocó: al otro lado
				_detour_s = 0.45  # rodea el obstáculo por el otro eje
				_stuck_s = 0.0
		else:
			_stuck_s = 0.0

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
