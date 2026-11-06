extends Node
## Prueba automática del esqueleto. Sale con código 0 si todo pasa, 1 si algo falla.
##
##  Mock:  Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/smoke_test.tscn
##  HTTP:  ... res://tests/smoke_test.tscn -- --backend=http   (con el motor corriendo)

var _fails: int = 0
var _passes: int = 0


func _ready() -> void:
	Backend.mock_delay_s = 0.01
	print("== Smoke test (backend=%s) ==" % Backend.mode)
	_test_content()
	_test_portraits()
	_test_scenes_load()
	if Backend.mode == "mock":
		await _test_mock_flow()
	else:
		await _test_http()
	print("== %d ok, %d fallos ==" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  ok   ", what)
	else:
		_fails += 1
		printerr("  FAIL ", what)


func _test_content() -> void:
	check(ContentDB.witness_ids().size() == 10, "10 testigos en characters.json")
	check(ContentDB.witness_ids(true).size() == 6, "6 testigos MVP")
	check(ContentDB.suspect_ids().size() == 6, "6 sospechosos")
	check(ContentDB.display_name("chonita") == "Doña Chonita", "nombres con acentos (Doña Chonita)")
	check(not ContentDB.game_object("tablero_electrico").is_empty(), "objeto tablero_electrico indexado")
	check(ContentDB.game_object("tablero_electrico")["location_id"] == "puesto_policial", "objeto sabe su lugar")
	check(GameState.format_clock("23:47") == "11:47 p. m.", "reloj 23:47 -> 11:47 p. m.")
	check(GameState.format_clock("00:13") == "12:13 a. m.", "reloj 00:13 -> 12:13 a. m.")


func _test_portraits() -> void:
	var ids: Array[String] = ContentDB.witness_ids() + ContentDB.suspect_ids()
	var all_ok: bool = true
	for id: String in ids:
		for emo: String in Portraits.EMOTIONS:
			var t: Texture2D = Portraits.get_texture(id, emo)
			if t == null or t.get_width() != 512:
				all_ok = false
				printerr("    sin retrato: %s_%s" % [id, emo])
	check(all_ok, "retrato 512x512 (real o placeholder) para 16 personajes x 6 emociones")
	check(Portraits.get_texture("no_existe") != null, "retrato _unknown para ids desconocidos")


func _test_scenes_load() -> void:
	for path: String in [SceneRouter.TITLE, SceneRouter.OPTIONS, SceneRouter.TOWN]:
		var ps: PackedScene = load(path) as PackedScene
		var ok: bool = ps != null
		if ok:
			var inst: Node = ps.instantiate()
			ok = inst != null
			inst.free()
		check(ok, "escena carga: " + path)


func _test_mock_flow() -> void:
	var r: Dictionary = await Backend.health()
	check(r["ok"] and r["data"]["status"] == "ok", "health en mock")

	r = await Backend.talk("chonita", "hola")
	check(not r["ok"] and r["error"]["error"] == "session_not_found", "talk sin sesión -> session_not_found")

	r = await Backend.new_session("Prueba")
	check(r["ok"] and GameState.has_session(), "nueva sesión")
	check((GameState.world["npcs"] as Array).size() == 6, "6 NPC en la partida")
	check(GameState.act() == 1 and GameState.evidence_ids().is_empty(), "acto 1, sin evidencias")

	r = await Backend.talk("chonita", "¿Vio algo raro?")
	check(r["ok"] and str(r["data"]["reply"]).length() > 0, "talk chonita responde")
	check(bool(GameState.npc("chonita")["met"]), "chonita queda como conocida")
	check(r["data"]["level"] == "inicial", "chonita sigue en nivel inicial")

	r = await Backend.present("alcides", "registro_electrico")
	check(not r["ok"] and r["error"]["error"] == "evidence_not_owned", "presentar sin tenerla -> evidence_not_owned")

	r = await Backend.examine("tablero_electrico")
	check(r["ok"] and "registro_electrico" in r["data"]["new_evidence"], "examinar tablero da registro_electrico")
	check(GameState.has_evidence("registro_electrico"), "GameState tiene la evidencia")
	r = await Backend.examine("tablero_electrico")
	check(r["ok"] and (r["data"]["new_evidence"] as Array).is_empty(), "examinar otra vez no duplica")

	r = await Backend.examine("puerta_campanario")
	check(not r["ok"] and r["error"]["error"] == "location_locked", "campanario cerrado en acto 1")
	r = await Backend.examine("no_existe")
	check(not r["ok"] and r["error"]["error"] == "bad_object", "objeto inexistente -> bad_object")

	r = await Backend.examine("empedrado_plaza")
	r = await Backend.present("alcides", "surcos_ruedas")
	check(r["ok"] and not r["data"]["contradiction"], "surcos a Alcides: sin contradicción")
	check(GameState.npc("alcides")["level"] == "inicial", "Alcides sigue en inicial")

	r = await Backend.present("alcides", "registro_electrico")
	check(r["ok"] and r["data"]["contradiction"], "registro eléctrico a Alcides: contradicción")
	check(GameState.npc("alcides")["level"] == "confrontada", "Alcides pasa a confrontada")
	check((GameState.world["deductions"] as Array).size() == 1, "una deducción nueva")
	var d: Dictionary = GameState.world["deductions"][0]
	check(d.has("id") and d.has("text"), "deducción viaja como {id, text}")

	r = await Backend.present("alcides", "registro_electrico")
	check(r["ok"] and not r["data"]["contradiction"], "repetir la contradicción no vuelve a subir")
	check((GameState.world["deductions"] as Array).size() == 1, "no duplica la deducción")

	r = await Backend.accuse("carreta_chillona", GameState.evidence_ids(), "revelar")
	check(r["ok"] and r["data"]["ending_id"] == "malo", "acusar con pocas pruebas -> final malo")
	check(bool(GameState.world["ended"]), "la partida queda terminada")
	r = await Backend.talk("chonita", "hola")
	check(not r["ok"] and r["error"]["error"] == "session_ended", "tras el final -> session_ended")

	r = await Backend.new_session("Demo", true)
	check(r["ok"] and GameState.evidence_ids().size() == 2 and bool(GameState.world.get("demo", false)), "sesión demo con 2 evidencias")


func _test_http() -> void:
	print("  motor en ", Backend.base_url)
	var r: Dictionary = await Backend.health()
	check(r["ok"], "health responde")
	if not r["ok"]:
		printerr("    ", r["error"])
		return
	check(r["data"]["status"] in ["ok", "degraded"], "health con status válido")
	r = await Backend.new_session("Prueba HTTP")
	check(r["ok"] and GameState.has_session(), "POST /session")
	check((GameState.world["npcs"] as Array).size() == 6, "6 NPC desde el motor")
	var sid: String = GameState.session_id()
	r = await Backend.get_session()
	check(r["ok"] and r["data"]["session_id"] == sid, "GET /session/{id}")
	var saved: Dictionary = GameState.world
	GameState.world = {"session_id": "no-existe-123"}
	r = await Backend.get_session()
	check(not r["ok"] and r["error"]["error"] == "session_not_found", "sesión inexistente -> session_not_found")
	GameState.apply_state(saved)
