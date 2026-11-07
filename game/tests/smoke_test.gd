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
		await _test_sound()
		await _test_night()
		await _test_villagers()
		await _test_cementerio()
	else:
		await _test_http()
		await _test_full_game_http()
		await _test_voice_http()
	print("== %d ok, %d fallos ==" % [_passes, _fails])
	Sound.quit_clean(1 if _fails > 0 else 0)


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
	check((GameState.world["npcs"] as Array).size() == 10, "10 NPC en la partida (6 MVP + 4)")
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
	check(town.get("witnesses").size() == 10, "los 10 testigos en el pueblo")
	# Fachadas del equipo (facades_hd): todas cargadas a escala 1/3 y con la base del lote.
	var hd_ok: int = 0
	for id: String in TownLayout.BUILDINGS:
		var b: Node2D = town.get("world").get_node("B_" + id)
		var f: Sprite2D = b.get_node("Facade")
		var lot_h: float = (load("res://assets/town/facades/%s.png" % id) as Texture2D).get_size().y
		if f.texture.resource_path.contains("facades_hd") and is_equal_approx(f.scale.x, 1.0 / 3.0) \
				and is_equal_approx(b.position.y, TownLayout.BUILDINGS[id].y * TownLayout.TILE + lot_h):
			hd_ok += 1
	check(hd_ok == TownLayout.BUILDINGS.size(), "fachadas del equipo en los %d edificios (%d)" % [TownLayout.BUILDINGS.size(), hd_ok])
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

	# Mouse: clic en el suelo camina hasta ahí; clic en un testigo camina y lo interroga.
	var chonita_it: Interactable = (town.get("witnesses")["chonita"] as Node2D).get_node("Interactable")
	check(town.call("interactable_at", chonita_it.global_position) == chonita_it, "el clic reconoce a Chonita")
	check(town.call("interactable_at", chonita_it.global_position + Vector2(80, 80)) == null, "clic lejos: nada")
	player.position = chonita_it.global_position + Vector2(0, 60)
	await _frames(2)
	var goal: Vector2 = player.position + Vector2(20, 0)
	town.call("click_at", goal)
	await _frames(40)
	check(player.position.distance_to(goal) < 4.0 and not player.is_walking(), "clic en el suelo: camina hasta ahí")
	town.call("click_at", chonita_it.global_position)
	for i: int in 180:
		if inter.is_open():
			break
		await _frames(1)
	check(inter.is_open() and inter.witness_id == "chonita", "clic en Chonita: camina y abre el interrogatorio")

	# Desde el interrogatorio, Tab (o el botón) abre el diario encima; Tab lo cierra.
	var journal: Journal = town.get("journal")
	inter.journal_requested.emit()
	await _frames(2)
	check(journal.is_open() and inter.is_open(), "el diario se abre sobre el interrogatorio")
	await _press_journal()
	check(not journal.is_open() and inter.is_open(), "al cerrar el diario sigue el interrogatorio")
	await _press_cancel()
	check(not inter.is_open(), "Esc vuelve al pueblo otra vez")

	# Botones del HUD: Diario y Pausa también con el mouse.
	(town.get("hud") as Hud).journal_pressed.emit()
	await _frames(2)
	check(journal.is_open(), "el botón Diario del HUD abre el diario")
	await _press_journal()
	(town.get("hud") as Hud).pause_pressed.emit()
	await _frames(2)
	var pm: PauseMenu = town.get("pause_menu")
	check(pm.is_open(), "el botón Pausa del HUD abre la pausa")
	await _press_cancel()
	check(not pm.is_open() and not player.frozen, "Esc cierra la pausa")

	# Acto I: tarjeta del acto al llegar; el portón del cementerio está cerrado.
	var card: ActCard = town.get("act_card")
	check("Acto I" in card.shown_text() or GameState.act_card_seen == 1, "tarjeta del Acto I al empezar")
	check(not town.get("objects").has("tumba_sin_nombre") and town.get("doors").has("cementerio"), "el cementerio tiene portón (sus objetos están adentro)")
	check(is_zero_approx(float(town.call("_fog_density"))), "sin niebla en el Acto I")
	town.call("use_door", "cementerio")
	await _frames(2)
	var mb0: MessageBox = town.get("message_box")
	check(mb0.is_open(), "en el Acto I el portón del cementerio está cerrado")
	mb0.advance()
	mb0.advance()
	await _frames(1)

	# Al desbloquearse el acto 2, se abren cementerio y quebrada, cae la niebla y sale su tarjeta.
	var st: Dictionary = GameState.world.duplicate(true)
	st["act"] = 2
	(st["unlocked_locations"] as Array).append_array(["cementerio", "quebrada"])
	GameState.apply_state(st)
	await _frames(1)
	check((town.get("objects")["orilla_quebrada"] as Node2D).visible, "acto 2 muestra la quebrada")
	check("Acto II" in card.shown_text() and GameState.act_card_seen == 2, "tarjeta del Acto II")
	check(float(town.call("_fog_density")) > 0.2, "niebla en el pueblo desde el Acto II")
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

	# Preguntas sugeridas: 3 botones; una ya hecha no se vuelve a sugerir.
	var sugg: Array[String] = it.suggestions()
	check(sugg.size() == Interrogation.MAX_SUGGESTIONS, "3 preguntas sugeridas: %s" % [sugg])
	check("¿Vio a alguien extraño cerca de la Caseta de vigilancia?" in sugg, "sugerencia con el lugar del testigo")
	check(Interrogation._de_lugar("Mercado") == "del Mercado" and Interrogation._de_lugar("Terminal de microbuses") == "de la Terminal de microbuses", "artículo del lugar")
	var chip: Button = (it.get("_suggest_box") as HFlowContainer).get_child(0) as Button
	var first_q: String = chip.text
	chip.pressed.emit()
	await _frames(1)
	while it.get("_busy"):
		await _frames(1)
	check(("Tú: " + first_q) in it.log_text(), "un clic en la sugerencia pregunta: «%s»" % first_q)
	await _frames(2)
	check(first_q not in it.suggestions(), "la sugerencia usada ya no aparece")
	check((it.get("_mic_btn") as Button).text == "Hablar" and (it.get("_mic_btn") as Button).icon != null, "botón Hablar con ícono de micrófono")

	await it.ask("¿Qué vio desde la caseta?")
	check("Tú: ¿Qué vio desde la caseta?" in it.log_text(), "la pregunta aparece en la conversación")
	check(GameState.transcript("alcides").size() == 5, "pregunta y respuesta guardadas")
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
	check(all_conf, "los 10 testigos confiesan")
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


