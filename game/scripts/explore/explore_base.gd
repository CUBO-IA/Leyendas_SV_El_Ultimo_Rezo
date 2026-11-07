class_name ExploreBase
extends Node2D
## Base de las escenas que se recorren a pie (pueblo e interiores).
## La subclase arma su mapa en _build_map() con los ayudantes de aquí; esta base
## pone la interfaz (HUD, mensajes, pausa, interrogatorio, diario, acusación) y
## resuelve la interacción con E o clic (testigo, objeto, puerta) y Tab (diario).
## Clic en el suelo: el jugador camina hasta ahí; clic en algo: camina y lo usa.

signal witness_selected(witness_id: String)

const CAMERA_ZOOM := 3.0
const MARKER := "res://assets/town/props/marcador.png"

var world: Node2D  ## nodos con orden por altura (y-sort)
var player: TownPlayer
var hud: Hud
var message_box: MessageBox
var pause_menu: PauseMenu
var interrogation: Interrogation
var journal: Journal
var accusation: Accusation

var objects: Dictionary = {}    ## object_id -> Node2D (marcador + Interactable)
var witnesses: Dictionary = {}  ## witness_id -> Node2D
var doors: Dictionary = {}      ## destino -> Node2D

var _busy: bool = false
var _known_unlocked: Array = []
var _zone: String = "-"
var _accuse_announced: bool = false
var _known_act: int = 1
var _click_target: Interactable = null  ## a dónde va el jugador tras un clic
var _hovering: bool = false


func _ready() -> void:
	if not GameState.has_session():
		# Escena abierta directo desde el editor: crea una partida para poder probar.
		await Backend.new_session()
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	_build_map()  # la subclase agrega suelo, edificios, objetos y jugador
	add_child(world)
	move_child(world, mini(1, get_child_count() - 1))

	hud = Hud.new()
	add_child(hud)
	message_box = MessageBox.new()
	add_child(message_box)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	interrogation = Interrogation.new()
	add_child(interrogation)
	journal = Journal.new()
	add_child(journal)
	accusation = Accusation.new()
	add_child(accusation)
	player.focus_changed.connect(_on_focus_changed)
	hud.journal_pressed.connect(func() -> void:
		if not _overlay_open() and not _busy:
			open_journal())
	hud.pause_pressed.connect(func() -> void:
		if not _overlay_open() and not _busy:
			pause_menu.open())
	interrogation.journal_requested.connect(_journal_from_interrogation)

	_known_unlocked = (GameState.world.get("unlocked_locations", []) as Array).duplicate()
	_known_act = GameState.act()
	Sound.play_ambience(_ambience_kind())
	if not GameState.bell_rung:
		GameState.bell_rung = true  # la campanada de las 11:47 que abre el caso
		Sound.bell(1)
	_accuse_announced = GameState.can_accuse()
	GameState.world_changed.connect(_on_world_changed)
	_on_world_changed(GameState.world)


# ---------- para las subclases ----------

func _build_map() -> void:
	push_error("ExploreBase._build_map() sin implementar")


func _zone_at(_pos: Vector2) -> String:
	return ""


## Ambiente de la escena: "town" o "interior".
func _ambience_kind() -> String:
	return "town"


func _process(_delta: float) -> void:
	if player == null or hud == null:
		return
	var z: String = _zone_at(player.global_position)
	if z != _zone:
		_zone = z
		hud.set_place(z)
	# Llegó a lo que se clicó: lo usa. Si se detuvo sin alcanzarlo, se olvida.
	if _click_target and not _busy and not _overlay_open():
		if player.focus == _click_target:
			var t: Interactable = _click_target
			_click_target = null
			player.stop_walking()
			interact(t)
		elif not player.is_walking():
			_click_target = null
	_update_hover()


func spawn_player(at: Vector2, limits: Rect2i = Rect2i(), follow: bool = true) -> void:
	player = TownPlayer.new()
	player.name = "Player"
	player.position = at
	world.add_child(player)
	var cam: Camera2D = Camera2D.new()
	cam.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	if limits.has_area():
		cam.limit_left = limits.position.x
		cam.limit_top = limits.position.y
		cam.limit_right = limits.end.x
		cam.limit_bottom = limits.end.y
	if follow:
		cam.position = Vector2(0, -10)
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 8.0
		player.add_child(cam)
	else:
		cam.position = Vector2(limits.get_center())
		add_child(cam)
	var glow: PointLight2D = make_light(Color(0.7, 0.78, 1.0), 1.0, 0.8)
	glow.position = Vector2(0, -10)
	player.add_child(glow)


