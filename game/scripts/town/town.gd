extends ExploreBase
## Pueblo de San Jacinto. Arma el mapa desde TownLayout y los datos públicos;
## qué objetos aparecen depende del WorldState (lugares desbloqueados).
## La interfaz y la interacción (E, Tab, Esc) vienen de ExploreBase.

const NIGHT := Color(0.36, 0.34, 0.56)

var ground: TileMapLayer


func _build_map() -> void:
	_build_ground()
	_build_buildings()
	_build_bounds()
	_build_lamps()
	for n: Dictionary in GameState.world.get("npcs", []):
		if TownLayout.WITNESS_SPOTS.has(n["id"]):
			spawn_witness(n["id"], TownLayout.to_world(TownLayout.WITNESS_SPOTS[n["id"]]))
	for loc: Dictionary in ContentDB.world.get("locations", []):
		for obj: Dictionary in loc.get("objects", []):
			if TownLayout.OBJECT_SPOTS.has(obj["id"]):
				spawn_object(obj["id"], loc["id"], int(loc.get("act", 1)),
					TownLayout.to_world(TownLayout.OBJECT_SPOTS[obj["id"]]))
			elif not InteriorLayout.has_object(obj["id"]):
				push_warning("Objeto sin lugar en el mapa: " + obj["id"])
	for to: String in TownLayout.DOORS:
		var d: Array = TownLayout.DOORS[to]
		spawn_door(to, d[1], TownLayout.to_world(d[0]))
	var start: Vector2i = TownLayout.PLAYER_START
	if GameState.town_spawn != Vector2i(-1, -1):
		start = GameState.town_spawn
	spawn_player(TownLayout.to_world(start),
		Rect2i(Vector2i.ZERO, TownLayout.MAP_SIZE * TownLayout.TILE))
	add_night(NIGHT)


func _zone_at(pos: Vector2) -> String:
	return TownLayout.zone_at(pos)


func _leave_to(to: String) -> void:
	# Al volver, reaparece en la baldosa frente a la puerta por la que salió.
	if TownLayout.DOORS.has(to):
		GameState.town_spawn = (TownLayout.DOORS[to][0] as Vector2i) + Vector2i(0, 1)
	super._leave_to(to)


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


## Fachadas del equipo (tools/import_facades.py): textura a HD x el tamaño del lote,
## dibujada a escala 1/HD para verse 1:1 en pantalla con el zoom x3 de la cámara.
const FACADE_HD := "res://assets/town/facades_hd/%s.png"
const HD := 3.0


func _build_buildings() -> void:
	for id: String in TownLayout.BUILDINGS:
		# El lote (ancho y línea de la base) lo define la fachada procedural de siempre;
		# así puertas, objetos y testigos quedan donde estaban.
		var lot: Vector2 = (load("res://assets/town/facades/%s.png" % id) as Texture2D).get_size()
		var origin: Vector2i = TownLayout.BUILDINGS[id]
		var base_y: float = origin.y * TownLayout.TILE + lot.y
		var tex: Texture2D = load("res://assets/town/facades/%s.png" % id) as Texture2D
		var scale_f: float = 1.0
		if ResourceLoader.exists(FACADE_HD % id):
			tex = load(FACADE_HD % id) as Texture2D
			scale_f = 1.0 / HD
		var size_px: Vector2 = tex.get_size() * scale_f
		var body: StaticBody2D = StaticBody2D.new()
		body.name = "B_" + id
		# El nodo va en la base del edificio para que el y-sort lo ordene bien.
		body.position = Vector2(origin.x * TownLayout.TILE, base_y)
		var spr: Sprite2D = Sprite2D.new()
		spr.name = "Facade"
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(scale_f, scale_f)
		spr.offset = Vector2(0, -tex.get_size().y)
		body.add_child(spr)
		add_rect_collision(body, Rect2(1, -size_px.y, size_px.x - 2, size_px.y - 6))
		world.add_child(body)


func _build_bounds() -> void:
	var map_px: Vector2 = Vector2(TownLayout.MAP_SIZE * TownLayout.TILE)
	var t: float = TownLayout.TILE
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Bounds"
	for r: Rect2 in [
		Rect2(-t, -t, map_px.x + 2 * t, t), Rect2(-t, map_px.y, map_px.x + 2 * t, t),
		Rect2(-t, 0, t, map_px.y), Rect2(map_px.x, 0, t, map_px.y),
		Rect2(Vector2(TownLayout.RIVER_RECT.position * TownLayout.TILE), Vector2(TownLayout.RIVER_RECT.size * TownLayout.TILE)),
	]:
		add_rect_collision(body, r)
	add_child(body)


func _build_lamps() -> void:
	var tex: Texture2D = load("res://assets/town/props/farol.png") as Texture2D
	for cell: Vector2i in TownLayout.LAMPS:
		var lamp: Node2D = Node2D.new()
		lamp.position = TownLayout.to_world(cell)
		lamp_points.append(lamp.position)  # junto a un farol, el miedo baja
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = tex
		spr.offset = Vector2(0, -14)
		lamp.add_child(spr)
		var light: PointLight2D = make_light(Color(1.0, 0.72, 0.38), 1.9, 1.3)
		light.position = Vector2(0, -24)
		lamp.add_child(light)
		world.add_child(lamp)
