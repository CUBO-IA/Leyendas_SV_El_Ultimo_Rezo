class_name Villager
extends CharacterBody2D
## Vecino de ambiente: pasea cerca de su lugar y, al hablarle (E o clic), dice una
## frase suelta del acto actual (content/public/villagers.json). No usa la IA.

const SPEED := 22.0
const WANDER := 18.0  ## cuánto se aleja de su lugar (px)

var data: Dictionary = {}
var home: Vector2
var _sprite: AnimatedSprite2D
var _target: Vector2
var _wait: float = 0.0
var _facing: String = "down"
var talking: bool = false


static func create(v: Dictionary, at: Vector2) -> Villager:
	var n: Villager = Villager.new()
	n.data = v
	n.name = "V_" + str(v["id"])
	n.position = at
	n.home = at
	return n


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var feet: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(8, 5)
	feet.shape = rect
	feet.position = Vector2(0, -3)
	add_child(feet)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = CharSprites.frames_for(str(data["id"]))
	_sprite.offset = Vector2(0, -12)
	_sprite.play("idle_down")
	add_child(_sprite)
	var it: Interactable = Interactable.new()
	it.name = "Interactable"
	it.kind = "villager"
	it.target_id = str(data["id"])
	it.label = "Hablar con %s" % data.get("name", "")
	it.radius = 14.0
	it.position = Vector2(0, -6)
	add_child(it)
	_target = home
	_wait = randf_range(0.5, 3.0)


func _physics_process(delta: float) -> void:
	if talking:
		velocity = Vector2.ZERO
		return
	var to: Vector2 = _target - position
	if to.length() < 1.5:
		velocity = Vector2.ZERO
		_sprite.play("idle_" + _facing)
		_wait -= delta
		if _wait <= 0.0:
			_target = home + Vector2(randf_range(-WANDER, WANDER), randf_range(-WANDER * 0.5, WANDER * 0.5))
			_wait = randf_range(2.0, 5.0)
		return
	var dir: Vector2 = Vector2(signf(to.x), 0) if absf(to.x) > absf(to.y) else Vector2(0, signf(to.y))
	velocity = dir * SPEED
	var before: Vector2 = position
	move_and_slide()
	if position.distance_to(before) < 0.1:
		_target = position  # chocó: se queda ahí y espera
	_facing = CharSprites.facing(Vector2.ZERO, dir)
	_sprite.play("walk_" + _facing)


## La siguiente frase del acto (rota entre las frases de ese acto).
func next_line(act: int, index: int) -> String:
	var lines: Dictionary = data.get("lines", {})
	var pool: Array = lines.get(str(act), lines.get("1", ["..."]))
	return str(pool[index % pool.size()]) if not pool.is_empty() else "..."


## Mira hacia quien le habla.
func face(from: Vector2) -> void:
	_facing = CharSprites.facing(global_position, from)
	_sprite.play("idle_" + _facing)