func _test_sound() -> void:
	print("  -- sonido y micrófono (A5)")
	for bus: String in Sound.BUSES:
		check(AudioServer.get_bus_index(bus) >= 0, "bus de audio " + bus)
	var mic: int = AudioServer.get_bus_index(Sound.MIC_BUS)
	check(mic >= 0 and AudioServer.is_bus_mute(mic), "bus del micrófono silenciado")
	var has_rec: bool = false
	for i: int in AudioServer.get_bus_effect_count(mic):
		has_rec = has_rec or AudioServer.get_bus_effect(mic, i) is AudioEffectRecord
	check(has_rec, "grabador en el bus del micrófono")
	var music: AudioStreamWAV = (Sound.get("_music") as AudioStreamPlayer).stream as AudioStreamWAV
	check(music != null and music.loop_mode == AudioStreamWAV.LOOP_FORWARD, "música en bucle")
	check(bool(ProjectSettings.get_setting("audio/driver/enable_input")), "entrada de audio habilitada")

	# Ajustes: respalda el settings.cfg real del jugador y lo restaura al final.
	var had: bool = FileAccess.file_exists(Sound.SETTINGS_PATH)
	var backup: PackedByteArray = FileAccess.get_file_as_bytes(Sound.SETTINGS_PATH) if had else PackedByteArray()
	var prev: Array = [Sound.voice_enabled, Sound.volumes.duplicate()]
	Sound.voice_enabled = false
	Sound.set_volume("Music", 0.2)
	Sound.save_settings()
	Backend.save_settings()  # no debe borrar la sección de audio
	Sound.voice_enabled = true
	Sound.set_volume("Music", 0.9)
	Sound.load_settings()
	check(not Sound.voice_enabled and is_equal_approx(float(Sound.volumes["Music"]), 0.2), "ajustes de sonido se guardan y cargan")
	if had:
		var f: FileAccess = FileAccess.open(Sound.SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Sound.SETTINGS_PATH))
	Sound.voice_enabled = prev[0]
	for b: String in Sound.BUSES:
		Sound.set_volume(b, float(prev[1][b]))

	Sound.play_voice(null)
	check(not Sound.is_voice_playing(), "sin audio_url no hay voz")

	# Detector de voz: corta tras ~1 s de silencio después de hablar; sin voz, a los 8 s.
	var vad: VoiceActivity = VoiceActivity.new()
	var verdict: String = ""
	var t: float = 0.0
	while t < 0.5:  # ruido de fondo
		verdict = vad.feed(-62.0, 1.0 / 60.0)
		t += 1.0 / 60.0
	while t < 2.0:  # habla
		verdict = vad.feed(-30.0 + randf_range(-4, 4), 1.0 / 60.0)
		t += 1.0 / 60.0
	check(vad.heard_speech and verdict == "", "el detector oye la voz y sigue escuchando")
	var end_at: float = -1.0
	while t < 5.0 and end_at < 0.0:  # silencio
		if vad.feed(-61.0, 1.0 / 60.0) == "end":
			end_at = t
		t += 1.0 / 60.0
	check(end_at > 2.9 and end_at < 3.4, "corta ~1.1 s después de callarse (%.2f s)" % (end_at - 2.0))
	var mute: VoiceActivity = VoiceActivity.new()
	var no_speech_at: float = -1.0
	for i: int in 600:
		if mute.feed(-65.0, 1.0 / 60.0) == "no_speech":
			no_speech_at = i / 60.0
			break
	check(not mute.heard_speech and absf(no_speech_at - VoiceActivity.NO_SPEECH_S) < 0.1, "sin voz se rinde a los 8 s")
	var noisy: VoiceActivity = VoiceActivity.new()
	for i: int in 120:  # ruido de fondo alto y parejo: no es voz
		noisy.feed(-40.0 + randf_range(-2, 2), 1.0 / 60.0)
	check(not noisy.heard_speech, "un ruido de fondo parejo no cuenta como voz")
	var cold: VoiceActivity = VoiceActivity.new()
	for i: int in 20:  # primeros cuadros: el medidor aún no tiene datos
		cold.feed(-80.0, 1.0 / 60.0)
	for i: int in 90:  # ruido de una laptop real
		cold.feed(-52.0 + randf_range(-6, 6), 1.0 / 60.0)
	check(not cold.heard_speech, "las lecturas vacías del inicio no descalibran el detector")
	check(Sound.mic_level_db() == -80.0, "sin grabar, el nivel del micrófono es -80 dB")

	# Interrogatorio: con «revisar antes de enviar», el texto transcrito queda en la caja.
	var prev_review: bool = Sound.mic_review
	await Backend.new_session("Microfono")
	var it: Interrogation = Interrogation.new()
	add_child(it)
	it.open("chonita")
	await _frames(2)
	Sound.mic_review = true
	await it.transcribe(_test_wav())
	var q: LineEdit = it.get("_question")
	var expected: String = str(Paths.read_json(Paths.fixture("stt_response__ejemplo"))["text"])
	check(q.text == expected and q.has_focus(), "la voz transcrita queda en la caja: «%s»" % q.text)
	# Sin revisar (lo normal): la pregunta dictada se le hace directamente al testigo.
	q.text = ""
	Sound.mic_review = false
	await it.transcribe(_test_wav())
	check(("Tú: " + expected) in it.log_text() and q.text == "", "la voz transcrita se envía sola")
	check(GameState.transcript("chonita").back()["who"] == "npc", "y el testigo responde")
	Sound.mic_review = prev_review
	it.close()
	it.queue_free()
	await _frames(1)


