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
		await _test_a4()
	else:
		await _test_http()
		await _test_full_game_http()
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
	if FileAccess.file_exists(Paths.content("generated/characters_public.json")):
		var prof: Dictionary = ContentDB.profile("chonita")
		check(prof.has("full_name") and prof.has("bio"), "lee el perfil público de B2 (%s)" % prof.get("full_name", "?"))
		check(ContentDB.role_line("chonita").ends_with("años"), "rol con edad: " + ContentDB.role_line("chonita"))


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
		if not TownLayout.OBJECT_SPOTS.has(id) and not InteriorLayout.has_object(id):
			missing.append(id)
	check(missing.is_empty(), "todo objeto de world.json tiene lugar (pueblo o interior) %s" % [missing])
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
	check(town.get("doors").has("iglesia"), "la iglesia tiene puerta en el pueblo")

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
	check(not GameState.is_unlocked("iglesia"), "la iglesia sigue cerrada en acto 2")
	town.call("use_door", "iglesia")
	await _frames(2)
	var mb: MessageBox = town.get("message_box")
	check(mb.is_open(), "la puerta cerrada avisa que está cerrado")
	mb.advance()
	mb.advance()
	await _frames(1)
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


## Estado de acto 3 inyectado (el mock no avanza actos solo).
func _act3_state(evidence: Array) -> void:
	var st: Dictionary = GameState.world.duplicate(true)
	st["act"] = 3
	st["clock"] = "00:47"
	st["can_accuse"] = true
	(st["unlocked_locations"] as Array).append_array(["cementerio", "quebrada", "iglesia", "campanario"])
	st["evidence"] = evidence
	st["deductions"] = [{"id": "d_carreta_despues", "text": "La Carreta Chillona llegó a las 11:54, después de las desapariciones."}]
	GameState.apply_state(st)
	if Backend.mode == "mock":
		(Backend.get("_mock") as MockBackend).state = st.duplicate(true)  # el mock guarda su propio estado


func _test_a4() -> void:
	print("  -- diario, interiores, acusación y finales (A4)")
	await Backend.new_session("A4")
	var journal: Journal = Journal.new()
	add_child(journal)
	await _frames(1)
	journal.refresh()
	check(journal.timeline_entries().is_empty(), "línea de tiempo vacía sin evidencias")
	check(journal.get("_accuse_btn").disabled, "no se puede acusar en acto 1")

	await Backend.examine("tablero_electrico")  # 11:47 y 11:54
	await Backend.examine("mostrador_pupuseria")  # 11:20
	journal.refresh()
	var times: Array[String] = []
	for e: Dictionary in journal.timeline_entries():
		times.append(str(e["time"]))
	check(times == ["11:20", "11:47", "11:54"], "línea de tiempo ordenada %s" % [times])
	check((journal.get("_ev_list") as ItemList).item_count == 2, "pestaña Evidencias con 2")
	journal.open(2)
	await _frames(1)
	check(journal.is_open(), "Tab abre el diario")
	await _press_journal()
	check(not journal.is_open(), "Tab lo cierra")

	_act3_state(["registro_electrico", "cuaderno_ventas", "surcos_ruedas"])
	journal.refresh()
	check(not journal.get("_accuse_btn").disabled, "en acto 3 se puede acusar")
	var t2: Array[String] = []
	for e: Dictionary in journal.timeline_entries():
		t2.append(str(e["time"]))
	check("11:54" in t2 and t2.count("11:54") == 2, "las deducciones también entran a la línea de tiempo")
	journal.queue_free()

	# Interior: la iglesia en acto 3.
	GameState.interior_id = "iglesia"
	GameState.interior_from = "town"
	var interior: Node2D = (load(SceneRouter.INTERIOR) as PackedScene).instantiate() as Node2D
	add_child(interior)
	await _frames(3)
	var objs: Dictionary = interior.get("objects")
	check(objs.has("altar_mayor") and (objs["altar_mayor"] as Node2D).visible, "altar mayor dentro de la iglesia")
	check(interior.get("doors").has("town") and interior.get("doors").has("campanario"), "puertas a la plaza y al campanario")
	var ip: TownPlayer = interior.get("player")
	check(ip.position.distance_to(InteriorLayout.to_world(Vector2i(10, 12))) < 1.0, "entra junto a la puerta de la plaza")
	interior.call("examine_object", "altar_mayor")
	await _frames(25)
	var imb: MessageBox = interior.get("message_box")
	check(imb.is_open() and not GameState.has_evidence("campana_funeraria"), "el altar no da nada sin la deducción")
	imb.advance()
	imb.advance()
	interior.queue_free()
	await _frames(2)
	GameState.interior_id = "campanario"
	GameState.interior_from = "iglesia"
	var bell: Node2D = (load(SceneRouter.INTERIOR) as PackedScene).instantiate() as Node2D
	add_child(bell)
	await _frames(3)
	check((bell.get("objects") as Dictionary).has("cuerda_campana"), "cuerda de la campana en el campanario")
	bell.queue_free()
	await _frames(2)

	# Acusación: tope de 10 pruebas, y el final llega a GameState.
	var many: Array = ["registro_electrico", "cuaderno_ventas", "surcos_ruedas", "mensaje_ceniza",
		"huellas_invertidas", "liston_cruz", "llave_armario", "recorte_periodico", "bitacora_caseta",
		"testimonio_sotana", "medalla_nina", "diario_esteban"]
	_act3_state(many)
	var acc: Accusation = Accusation.new()
	add_child(acc)
	await _frames(1)
	acc.open()
	await _frames(1)
	check(acc.get("_confirm").disabled, "sin sospechoso ni decisión no se puede acusar")
	for id: String in many:
		acc.set_evidence(id, true)
	check(acc.selected_evidence().size() == 10, "máximo 10 pruebas (%d)" % acc.selected_evidence().size())
	acc.choose_suspect("cadejo")
	acc.choose_decision("revelar")
	check(not acc.get("_confirm").disabled, "con sospechoso y decisión se habilita Acusar")
	await acc.confirm()
	check(not GameState.last_ending.is_empty() and bool(GameState.world["ended"]), "el final queda en GameState")
	check(GameState.last_ending["ending_id"] == "verdadero", "mock: 10 pruebas + revelar -> verdadero")
	acc.queue_free()

	var ending: Control = (load(SceneRouter.ENDING) as PackedScene).instantiate() as Control
	add_child(ending)
	await _frames(2)
	var labels: Array[String] = []
	for l: Node in ending.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	check(str(GameState.last_ending["title"]) in labels, "la escena del final muestra su título")
	var has_bg: bool = false
	for tr: Node in ending.find_children("*", "TextureRect", true, false):
		has_bg = has_bg or (tr as TextureRect).texture != null
	check(has_bg, "la escena del final tiene fondo")
	ending.queue_free()
	await _frames(1)