func spawn_object(id: String, location_id: String, act: int, at: Vector2) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = "O_" + id
	node.position = at
	node.set_meta("location_id", location_id)
	node.set_meta("act", act)
	var spr: Sprite2D = Sprite2D.new()
	spr.name = "Marker"
	spr.texture = load(MARKER) as Texture2D
	spr.hframes = 2
	spr.offset = Vector2(0, -8)
	node.add_child(spr)
	var pulse: Tween = spr.create_tween().set_loops()
	pulse.tween_callback(func() -> void: spr.frame = 1 - spr.frame).set_delay(0.45)
	var it: Interactable = Interactable.new()
	it.name = "Interactable"
	it.kind = "object"
	it.target_id = id
	it.position = Vector2(0, -6)
	node.add_child(it)
	world.add_child(node)
	objects[id] = node
	return node


## Puerta hacia otro lugar ("town" = el pueblo). Si el motor no ha desbloqueado
## el destino, al usarla avisa que está cerrada.
func spawn_door(to: String, label: String, at: Vector2, sprite: Texture2D = null) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = "D_" + to
	node.position = at
	if sprite:
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = sprite
		spr.offset = Vector2(0, -sprite.get_height() / 2.0)
		node.add_child(spr)
	var it: Interactable = Interactable.new()
	it.name = "Interactable"
	it.kind = "door"
	it.target_id = to
	it.label = label
	it.radius = 14.0
	it.position = Vector2(0, -6)
	node.add_child(it)
	world.add_child(node)
	doors[to] = node
	return node


func spawn_witness(id: String, at: Vector2) -> Node2D:
	var npc: StaticBody2D = StaticBody2D.new()
	npc.name = "W_" + id
	npc.position = at
	var spr: AnimatedSprite2D = AnimatedSprite2D.new()
	spr.name = "Sprite"
	spr.sprite_frames = CharSprites.frames_for(id)
	spr.offset = Vector2(0, -12)
	spr.play("idle_down")
	npc.add_child(spr)
	add_rect_collision(npc, Rect2(-5, -6, 10, 6))
	var it: Interactable = Interactable.new()
	it.name = "Interactable"
	it.kind = "witness"
	it.target_id = id
	it.radius = 14.0
	it.position = Vector2(0, -6)
	npc.add_child(it)
	world.add_child(npc)
	witnesses[id] = npc
	return npc


static func add_rect_collision(body: CollisionObject2D, rect: Rect2) -> void:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var r: RectangleShape2D = RectangleShape2D.new()
	r.size = rect.size
	shape.shape = r
	shape.position = rect.get_center()
	body.add_child(shape)


static func make_light(color: Color, energy: float, scale_f: float) -> PointLight2D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var l: PointLight2D = PointLight2D.new()
	l.texture = tex
	l.color = color
	l.energy = energy
	l.texture_scale = scale_f
	return l


func add_night(color: Color) -> void:
	var cm: CanvasModulate = CanvasModulate.new()
	cm.color = color
	add_child(cm)


# ---------- estado ----------

func _on_world_changed(_state: Dictionary) -> void:
	hud.refresh()
	var unlocked: Array = GameState.world.get("unlocked_locations", [])
	var act: int = GameState.act()
	for id: String in objects:
		var node: Node2D = objects[id]
		var open: bool = node.get_meta("location_id") in unlocked and int(node.get_meta("act")) <= act
		node.visible = open
		(node.get_node("Interactable") as Interactable).monitorable = open
		(node.get_node("Marker") as Sprite2D).modulate.a = 0.35 if GameState.examined.has(id) else 1.0
	for loc: Variant in unlocked:
		if loc not in _known_unlocked:
			hud.toast("Nuevo lugar: %s" % ContentDB.display_name(str(loc)), UiKit.VIOLET.lightened(0.3))
	_known_unlocked = unlocked.duplicate()
	if act > _known_act:
		_known_act = act
		Sound.bell(3)  # cambia el acto: el campanario vuelve a sonar
	hud.set_accuse_ready(GameState.can_accuse())
	if GameState.can_accuse() and not _accuse_announced:
		_accuse_announced = true
		hud.toast("Ya puedes acusar: abre el diario (Tab)", UiKit.ACCENT)


# ---------- interacción ----------

func _on_focus_changed(target: Interactable) -> void:
	hud.set_prompt(target.prompt() if target else "")


func _overlay_open() -> bool:
	return interrogation.is_open() or journal.is_open() or accusation.is_open() \
		or pause_menu.is_open() or message_box.is_open()