func _test_wav() -> PackedByteArray:
	return FileAccess.get_file_as_bytes("res://tests/assets/pregunta_plaza.wav")


## Vecinos de ambiente: aparecen, pasean y dicen frases por acto (sin motor ni IA).
func _test_villagers() -> void:
	print("  -- vecinos de ambiente")
	check(ContentDB.villagers.size() == 6, "6 vecinos en villagers.json")
	var sprites_ok: bool = true
	for v: Dictionary in ContentDB.villagers:
		sprites_ok = sprites_ok and ResourceLoader.exists("res://assets/town/chars/%s.png" % v["id"])
		for act: String in ["1", "2", "3"]:
			sprites_ok = sprites_ok and not (v["lines"][act] as Array).is_empty()
	check(sprites_ok, "cada vecino tiene sprite y frases para los 3 actos")
	await Backend.new_session("Vecinos")
	var town: Node2D = (load(SceneRouter.TOWN) as PackedScene).instantiate() as Node2D
	add_child(town)
	await _frames(3)
	var vill: Dictionary = town.get("villagers")
	check(vill.size() == 6, "los 6 vecinos en el pueblo")
	var neto: Villager = vill["cipote_neto"]
	check(town.call("interactable_at", (neto.get_node("Interactable") as Node2D).global_position) != null, "el clic reconoce a un vecino")
	var box: MessageBox = town.get("message_box")
	town.call("interact", neto.get_node("Interactable"))
	await _frames(3)
	var first: String = str(neto.data["lines"]["1"][0])
	check(box.is_open() and neto.talking, "hablar con Neto abre la caja y se queda quieto")
	box.advance()
	box.advance()
	await _frames(3)
	check(not box.is_open() and not neto.talking and int(GameState.chatter["cipote_neto"]) == 1, "la caja se cierra y Neto vuelve a pasear")
	check(neto.next_line(1, 0) == first and neto.next_line(1, 1) != first, "la siguiente vez dice otra frase")
	check(neto.next_line(2, 0) == str(neto.data["lines"]["2"][0]), "en el acto II cambian sus frases")
	town.queue_free()
	await _frames(2)


