extends Node2D
## Pueblo de San Jacinto (Acto I). Arma el mapa desde TownLayout y los datos públicos;
## qué objetos y testigos aparecen depende del WorldState (lugares desbloqueados).
##  - E sobre un objeto: Backend.examine y muestra el texto.
##  - E sobre un testigo: abre el interrogatorio.

signal witness_selected(witness_id: String)  ## A3 abre el interrogatorio con esto

const CAMERA_ZOOM := 3.0
const NIGHT := Color(0.36, 0.34, 0.56)

var ground: TileMapLayer
var world: Node2D  ## nodos con orden por altura (y-sort)
var player: TownPlayer
var hud: Hud
var message_box: MessageBox
var pause_menu: PauseMenu
var interrogation: Interrogation

var objects: Dictionary = {}    ## object_id -> Node2D (marcador + Interactable)
var witnesses: Dictionary = {}  ## witness_id -> Node2D
var _busy: bool = false
var _known_unlocked: Array = []
var _zone: String = "-"


func _ready() -> void:
	if not GameState.has_session():
		# Abierta directo desde el editor: crea una partida para poder probar.
		await Backend.new_session()
	_build_ground()
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	_build_buildings()
	_build_bounds()
	_build_lamps()
	_spawn_witnesses()
	_spawn_objects()
	_spawn_player()
	_build_lighting()

	hud = Hud.new()
	add_child(hud)
	message_box = MessageBox.new()
	add_child(message_box)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	interrogation = Interrogation.new()
	add_child(interrogation)
	player.focus_changed.connect(_on_focus_changed)

	_known_unlocked = (GameState.world.get("unlocked_locations", []) as Array).duplicate()
	GameState.world_changed.connect(_on_world_changed)
	_on_world_changed(GameState.world)


func _process(_delta: float) -> void:
	var z: String = TownLayout.zone_at(player.global_position)
	if z != _zone:
		_zone = z
		hud.set_place(z)


# ---------- construcción ----------

func _build_ground() -> void:
	ground = TileMapLayer.new()
	ground.name = "Ground"
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(TownLayout.TILE, TownLayout.TILE)
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = load("res://assets/town/tiles.png") as Texture2D
	src.texture_region_size = Vector2i(TownLayout.TILE, TownLayout.TILE)
	for i: int in TownLayout.Tile.size():
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	ground.tile_set = ts
	add_child(ground)

	var rnd: RandomNumberGenerator = RandomNumberGenerator.new()
	rnd.seed = 1147  # 11:47
	for y: int in TownLayout.MAP_SIZE.y:
		for x: int in TownLayout.MAP_SIZE.x:
			var r: float = rnd.randf()
			var t: int = TownLayout.Tile.GRASS if r < 0.7 else TownLayout.Tile.GRASS2
			if r > 0.975:
				t = TownLayout.Tile.FLOWERS
			_set_tile(Vector2i(x, y), t)
	_fill(TownLayout.PLAZA_RECT, TownLayout.Tile.PLAZA, TownLayout.Tile.PLAZA2, rnd)
	for street: Rect2i in TownLayout.STREETS:
		_fill(street, TownLayout.Tile.COBBLE, TownLayout.Tile.COBBLE2, rnd)
	_fill(TownLayout.BANK_RECT, TownLayout.Tile.DIRT, TownLayout.Tile.DIRT, rnd)
	_fill(TownLayout.RIVER_RECT, TownLayout.Tile.WATER, TownLayout.Tile.WATER2, rnd)
	# Cempasúchil alrededor de la plaza.
	var p: Rect2i = TownLayout.PLAZA_RECT.grow(1)
	for x: int in range(p.position.x, p.end.x):
		for y: int in [p.position.y, p.end.y - 1]:
			if ground.get_cell_atlas_coords(Vector2i(x, y)).x <= TownLayout.Tile.GRASS2 and rnd.randf() < 0.5:
				_set_tile(Vector2i(x, y), TownLayout.Tile.FLOWERS)


func _fill(rect: Rect2i, a: int, b: int, rnd: RandomNumberGenerator) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			_set_tile(Vector2i(x, y), a if rnd.randf() < 0.75 else b)


func _set_tile(cell: Vector2i, tile: int) -> void:
	ground.set_cell(cell, 0, Vector2i(tile, 0))


func _build_buildings() -> void:
	for id: String in TownLayout.BUILDINGS:
		var tex: Texture2D = load("res://assets/town/facades/%s.png" % id) as Texture2D
		var origin: Vector2i = TownLayout.BUILDINGS[id]
		var size_px: Vector2 = tex.get_size()
		var body: StaticBody2D = StaticBody2D.new()
		body.name = "B_" + id
		# El nodo va en la base del edificio para que el y-sort lo ordene bien.
		body.position = Vector2(origin.x * TownLayout.TILE, origin.y * TownLayout.TILE + size_px.y)
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.offset = Vector2(0, -size_px.y)
		body.add_child(spr)
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(size_px.x - 2, size_px.y - 6)
		shape.shape = rect
		shape.position = Vector2(size_px.x / 2.0, -size_px.y / 2.0 - 3)
		body.add_child(shape)
		world.add_child(body)


