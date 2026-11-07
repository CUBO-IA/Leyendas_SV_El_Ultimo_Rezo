extends Node
## Prueba automática del esqueleto. Sale con código 0 si todo pasa, 1 si algo falla.
##
##  Mock:  Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/smoke_test.tscn
##  HTTP:  ... res://tests/smoke_test.tscn -- --backend=http   (con el motor corriendo)

var _fails: int = 0
var _passes: int = 0
var _last_contradiction: String = ""


func _ready() -> void:
	Backend.mock_delay_s = 0.01
	print("== Smoke test (backend=%s) ==" % Backend.mode)
	_test_content()
	_test_portraits()
	_test_scenes_load()
	if Backend.mode == "mock":
		await _test_mock_flow()
		await _test_town()
		await _test_interrogation()
	else:
		await _test_http()
	# Deja liberar nodos y que el hilo de audio suelte los sonidos detenidos antes de salir.
	await get_tree().create_timer(0.5).timeout
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


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _test_town() -> void:
	print("  -- pueblo (A2)")
	var all_objects: Array[String] = []
	var act1_objects: Array[String] = []
	for loc: Dictionary in ContentDB.world["locations"]:
		for obj: Dictionary in loc["objects"]:
			all_objects.append(obj["id"])
			if int(loc["act"]) == 1:
				act1_objects.append(obj["id"])
	var missing: Array[String] = []
	for id: String in all_objects:
		if not TownLayout.OBJECT_SPOTS.has(id):
			missing.append(id)
	check(missing.is_empty(), "todo objeto de world.json tiene lugar en el mapa %s" % [missing])
	var no_spot: Array[String] = []
	for id: String in ContentDB.witness_ids():
		if not TownLayout.WITNESS_SPOTS.has(id):
			no_spot.append(id)
	check(no_spot.is_empty(), "los 10 testigos tienen lugar en el mapa %s" % [no_spot])
	check(TownLayout.zone_at(TownLayout.to_world(Vector2i(15, 21))) == "pupuseria", "zona: frente a la pupusería")

	await Backend.new_session("Pueblo")
	var town: Node2D = (load(SceneRouter.TOWN) as PackedScene).instantiate() as Node2D
	add_child(town)
	await _frames(3)
	check(town.get("witnesses").size() == 6, "6 testigos MVP en el pueblo")
	var visible_ids: Array[String] = []
	for id: String in town.get("objects"):
		if (town.get("objects")[id] as Node2D).visible:
			visible_ids.append(id)
	visible_ids.sort()
	act1_objects.sort()
	check(visible_ids == act1_objects, "solo se ven los objetos del Acto I (%d)" % act1_objects.size())
	check(not (town.get("objects")["cuerda_campana"] as Node2D).visible, "campanario oculto en acto 1")

	# Colisión: caminar hacia arriba contra la pupusería no la atraviesa.
	var player: TownPlayer = town.get("player")
	player.position = TownLayout.to_world(Vector2i(13, 22))
	player.input_override = Vector2.UP
	await _frames(70)
	player.input_override = Vector2.ZERO
	check(player.position.y > 20 * TownLayout.TILE - 2, "la pupusería bloquea el paso (y=%.0f)" % player.position.y)

	# Enfoque: junto al tablero eléctrico el jugador lo enfoca.
	player.position = TownLayout.to_world(Vector2i(46, 21))
	await _frames(4)
	var focus: Interactable = player.focus
	check(focus != null and focus.target_id == "tablero_electrico", "enfoca el tablero eléctrico")

	# E sobre el objeto: examina y muestra el texto.
	town.call("interact", focus)
	await _frames(25)
	var box: MessageBox = town.get("message_box")
	check(box.is_open(), "se abre la caja de mensaje")
	check(GameState.has_evidence("registro_electrico"), "examinar desde el pueblo da la evidencia")
	box.advance()
	box.advance()
	await _frames(2)
	check(not box.is_open() and not player.frozen, "la caja se cierra y el jugador vuelve a moverse")
	check(town.get("hud").toast_count() >= 1, "aviso de nueva evidencia")

	# E sobre un testigo abre el interrogatorio; Esc vuelve al pueblo.
	player.position = TownLayout.to_world(Vector2i(15, 22))
	await _frames(4)
	check(player.focus != null and player.focus.kind == "witness" and player.focus.target_id == "chonita", "enfoca a Doña Chonita")
	town.call("interact", player.focus)
	await _frames(3)
	var inter: Interrogation = town.get("interrogation")
	check(inter.is_open() and inter.witness_id == "chonita", "E abre el interrogatorio de Chonita")
	check(not (town.get("hud") as CanvasLayer).visible, "el HUD del pueblo se oculta")
	await _press_cancel()
	check(not inter.is_open() and not player.frozen, "Esc vuelve al pueblo")

	# Al desbloquearse el acto 2, aparecen cementerio y quebrada.
	var st: Dictionary = GameState.world.duplicate(true)
	st["act"] = 2
	(st["unlocked_locations"] as Array).append_array(["cementerio", "quebrada"])
	GameState.apply_state(st)
	await _frames(1)
	check((town.get("objects")["tumba_sin_nombre"] as Node2D).visible, "acto 2 muestra el cementerio")
	check(not (town.get("objects")["altar_mayor"] as Node2D).visible, "la iglesia sigue cerrada en acto 2")
	town.queue_free()
	await _frames(1)