## Acto II: el cementerio como escena propia (se entra por el portón del pueblo).
func _test_cementerio() -> void:
	print("  -- acto II: el cementerio")
	await Backend.new_session("Cementerio")
	var st: Dictionary = GameState.world.duplicate(true)
	st["act"] = 2
	st["clock"] = "00:13"
	(st["unlocked_locations"] as Array).append_array(["cementerio", "quebrada"])
	GameState.apply_state(st)
	(Backend.get("_mock") as MockBackend).state = st.duplicate(true)
	GameState.interior_id = "cementerio"
	GameState.interior_from = "town"
	var room: Node2D = (load(SceneRouter.INTERIOR) as PackedScene).instantiate() as Node2D
	add_child(room)
	await _frames(10)  # da tiempo a que la escena procese y avise a Night dónde está
	var objs: Dictionary = room.get("objects")
	check(objs.has("tumba_sin_nombre") and objs.has("muro_cementerio") and (objs["tumba_sin_nombre"] as Node2D).visible, "la tumba sin nombre y el muro están en el cementerio")
	check(room.get("doors").has("town"), "la reja vuelve al pueblo")
	check(float(room.call("_fog_density")) >= 0.5 and room.call("_ambience_kind") == "town", "niebla y viento en el cementerio")
	check(Night.place == "cementerio" and (room.get("lamp_points") as Array).size() == 3, "el cementerio da miedo; sus 3 velas calman")
	check(room.get_node_or_null("World/P_mausoleo") != null or room.find_child("P_mausoleo", true, false) != null, "mausoleo, lápidas y cruces")
	room.call("examine_object", "tumba_sin_nombre")  # espera a que se cierre la caja: no se espera aquí
	await _frames(25)
	check(GameState.has_evidence("tierra_removida"), "examinar la tumba sin nombre da la tierra removida")
	var mb: MessageBox = room.get("message_box")
	mb.advance()
	mb.advance()
	await _frames(1)
	room.queue_free()
	await _frames(2)


var _bells: Array = []


