class_name MockBackend
extends RefCounted
## Backend simulado: arma las respuestas con contract/fixtures/ y los datos públicos,
## y mantiene su propio WorldState para que el cliente se pueda jugar sin motor.
##
## No conoce la solución del caso (vive solo en el servidor). Lo único que simula
## es el ejemplo del contrato: presentarle registro_electrico a Don Alcides lo
## confronta. Cualquier otra evidencia produce una respuesta evasiva.
## La acusación en mock: con 5 o más evidencias y "revelar" -> verdadero; con 5 o
## más y "negociar" -> gris; si no, malo. Sirve para probar las 3 escenas de final.

const CONTRADICTION := {"npc": "alcides", "evidence": "registro_electrico",
	"fixture": "present_response__alcides_contradiccion"}
const EVASIVE := "present_response__alcides_sin_relacion"
const GENERIC_EVASIVE := "¿Y eso qué tiene que ver conmigo? Yo ya le dije lo que sé."

var state: Dictionary = {}
var _fixtures: Dictionary = {}
var _counter: int = 0


func fixture(fixture_name: String) -> Dictionary:
	if not _fixtures.has(fixture_name):
		var v: Variant = Paths.read_json(Paths.fixture(fixture_name))
		if not v is Dictionary:
			push_error("[Mock] falta la fixture %s" % fixture_name)
			v = {}
		_fixtures[fixture_name] = v
	return (_fixtures[fixture_name] as Dictionary).duplicate(true)


func handle(kind: String, body: Dictionary) -> Dictionary:
	match kind:
		"health":
			var h: Dictionary = fixture("health_response__ok")
			h["model"] = "mock (contract/fixtures)"
			return _ok(h)
		"session":
			return _session(body)
		"get_session":
			if state.is_empty():
				return _err("session_not_found", "No hay partida en el mock.")
			return _ok(state.duplicate(true))
		"stt":
			return _ok(fixture("stt_response__ejemplo"))
		"lobby":  # experimental: en el mock no hay partidas en red
			return _ok({"games": []})
	if state.is_empty():
		return _err("session_not_found", "No existe la sesión %s." % body.get("session_id", ""))
	if bool(state.get("ended", false)):
		return _err("session_ended", "La partida ya terminó.")
	match kind:
		"talk":
			return _talk(body)
		"present":
			return _present(body)
		"examine":
			return _examine(body)
		"accuse":
			return _accuse(body)
	return _err("bad_request", "Ruta desconocida en el mock: %s" % kind)


# ---------- rutas ----------

func _session(body: Dictionary) -> Dictionary:
	var demo: bool = bool(body.get("demo", false))
	state = fixture("world_state__demo" if demo else "world_state__nueva_partida")
	# Las fixtures traen los 6 del MVP; el motor (WITNESSES=all) suma los 4 restantes.
	var have: Array = (state["npcs"] as Array).map(func(n: Dictionary) -> String: return str(n["id"]))
	for id: String in ContentDB.witness_ids():
		if id not in have:
			(state["npcs"] as Array).append({"id": id, "level": "inicial", "trust": 5, "fear": 4, "met": false})
	_counter += 1
	state["session_id"] = "mock-%04d" % _counter
	if demo:
		state["demo"] = true
	_normalize_ints()
	return _ok(state.duplicate(true))


func _talk(body: Dictionary) -> Dictionary:
	var npc: Dictionary = _npc(str(body.get("npc_id", "")))
	if npc.is_empty():
		return _err("bad_npc", "Ese testigo no está en la partida.")
	var id: String = npc["id"]
	var reply: String = str(ContentDB.witness(id).get("intro", "..."))
	var emotion: String = "neutral"
	if id == "chonita" and npc["level"] == "inicial":
		var f: Dictionary = fixture("talk_response__chonita_inicial")
		reply = f["reply"]
		emotion = f["emotion"]
	npc["met"] = true
	return _ok({
		"reply": reply, "emotion": emotion, "level": npc["level"],
		"trust": npc["trust"], "fear": npc["fear"],
		"new_evidence": [], "new_deductions": [], "audio_url": null,
		"source": "cache", "state": state.duplicate(true),
	})


