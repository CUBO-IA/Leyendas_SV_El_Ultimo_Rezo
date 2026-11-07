extends ExploreBase
## Interior (iglesia o campanario) según GameState.interior_id. La sala cabe en la
## pantalla, así que la cámara queda fija en su centro.

const DIM := Color(0.42, 0.38, 0.52)
const PROPS := "res://assets/interior/props/%s.png"

var room_id: String = "iglesia"
var ground: TileMapLayer


func _build_map() -> void:
	if InteriorLayout.ROOMS.has(GameState.interior_id):
		room_id = GameState.interior_id
	var room: Dictionary = InteriorLayout.ROOMS[room_id]
	var size: Vector2i = room["size"]
	_build_floor(room, size)
	_build_walls(size)

	for p: Array in room["props"]:
		_prop(p[0], p[1], p[2])
	for c: Vector2i in room["candles"]:
		var candle: Node2D = Node2D.new()
		candle.position = InteriorLayout.to_world(c)
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = load(PROPS % "vela") as Texture2D
		spr.offset = Vector2(0, -7)
		candle.add_child(spr)
		var light: PointLight2D = make_light(Color(1.0, 0.7, 0.35), 1.6, 0.9)
		light.position = Vector2(0, -12)
		candle.add_child(light)
		world.add_child(candle)

	var act: int = int(ContentDB.location(room_id).get("act", 3))
	for id: String in room["objects"]:
		spawn_object(id, room_id, act, InteriorLayout.to_world(room["objects"][id]))
	for d: Array in room["doors"]:
		spawn_door(d[0], d[1], InteriorLayout.to_world(d[2]), load(PROPS % d[3]) as Texture2D)

	var spawns: Dictionary = room["spawns"]
	var spawn: Vector2i = spawns.get(GameState.interior_from, spawns.values()[0])
	spawn_player(InteriorLayout.to_world(spawn), Rect2i(Vector2i.ZERO, size * InteriorLayout.TILE), false)
	add_night(DIM)


func _zone_at(_pos: Vector2) -> String:
	return room_id


func _here() -> String:
	return room_id


func _build_floor(room: Dictionary, size: Vector2i) -> void:
	ground = TileMapLayer.new()
	ground.name = "Ground"
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(InteriorLayout.TILE, InteriorLayout.TILE)
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = load("res://assets/interior/tiles.png") as Texture2D
	src.texture_region_size = Vector2i(InteriorLayout.TILE, InteriorLayout.TILE)
	for i: int in InteriorLayout.Tile.size():
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	ground.tile_set = ts
	add_child(ground)
	var base: int = room["floor"]
	var carpet: Rect2i = room["carpet"]
	for y: int in size.y:
		for x: int in size.x:
			var cell: Vector2i = Vector2i(x, y)
			var t: int = base + (1 if (x * 7 + y * 3) % 5 == 0 else 0)  # variante 2 a veces
			if y < 2:
				t = InteriorLayout.Tile.WALL_WINDOW if x % 4 == 2 else InteriorLayout.Tile.WALL
			elif x == 0 or x == size.x - 1 or y == size.y - 1:
				t = InteriorLayout.Tile.WALL
			elif carpet.has_area() and carpet.has_point(cell):
				t = InteriorLayout.Tile.CARPET
			ground.set_cell(cell, 0, Vector2i(t, 0))


func _build_walls(size: Vector2i) -> void:
	var t: float = InteriorLayout.TILE
	var w: float = size.x * t
	var h: float = size.y * t
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Walls"
	add_rect_collision(body, Rect2(0, 0, w, 2 * t))           # muro de arriba
	add_rect_collision(body, Rect2(0, 0, t, h))               # izquierda
	add_rect_collision(body, Rect2(w - t, 0, t, h))           # derecha
	add_rect_collision(body, Rect2(0, h - t + 6, w, t))       # abajo (deja ver la puerta)
	add_child(body)


func _prop(sprite: String, cell: Vector2i, solid: bool) -> void:
	var tex: Texture2D = load(PROPS % sprite) as Texture2D
	var size_px: Vector2 = tex.get_size()
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "P_" + sprite
	body.position = Vector2(cell.x * InteriorLayout.TILE, cell.y * InteriorLayout.TILE + size_px.y)
	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.offset = Vector2(0, -size_px.y)
	body.add_child(spr)
	if solid:
		add_rect_collision(body, Rect2(0, -size_px.y * 0.6, size_px.x, size_px.y * 0.6))
	world.add_child(body)