func _build_bounds() -> void:
	var map_px: Vector2 = Vector2(TownLayout.MAP_SIZE * TownLayout.TILE)
	var t: float = TownLayout.TILE
	var walls: Array[Rect2] = [
		Rect2(-t, -t, map_px.x + 2 * t, t), Rect2(-t, map_px.y, map_px.x + 2 * t, t),
		Rect2(-t, 0, t, map_px.y), Rect2(map_px.x, 0, t, map_px.y),
		Rect2(Vector2(TownLayout.RIVER_RECT.position * TownLayout.TILE), Vector2(TownLayout.RIVER_RECT.size * TownLayout.TILE)),
	]
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Bounds"
	for r: Rect2 in walls:
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		shape.position = r.get_center()
		body.add_child(shape)
	add_child(body)


func _build_lamps() -> void:
	var tex: Texture2D = load("res://assets/town/props/farol.png") as Texture2D
	for cell: Vector2i in TownLayout.LAMPS:
		var lamp: Node2D = Node2D.new()
		lamp.position = TownLayout.to_world(cell)
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = tex
		spr.offset = Vector2(0, -14)
		lamp.add_child(spr)
		var light: PointLight2D = _light(Color(1.0, 0.72, 0.38), 1.9, 1.3)
		light.position = Vector2(0, -24)
		lamp.add_child(light)
		world.add_child(lamp)


func _spawn_witnesses() -> void:
	for n: Dictionary in GameState.world.get("npcs", []):
		var id: String = n["id"]
		if not TownLayout.WITNESS_SPOTS.has(id):
			continue
		var npc: StaticBody2D = StaticBody2D.new()
		npc.name = "W_" + id
		npc.position = TownLayout.to_world(TownLayout.WITNESS_SPOTS[id])
		var spr: AnimatedSprite2D = AnimatedSprite2D.new()
		spr.name = "Sprite"
		spr.sprite_frames = CharSprites.frames_for(id)
		spr.offset = Vector2(0, -12)
		spr.play("idle_down")
		npc.add_child(spr)
		var feet: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(10, 6)
		feet.shape = rect
		feet.position = Vector2(0, -3)
		npc.add_child(feet)
		var it: Interactable = Interactable.new()
		it.name = "Interactable"
		it.kind = "witness"
		it.target_id = id
		it.radius = 14.0
		it.position = Vector2(0, -6)
		npc.add_child(it)
		world.add_child(npc)
		witnesses[id] = npc


func _spawn_objects() -> void:
	var tex: Texture2D = load("res://assets/town/props/marcador.png") as Texture2D
	for loc: Dictionary in ContentDB.world.get("locations", []):
		for obj: Dictionary in loc.get("objects", []):
			var id: String = obj["id"]
			if not TownLayout.OBJECT_SPOTS.has(id):
				push_warning("Objeto sin lugar en el mapa: " + id)
				continue
			var node: Node2D = Node2D.new()
			node.name = "O_" + id
			node.position = TownLayout.to_world(TownLayout.OBJECT_SPOTS[id])
			node.set_meta("location_id", loc["id"])
			node.set_meta("act", int(loc.get("act", 1)))
			var spr: Sprite2D = Sprite2D.new()
			spr.name = "Marker"
			spr.texture = tex
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


func _spawn_player() -> void:
	player = TownPlayer.new()
	player.name = "Player"
	player.position = TownLayout.to_world(TownLayout.PLAYER_START)
	world.add_child(player)
	var cam: Camera2D = Camera2D.new()
	cam.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	cam.position = Vector2(0, -10)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = TownLayout.MAP_SIZE.x * TownLayout.TILE
	cam.limit_bottom = TownLayout.MAP_SIZE.y * TownLayout.TILE
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)
	var glow: PointLight2D = _light(Color(0.7, 0.78, 1.0), 1.0, 0.8)
	glow.position = Vector2(0, -10)
	player.add_child(glow)


func _build_lighting() -> void:
	var cm: CanvasModulate = CanvasModulate.new()
	cm.color = NIGHT
	add_child(cm)


func _light(color: Color, energy: float, scale_f: float) -> PointLight2D:
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


# ---------- interacción ----------

func _on_focus_changed(target: Interactable) -> void:
	hud.set_prompt(target.prompt() if target else "")


func _unhandled_input(event: InputEvent) -> void:
	if interrogation.is_open():
		return
	if event.is_action_pressed("pause") and not pause_menu.is_open() and not message_box.is_open():
		get_viewport().set_input_as_handled()
		pause_menu.open()
	elif event.is_action_pressed("interact") and player.focus and not _busy and not message_box.is_open():
		get_viewport().set_input_as_handled()
		interact(player.focus)


func interact(target: Interactable) -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	hud.set_prompt("")
	if target.kind == "witness":
		await _talk_to(target.target_id)
	else:
		await examine_object(target.target_id)
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
		var spr: AnimatedSprite2D = npc.get_node("Sprite") as AnimatedSprite2D
		spr.play("idle_" + CharSprites.facing(npc.global_position, player.global_position))
	witness_selected.emit(witness_id)
	hud.visible = false
	await interrogation.open(witness_id)
	hud.visible = true
	if npc:
		(npc.get_node("Sprite") as AnimatedSprite2D).play("idle_down")
