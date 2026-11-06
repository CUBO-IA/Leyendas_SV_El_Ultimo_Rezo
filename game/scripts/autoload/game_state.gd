extends Node
## Último WorldState recibido del Backend (mock o http). Las escenas leen de aquí
## y escuchan world_changed; nunca modifican el estado por su cuenta.

signal world_changed(state: Dictionary)
signal game_ended(ending: Dictionary)

var world: Dictionary = {}
var last_ending: Dictionary = {}


func apply_state(state: Dictionary) -> void:
	world = state
	world_changed.emit(world)


func end_game(ending: Dictionary) -> void:
	last_ending = ending
	world["ended"] = true
	game_ended.emit(ending)


func reset() -> void:
	world = {}
	last_ending = {}


func has_session() -> bool:
	return world.has("session_id")


func session_id() -> String:
	return str(world.get("session_id", ""))


func act() -> int:
	return int(world.get("act", 1))


func npc(id: String) -> Dictionary:
	for n: Dictionary in world.get("npcs", []):
		if n["id"] == id:
			return n
	return {}


func evidence_ids() -> Array[String]:
	var out: Array[String] = []
	for e: Variant in world.get("evidence", []):
		out.append(str(e))
	return out


func has_evidence(id: String) -> bool:
	return id in world.get("evidence", [])


func is_unlocked(location_id: String) -> bool:
	return location_id in world.get("unlocked_locations", [])


## "23:47" -> "11:47 p. m."
func clock_text() -> String:
	return format_clock(str(world.get("clock", "23:47")))


func format_clock(hhmm: String) -> String:
	var parts: PackedStringArray = hhmm.split(":")
	if parts.size() != 2:
		return hhmm
	var h: int = int(parts[0])
	var suffix: String = "a. m." if h < 12 else "p. m."
	var h12: int = h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%s %s" % [h12, parts[1], suffix]


const LEVEL_NAMES: Dictionary = {
	"inicial": "Declaración",
	"confrontada": "Confrontada",
	"confesion": "Confesión parcial",
}


func level_name(level: String) -> String:
	return LEVEL_NAMES.get(level, level)