func _unhandled_input(event: InputEvent) -> void:
	if _overlay_open() or _busy:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_menu.open()
	elif event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		open_journal()
	elif event.is_action_pressed("interact") and player.focus:
		get_viewport().set_input_as_handled()
		interact(player.focus)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		click_at(get_global_mouse_position())


## Clic en el mundo: sobre un testigo, objeto o puerta camina hasta ahí y lo usa;
## en el suelo, solo camina.
func click_at(world_pos: Vector2) -> void:
	if _busy or _overlay_open():
		return
	var it: Interactable = interactable_at(world_pos)
	if it and player.focus == it:
		_click_target = null
		interact(it)
		return
	_click_target = it
	player.walk_to(it.global_position + Vector2(0, 8) if it else world_pos)


## El Interactable visible bajo un punto del mundo (o null).
func interactable_at(world_pos: Vector2) -> Interactable:
	var best: Interactable = null
	var best_d: float = INF
	for group: Dictionary in [witnesses, objects, doors]:
		for node: Node2D in group.values():
			if not node.visible:
				continue
			var it: Interactable = node.get_node_or_null("Interactable") as Interactable
			if it == null or not it.monitorable:
				continue
			# El dibujo queda por encima del punto de interacción: se mide un poco más arriba.
			var d: float = world_pos.distance_to(it.global_position + Vector2(0, -4))
			if d <= it.radius + 4.0 and d < best_d:
				best_d = d
				best = it
	return best


func _update_hover() -> void:
	var over: bool = not _overlay_open() and not _busy \
		and interactable_at(get_global_mouse_position()) != null
	if over != _hovering:
		_hovering = over
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func interact(target: Interactable) -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	hud.set_prompt("")
	match target.kind:
		"witness":
			await _talk_to(target.target_id)
		"door":
			await use_door(target.target_id)
		_:
			await examine_object(target.target_id)
	if is_inside_tree():
		player.frozen = false
		_busy = false
		_on_focus_changed(player.focus)


func examine_object(object_id: String) -> void:
	var r: Dictionary = await Backend.examine(object_id)
	var title: String = ContentDB.display_name(object_id)
	if not r["ok"]:
		await message_box.show_message(title, str(r["error"].get("detail", "No se pudo examinar.")))
		return
	GameState.examined[object_id] = true
	_on_world_changed(GameState.world)
	for ev: Variant in r["data"].get("new_evidence", []):
		hud.toast("Nueva evidencia: %s" % ContentDB.display_name(str(ev)))
	await message_box.show_message(title, str(r["data"].get("text", "")))


func _talk_to(witness_id: String) -> void:
	var npc: Node2D = witnesses.get(witness_id)
	if npc:
		(npc.get_node("Sprite") as AnimatedSprite2D).play(
			"idle_" + CharSprites.facing(npc.global_position, player.global_position))
	witness_selected.emit(witness_id)
	hud.visible = false
	await interrogation.open(witness_id)
	hud.visible = true
	if npc:
		(npc.get_node("Sprite") as AnimatedSprite2D).play("idle_down")


## Puerta: comprueba que el destino esté abierto y cambia de escena.
func use_door(to: String) -> void:
	if to != "town":
		var loc: Dictionary = ContentDB.location(to)
		if not GameState.is_unlocked(to) or int(loc.get("act", 1)) > GameState.act():
			await message_box.show_message(str(loc.get("name", to)),
				"Está cerrado. Todavía no hay razón para entrar aquí.")
			return
	_leave_to(to)


## La subclase guarda dónde reaparecer antes de salir (ver Town._leave_to).
func _leave_to(to: String) -> void:
	GameState.interior_from = _here()
	if to == "town":
		SceneRouter.go(SceneRouter.TOWN)
	else:
		GameState.interior_id = to
		SceneRouter.go(SceneRouter.INTERIOR)


func _here() -> String:
	return "town"


# ---------- diario y acusación ----------

func open_journal() -> void:
	_busy = true
	player.frozen = true
	hud.visible = false
	var wants_accuse: bool = await journal.open()
	if wants_accuse:
		await open_accusation()
	if is_inside_tree():
		hud.visible = true
		player.frozen = false
		_busy = false


## Diario abierto desde el interrogatorio (Tab o su botón): se dibuja encima. Si desde
## ahí el jugador decide acusar, se cierra el interrogatorio y se abre la acusación.
func _journal_from_interrogation() -> void:
	if journal.is_open():
		return
	var wants_accuse: bool = await journal.open()
	if wants_accuse and is_inside_tree():
		interrogation.close()
		await open_accusation()


func open_accusation() -> void:
	var ending: Dictionary = await accusation.open()
	if not ending.is_empty():
		SceneRouter.go(SceneRouter.ENDING)
