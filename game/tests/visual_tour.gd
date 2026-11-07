extends Node
## Recorrido visual de A4 para revisar pantallas con ventana (modo mock):
## pueblo frente a la iglesia -> interior -> diario -> acusación -> final.
##   Godot --path game res://tests/visual_tour.tscn
## Cada paso dura STEP segundos e imprime "[tour] N nombre".

const STEP := 4.0


func _ready() -> void:
	await Backend.new_session("Tour")
	await Backend.examine("tablero_electrico")
	await Backend.examine("mostrador_pupuseria")
	await Backend.examine("empedrado_plaza")
	var st: Dictionary = GameState.world.duplicate(true)
	st["act"] = 3
	st["clock"] = "00:47"
	st["can_accuse"] = true
	(st["unlocked_locations"] as Array).append_array(["cementerio", "quebrada", "iglesia", "campanario"])
	(st["evidence"] as Array).append_array(["testimonio_sotana", "bitacora_caseta"])
	st["deductions"] = [
		{"id": "d_carreta_despues", "text": "La Carreta Chillona llegó a las 11:54, después de las desapariciones. Probablemente no las causó."},
		{"id": "d_excavacion_cementerio", "text": "Esa noche varios hombres excavaban una tumba detrás del cementerio."},
	]
	GameState.apply_state(st)
	(Backend.get("_mock") as MockBackend).state = st.duplicate(true)

	GameState.town_spawn = Vector2i(32, 14)
	for arg: String in OS.get_cmdline_user_args():  # -- --spawn=15,23 para mirar otra zona
		if arg.begins_with("--spawn="):
			var xy: PackedStringArray = arg.substr(8).split(",")
			GameState.town_spawn = Vector2i(int(xy[0]), int(xy[1]))
		elif arg.begins_with("--fear="):  # -- --fear=90 para ver la viñeta del miedo
			Night.add_fear(float(arg.substr(7)))
	var town: Node = await _show(SceneRouter.TOWN, "1 pueblo frente a la iglesia")
	var inter: Interrogation = town.get("interrogation")
	inter.open("chonita")
	print("[tour] 1b interrogatorio (micrófono y sugerencias)")
	await get_tree().create_timer(STEP).timeout
	inter.close()
	town.queue_free()
	GameState.interior_id = "iglesia"
	GameState.interior_from = "town"
	var interior: Node = await _show(SceneRouter.INTERIOR, "2 interior de la iglesia")
	var journal: Journal = interior.get("journal")
	journal.open(3)
	print("[tour] 3 diario: línea de tiempo")
	await get_tree().create_timer(STEP).timeout
	journal.close()
	var acc: Accusation = interior.get("accusation")
	acc.open()
	acc.choose_suspect("padre_sin_cabeza")
	for e: String in GameState.evidence_ids():
		acc.set_evidence(e, true)
	acc.choose_decision("revelar")
	print("[tour] 4 acusación")
	await get_tree().create_timer(STEP).timeout
	interior.queue_free()
	GameState.last_ending = Paths.read_json(Paths.fixture("ending__verdadero"))
	await _show(SceneRouter.ENDING, "5 final verdadero", STEP + 4.0)
	print("[tour] fin")
	Sound.quit_clean()


func _show(path: String, label: String, secs: float = STEP) -> Node:
	var n: Node = (load(path) as PackedScene).instantiate()
	add_child(n)
	print("[tour] ", label)
	await get_tree().create_timer(secs).timeout
	return n
