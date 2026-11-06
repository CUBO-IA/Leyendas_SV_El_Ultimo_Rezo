class_name Interactable
extends Area2D
## Algo con lo que el jugador puede interactuar con E: un testigo o un objeto.
## El jugador detecta estas áreas (capa 2) y enfoca la más cercana.

const LAYER := 2

@export var kind: String = "object"  ## "witness" | "object"
@export var target_id: String = ""
@export var radius: float = 16.0


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)


## Texto de la pista en el HUD, p. ej. "E · Examinar Comal".
func prompt() -> String:
	var name_text: String = ContentDB.display_name(target_id)
	if kind == "witness":
		return "E · Hablar con %s" % name_text
	return "E · Examinar %s" % name_text
