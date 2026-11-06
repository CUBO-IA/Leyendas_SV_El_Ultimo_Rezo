class_name CharSprites
extends RefCounted
## SpriteFrames desde una hoja de assets/town/chars/{id}.png:
## 12 cuadros de 16x24 = 4 direcciones (down, up, left, right) x 3 (quieto, paso 1, paso 2).

const FRAME := Vector2i(16, 24)
const DIRS: Array[String] = ["down", "up", "left", "right"]
const DIR_PATH := "res://assets/town/chars/"

static var _cache: Dictionary = {}


static func frames_for(id: String) -> SpriteFrames:
	if _cache.has(id):
		return _cache[id]
	var path: String = DIR_PATH + id + ".png"
	if not ResourceLoader.exists(path):
		path = DIR_PATH + "player.png"
	var sheet: Texture2D = load(path) as Texture2D
	var sf: SpriteFrames = SpriteFrames.new()
	sf.remove_animation("default")
	for d: int in DIRS.size():
		var idle: String = "idle_" + DIRS[d]
		var walk: String = "walk_" + DIRS[d]
		sf.add_animation(idle)
		sf.add_animation(walk)
		sf.set_animation_speed(walk, 8.0)
		sf.add_frame(idle, _frame(sheet, d * 3))
		for step: int in [1, 0, 2, 0]:
			sf.add_frame(walk, _frame(sheet, d * 3 + step))
	_cache[id] = sf
	return sf


static func _frame(sheet: Texture2D, index: int) -> AtlasTexture:
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(index * FRAME.x, 0, FRAME.x, FRAME.y)
	return at


## Dirección ("down", "up", "left", "right") que mira de `from` hacia `to`.
static func facing(from: Vector2, to: Vector2) -> String:
	var v: Vector2 = to - from
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0 else "left"
	return "down" if v.y > 0 else "up"
