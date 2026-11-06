extends Node
## Datos públicos del caso: content/public/{world,characters,evidence}.json.
## Si existe content/generated/characters_public.json (fase B2), aporta biografía y edad.

var world: Dictionary = {}
var characters: Dictionary = {}
var evidence: Dictionary = {}
var generated: Dictionary = {}

var _witnesses: Dictionary = {}
var _suspects: Dictionary = {}
var _evidence: Dictionary = {}
var _locations: Dictionary = {}
var _objects: Dictionary = {}  # object_id -> objeto + "location_id"


func _ready() -> void:
	reload()


func reload() -> void:
	world = _load_dict(Paths.content("public/world.json"))
	characters = _load_dict(Paths.content("public/characters.json"))
	evidence = _load_dict(Paths.content("public/evidence.json"))
	var gen: Variant = Paths.read_json(Paths.content("generated/characters_public.json"))
	generated = {}
	if gen is Dictionary:
		generated = gen
	elif gen is Array:
		for item: Variant in gen:
			if item is Dictionary and (item as Dictionary).has("id"):
				generated[(item as Dictionary)["id"]] = item

	_witnesses = _index(characters.get("witnesses", []))
	_suspects = _index(characters.get("suspects", []))
	_evidence = _index(evidence.get("evidence", []))
	_locations = _index(world.get("locations", []))
	_objects.clear()
	for loc: Dictionary in world.get("locations", []):
		for obj: Dictionary in loc.get("objects", []):
			var o: Dictionary = obj.duplicate()
			o["location_id"] = loc["id"]
			_objects[obj["id"]] = o


func witness_ids(only_mvp: bool = false) -> Array[String]:
	var out: Array[String] = []
	for w: Dictionary in characters.get("witnesses", []):
		if not only_mvp or bool(w.get("mvp", false)):
			out.append(w["id"])
	return out


func suspect_ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in characters.get("suspects", []):
		out.append(s["id"])
	return out


func witness(id: String) -> Dictionary:
	return _witnesses.get(id, {})


func suspect(id: String) -> Dictionary:
	return _suspects.get(id, {})


func evidence_item(id: String) -> Dictionary:
	return _evidence.get(id, {})


func location(id: String) -> Dictionary:
	return _locations.get(id, {})


func game_object(id: String) -> Dictionary:
	return _objects.get(id, {})


func objects_in(location_id: String) -> Array:
	return location(location_id).get("objects", [])


## Nombre para mostrar de cualquier id (testigo, sospechoso, evidencia, lugar u objeto).
func display_name(id: String) -> String:
	for table: Dictionary in [_witnesses, _suspects, _evidence, _locations, _objects]:
		if table.has(id):
			return str((table[id] as Dictionary).get("name", id))
	return id


## Biografía corta: la generada en B2 si existe; si no, el rol.
func bio(id: String) -> String:
	var g: Dictionary = generated.get(id, {})
	if g.has("bio"):
		return str(g["bio"])
	return str(witness(id).get("role", suspect(id).get("epithet", "")))


func _load_dict(path: String) -> Dictionary:
	var v: Variant = Paths.read_json(path)
	if v is Dictionary:
		return v
	push_error("No se pudo leer %s" % path)
	return {}


func _index(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for item: Dictionary in items:
		out[item["id"]] = item
	return out