func _present(body: Dictionary) -> Dictionary:
	var npc: Dictionary = _npc(str(body.get("npc_id", "")))
	if npc.is_empty():
		return _err("bad_npc", "Ese testigo no está en la partida.")
	var ev: String = str(body.get("evidence_id", ""))
	if ContentDB.evidence_item(ev).is_empty():
		return _err("bad_evidence", "No existe la evidencia %s." % ev)
	if ev not in state["evidence"]:
		return _err("evidence_not_owned", "Todavía no tienes esa evidencia.")
	npc["met"] = true

	var id: String = npc["id"]
	if id == CONTRADICTION["npc"] and ev == CONTRADICTION["evidence"] and npc["level"] == "inicial":
		var f: Dictionary = fixture(CONTRADICTION["fixture"])
		npc["level"] = f["level"]
		npc["trust"] = int(f["trust"])
		npc["fear"] = int(f["fear"])
		for d: Dictionary in f["new_deductions"]:
			if not _has_deduction(d["id"]):
				(state["deductions"] as Array).append(d)
		return _ok({
			"reply": f["reply"], "emotion": f["emotion"], "contradiction": true,
			"level": npc["level"], "new_deductions": f["new_deductions"], "new_evidence": [],
			"trust": npc["trust"], "fear": npc["fear"], "audio_url": null,
			"source": "cache", "state": state.duplicate(true),
		})

	npc["trust"] = clampi(int(npc["trust"]) - 1, 0, 10)
	var reply: String = GENERIC_EVASIVE
	var emotion: String = "nervioso"
	if id == "alcides":
		var e: Dictionary = fixture(EVASIVE)
		reply = e["reply"]
		emotion = e["emotion"]
	return _ok({
		"reply": reply, "emotion": emotion, "contradiction": false,
		"level": npc["level"], "new_deductions": [], "new_evidence": [],
		"trust": npc["trust"], "fear": npc["fear"], "audio_url": null,
		"source": "cache", "state": state.duplicate(true),
	})


func _examine(body: Dictionary) -> Dictionary:
	var obj_id: String = str(body.get("object_id", ""))
	var obj: Dictionary = ContentDB.game_object(obj_id)
	if obj.is_empty():
		return _err("bad_object", "No existe el objeto %s." % obj_id)
	var loc: Dictionary = ContentDB.location(obj["location_id"])
	if obj["location_id"] not in state["unlocked_locations"] or int(loc.get("act", 1)) > int(state["act"]):
		return _err("location_locked", "Todavía no puedes entrar a %s." % loc.get("name", obj["location_id"]))
	var req: Variant = obj.get("requires_deduction")
	if req != null and str(req) != "" and not _has_deduction(str(req)):
		return _ok({"text": "Todavía no sabes qué buscar aquí.", "new_evidence": [],
			"state": state.duplicate(true)})
	var new_evidence: Array = []
	var ev: Variant = obj.get("evidence_id")
	if ev != null and str(ev) != "" and str(ev) not in state["evidence"]:
		(state["evidence"] as Array).append(str(ev))
		new_evidence.append(str(ev))
	return _ok({"text": obj.get("description", ""), "new_evidence": new_evidence,
		"state": state.duplicate(true)})


func _accuse(body: Dictionary) -> Dictionary:
	var suspect: String = str(body.get("suspect_id", ""))
	if ContentDB.suspect(suspect).is_empty():
		return _err("bad_request", "No existe el sospechoso %s." % suspect)
	var evidence_ids: Array = body.get("evidence_ids", [])
	for e: Variant in evidence_ids:
		if str(e) not in state["evidence"]:
			return _err("evidence_not_owned", "No tienes la evidencia %s." % e)
	var ending: String = "malo"
	if evidence_ids.size() >= 5:
		ending = "verdadero" if body.get("decision", "") == "revelar" else "gris"
	state["ended"] = true
	return _ok(fixture("ending__" + ending))


# ---------- utilidades ----------

func _npc(id: String) -> Dictionary:
	for n: Dictionary in state.get("npcs", []):
		if n["id"] == id:
			return n
	return {}


func _has_deduction(id: String) -> bool:
	for d: Dictionary in state.get("deductions", []):
		if d["id"] == id:
			return true
	return false


## JSON.parse_string devuelve números como float; el contrato usa enteros.
func _normalize_ints() -> void:
	state["act"] = int(state["act"])
	for n: Dictionary in state["npcs"]:
		n["trust"] = int(n["trust"])
		n["fear"] = int(n["fear"])


static func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data, "error": {}, "status": 200}


static func _err(error: String, detail: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": {"error": error, "detail": detail}, "status": 400}