## Unión 2: partida completa contra el motor real, por la API y la pantalla de acusación.
## SOLO PRUEBA: lee la solución de server/data para jugar como alguien que ya sabe
## qué presentar (el juego nunca lee ese archivo).
func _test_full_game_http() -> void:
	print("  -- Unión 2: partida completa contra el motor")
	var secret: Dictionary = Paths.read_json(Paths.repo_root().path_join("server/data/case_secret.json"))
	var t0: int = Time.get_ticks_msec()
	await Backend.new_session("Union 2")
	var presents: int = 0
	for round_i: int in 12:
		var before: String = "%d/%d/%d" % [GameState.act(), GameState.evidence_ids().size(),
			(GameState.world["deductions"] as Array).size()]
		for loc: Dictionary in ContentDB.world["locations"]:
			if not GameState.is_unlocked(loc["id"]) or int(loc["act"]) > GameState.act():
				continue
			for obj: Dictionary in loc["objects"]:
				await Backend.examine(obj["id"])
		for n: Dictionary in GameState.world["npcs"]:
			var w: Dictionary = secret["witnesses"][n["id"]]
			var wanted: Array = w["contradicted_by"] if n["level"] == "inicial" else 				(w["confession"]["by_evidence"] if n["level"] == "confrontada" else [])
			for ev: Variant in wanted:
				if GameState.has_evidence(str(ev)):
					var r: Dictionary = await Backend.present(n["id"], str(ev))
					presents += 1
					if not r["ok"]:
						printerr("    present falló: ", r["error"])
					break
		var after: String = "%d/%d/%d" % [GameState.act(), GameState.evidence_ids().size(),
			(GameState.world["deductions"] as Array).size()]
		if after == before:
			break
	print("    %d presentaciones con LLM en %.1f s" % [presents, (Time.get_ticks_msec() - t0) / 1000.0])
	check(GameState.act() == 3 and GameState.clock_text() == "12:47 a. m.", "se llega al Acto III (12:47 a. m.)")
	check(GameState.can_accuse(), "el motor habilita la acusación")
	var all_conf: bool = true
	for n: Dictionary in GameState.world["npcs"]:
		all_conf = all_conf and n["level"] == "confesion"
	check(all_conf, "los 6 testigos confiesan")
	var proofs: Array[String] = []
	for p: Dictionary in secret["solution"]["proofs"]:
		proofs.append(str(p["evidence_id"]))
	var missing: Array[String] = []
	for p: String in proofs:
		if not GameState.has_evidence(p):
			missing.append(p)
	check(missing.is_empty(), "todas las pruebas de la solución se consiguen %s" % [missing])

	var journal: Journal = Journal.new()
	add_child(journal)
	await _frames(1)
	journal.refresh()
	check(journal.timeline_entries().size() >= 5, "línea de tiempo con %d horas" % journal.timeline_entries().size())
	journal.queue_free()

	var acc: Accusation = Accusation.new()
	add_child(acc)
	await _frames(1)
	acc.open()
	await _frames(1)
	acc.choose_suspect(str(secret["solution"]["culprit"]))
	for p: String in proofs:
		acc.set_evidence(p, true)
	acc.choose_decision("revelar")
	await acc.confirm()
	check(GameState.last_ending.get("ending_id", "") == "verdadero", "final verdadero contra el motor real")
	print("    Final: %s — %s" % [GameState.last_ending.get("title", "?"), GameState.last_ending.get("text", "")])
	acc.queue_free()
	await _frames(2)


func _press_journal() -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "journal"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)


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
