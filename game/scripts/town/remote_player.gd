class_name RemotePlayer
extends Node2D
## Otro jugador conectado al mismo motor (Presence). Sprite del investigador con otro
## color, su nombre encima y movimiento suavizado hacia la última posición recibida.
## No choca con nada ni se puede interactuar con él.

const SMOOTH := 12.0
const TELEPORT := 120.0  ## si la distancia es mayor (cambio de escena), salta directo

var peer_id: String = ""
var peer_name: String = ""
var target: Vector2
var facing: String = "down"
var moving: bool = false
var _sprite: AnimatedSprite2D
var _label: Label


static func create(id: String, data: Dictionary) -> RemotePlayer:
	var n: RemotePlayer = RemotePlayer.new()
	n.peer_id = id
	n.name = "R_" + id
	n.peer_name = str(data.get("name", "?"))
	n.position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	n.target = n.position
	return n


## Color propio por jugador (estable: sale del id).
static func tint_for(id: String) -> Color:
	var h: float = float(absi(hash(id)) % 360) / 360.0
	return Color.from_hsv(h, 0.45, 1.0)


func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = CharSprites.frames_for("player")
	_sprite.offset = Vector2(0, -12)
	_sprite.modulate = tint_for(peer_id)
	_sprite.play("idle_down")
	add_child(_sprite)
	_label = Label.new()
	_label.text = peer_name
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", tint_for(peer_id).lightened(0.3))
	_label.add_theme_constant_override("outline_size", 3)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(80, 12)
	_label.position = Vector2(-40, -36)
	add_child(_label)
	var glow: PointLight2D = ExploreBase.make_light(tint_for(peer_id), 0.6, 0.5)
	glow.position = Vector2(0, -10)
	add_child(glow)


func apply(data: Dictionary) -> void:
	target = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	facing = str(data.get("f", "down"))
	moving = bool(data.get("m", false))
	if position.distance_to(target) > TELEPORT:
		position = target


func _process(delta: float) -> void:
	position = position.lerp(target, clampf(SMOOTH * delta, 0.0, 1.0))
	var anim: String = ("walk_" if moving or position.distance_to(target) > 1.0 else "idle_") + facing
	if _sprite.animation != anim:
		_sprite.play(anim)