## Reloj vivo, campanadas por tiempo y miedo del jugador (Night).
func _test_night() -> void:
	print("  -- la noche: reloj, campanadas y miedo")
	await Backend.new_session("Noche")
	check(Night.clock_text() == "11:47 p. m." and Night.fear == 0.0, "partida nueva: 11:47 p. m. y sin miedo")
	check(Night.to_minutes("23:47") == -13 and Night.to_minutes("00:13") == 13 and Night.from_minutes(-13) == "23:47", "minutos desde medianoche")
	_bells.clear()
	var on_bell: Callable = func(n: int, label: String) -> void: _bells.append([n, label])
	Night.bell_rang.connect(on_bell)
	Night.advance_minutes(12.5)
	check(Night.clock_text() == "11:59 p. m." and _bells.is_empty(), "el reloj avanza (11:59 p. m.) sin campanadas")
	Night.advance_minutes(1.0)
	check(_bells.size() == 1 and _bells[0][0] == 12 and "doce" in str(_bells[0][1]), "medianoche: 12 campanadas")
	check(Night.fear >= Night.FEAR_HOUR_BELL, "las campanadas dan miedo (%.0f)" % Night.fear)
	Night.advance_minutes(100.0)
	check(Night.clock_text() == "12:12 a. m.", "el acto I no pasa de las 12:12 a. m. (no adelanta la historia)")
	# Cambio de acto: el motor fija la hora y el reloj vivo vuelve a empezar.
	var st: Dictionary = GameState.world.duplicate(true)
	st["act"] = 2
	st["clock"] = "00:13"
	var before: float = Night.fear
	GameState.apply_state(st)
	check(Night.clock_text() == "12:13 a. m." and Night.fear >= before + Night.FEAR_NEW_ACT - 0.01, "acto II: 12:13 a. m. y más miedo")
	_bells.clear()
	Night.advance_minutes(2.0)
	check(_bells.size() == 1 and _bells[0][0] == 1 and "cuarto" in str(_bells[0][1]), "12:15 a. m.: suena un cuarto de hora")
	Night.bell_rang.disconnect(on_bell)
	# Miedo: sube en el cementerio, baja junto a un farol, entre 0 y 100.
	Night.fear = 30.0
	Night.place = "cementerio"
	Night.near_lamp = false
	Night.tick(10.0)
	var in_cemetery: float = Night.fear
	check(in_cemetery > 37.0, "en el cementerio el miedo sube (%.0f)" % in_cemetery)
	Night.place = "plaza"
	Night.near_lamp = true
	Night.tick(10.0)
	check(Night.fear < in_cemetery - 15.0, "junto a un farol baja (%.0f)" % Night.fear)
	Night.add_fear(500.0)
	check(Night.fear == 100.0 and Night.fear_level() == 3, "tope 100: aterrado")
	# En el pueblo: HUD con hora viva y miedo, viñeta y latido.
	await Backend.new_session("Noche 2")
	var town: Node2D = (load(SceneRouter.TOWN) as PackedScene).instantiate() as Node2D
	add_child(town)
	await _frames(3)
	var hud: Hud = town.get("hud")
	check(Night.active and "11:47 p. m." in hud.clock_label() and hud.fear_text() == "Tranquilo", "HUD: hora viva y miedo tranquilo")
	check((town.get("lamp_points") as Array).size() == TownLayout.LAMPS.size(), "los faroles calman (%d)" % TownLayout.LAMPS.size())
	Night.add_fear(85.0)
	await _frames(2)
	check(hud.fear_text() == "Aterrado" and Sound.heartbeat_playing(), "miedo alto: aterrado y se oye el latido")
	check((town.get("fear_overlay") as FearOverlay) != null, "viñeta del miedo en pantalla")
	town.queue_free()
	await _frames(2)
	check(not Night.active and not Sound.heartbeat_playing(), "al salir del pueblo la noche se detiene y el latido calla")


## Contra el motor real: la voz de un testigo suena y el micrófono se transcribe.
func _test_voice_http() -> void:
	print("  -- voz contra el motor (B4 + A5)")
	var h: Dictionary = (await Backend.health())["data"]
	if not bool(h.get("tts", false)) or not bool(h.get("stt", false)):
		print("    (el motor no tiene voz: tts=%s stt=%s)" % [h.get("tts"), h.get("stt")])
		check(false, "el motor real tiene TTS y STT")
		return
	await Backend.new_session("Voz")
	var r: Dictionary = await Backend.talk("chonita", "Buenas noches, doña.", true)
	check(r["ok"] and r["data"]["audio_url"] != null, "talk con want_audio trae audio_url")
	Sound.voice_enabled = true
	await Sound.play_voice(r["data"]["audio_url"])
	check(Sound.is_voice_playing() and Sound.voice_length() > 0.5, "la voz de Chonita suena (%.1f s)" % Sound.voice_length())
	Sound.stop_voice()
	var s: Dictionary = await Backend.stt(_test_wav())
	var heard: String = str(s["data"].get("text", "")) if s["ok"] else str(s["error"])
	print("    STT: ", heard)
	check(s["ok"] and "plaza" in heard.to_lower(), "el micrófono se transcribe por /stt")


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
	check((GameState.world["npcs"] as Array).size() == 10, "10 NPC desde el motor")
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