func _press_cancel() -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)


func _on_contradiction(level: String) -> void:
	_last_contradiction = level


func _test_interrogation() -> void:
	print("  -- interrogatorio (A3)")
	await Backend.new_session("Interrogatorio")
	var it: Interrogation = Interrogation.new()
	add_child(it)
	it.contradiction_shown.connect(_on_contradiction)
	it.open("alcides")  # se queda esperando hasta cerrar; no se espera aquí
	await _frames(2)
	check(it.is_open(), "se abre el interrogatorio de Don Alcides")
	check(it.level_text() == "Declaración", "nivel inicial: Declaración")
	check(it.gauges() == Vector2i(3, 6), "barras con confianza 3 y miedo 6")
	check("Don Alcides:" in it.log_text() and "carreta" in it.log_text(), "muestra su presentación sin llamar al motor")
	check(GameState.transcript("alcides").size() == 1, "la presentación queda en la memoria del cliente")

	await it.ask("¿Qué vio desde la caseta?")
	check("Tú: ¿Qué vio desde la caseta?" in it.log_text(), "la pregunta aparece en la conversación")
	check(GameState.transcript("alcides").size() == 3, "pregunta y respuesta guardadas")
	check(bool(GameState.npc("alcides")["met"]), "Alcides queda como conocido")

	await Backend.examine("tablero_electrico")
	it.open_picker()
	check(it.get("_picker").visible and (it.get("_picker_list") as ItemList).item_count == 1, "selector con la evidencia que tengo")
	await it.present("registro_electrico")
	await _frames(2)
	check(it.level_text() == "Confrontada", "presentar el registro lo confronta")
	check(it.gauges() == Vector2i(2, 8), "barras actualizadas (2 y 8)")
	check(_last_contradiction == "confrontada", "señal de contradicción")
	check("Carreta Chillona" in it.banner_text(), "cartel con la deducción nueva")
	check(it.is_shaking(), "la pantalla se sacude")
	check(it.emotion == "asustado", "retrato con la emoción de la respuesta")

	# Respaldo si el motor tarda: el testigo dice algo y luego llega la respuesta real.
	it.wait_fallback_s = 0.05
	Backend.mock_delay_s = 0.3
	await it.ask("¿Y luego?")
	Backend.mock_delay_s = 0.01
	var fallback_seen: bool = false
	for line: String in Interrogation.FALLBACK_LINES:
		if line in it.log_text():
			fallback_seen = true
	check(fallback_seen, "frase de respaldo mientras espera")
	check(GameState.transcript("alcides").back()["who"] == "npc", "la respuesta real llega después")

	await _press_cancel()  # cierra el cartel
	await _press_cancel()  # cierra el interrogatorio
	check(not it.is_open(), "Esc cierra el interrogatorio")
	it.queue_free()
	await _frames(1)


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

	# B3: interrogatorio contra el motor real (el texto lo redacta el LLM).
	r = await Backend.talk("chonita", "Buenas noches, doña. ¿Vio algo raro?")
	check(r["ok"] and str(r["data"].get("reply", "")) != "", "POST /talk responde")
	if r["ok"]:
		print("    Chonita (%s, %s): %s" % [r["data"]["emotion"], r["data"]["source"], r["data"]["reply"]])
	check(bool(GameState.npc("chonita").get("met", false)), "GameState se actualiza con state de /talk")
	r = await Backend.examine("tablero_electrico")
	check(r["ok"] and GameState.has_evidence("registro_electrico"), "POST /examine da registro_electrico")
	r = await Backend.present("alcides", "registro_electrico")
	check(r["ok"] and bool(r["data"]["contradiction"]), "POST /present quiebra a Alcides")
	check(GameState.npc("alcides").get("level", "") == "confrontada", "Alcides queda confrontada")
	if r["ok"]:
		print("    Alcides (%s): %s" % [r["data"]["emotion"], r["data"]["reply"]])
	r = await Backend.accuse("cipitio", [], "revelar")
	check(not r["ok"] and r["error"]["error"] == "cannot_accuse", "POST /accuse en acto 1 -> cannot_accuse")

	# Unión 1 por la interfaz: interrogatorio contra el motor real.
	await Backend.new_session("Union 1")
	await Backend.examine("tablero_electrico")
	var it: Interrogation = Interrogation.new()
	add_child(it)
	it.open("chonita")
	await _frames(2)
	await it.ask("Buenas noches, doña. ¿A qué hora cerró la pupusería?")
	var last: Dictionary = GameState.transcript("chonita").back()
	check(last["who"] == "npc" and str(last["text"]).length() > 10, "Chonita contesta en la interfaz")
	print("    Chonita: ", last["text"])
	it.close()
	it.open("alcides")
	await _frames(2)
	await it.present("registro_electrico")
	await _frames(2)
	check(it.level_text() == "Confrontada" and "Carreta" in it.banner_text(), "Alcides se quiebra en la interfaz")
	print("    Alcides (%s): %s" % [it.emotion, GameState.transcript("alcides").back()["text"]])
	it.close()
	it.queue_free()
	await _frames(2)
