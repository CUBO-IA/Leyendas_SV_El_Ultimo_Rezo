class_name Portraits
extends RefCounted
## Retrato de un personaje por emoción, con cadena de respaldo:
## assets_generated/portraits/{id}_{emocion}.png -> {id}_neutral.png
## -> res://assets/placeholders/{id}.png -> res://assets/placeholders/_unknown.png

const EMOTIONS: Array[String] = ["neutral", "nervioso", "enojado", "asustado", "triste", "aliviado"]
const PLACEHOLDER_DIR := "res://assets/placeholders/"

static var _cache: Dictionary = {}


static func get_texture(id: String, emotion: String = "neutral") -> Texture2D:
	var key: String = "%s_%s" % [id, emotion]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var tries: Array[String] = [Paths.portrait(id, emotion)]
	if emotion != "neutral":
		tries.append(Paths.portrait(id, "neutral"))
	for path: String in tries:
		if FileAccess.file_exists(path):
			var img: Image = Image.load_from_file(path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
				break
	if tex == null:
		tex = placeholder(id)
	_cache[key] = tex
	return tex


static func placeholder(id: String) -> Texture2D:
	var path: String = PLACEHOLDER_DIR + id + ".png"
	if not ResourceLoader.exists(path):
		path = PLACEHOLDER_DIR + "_unknown.png"
	return load(path) as Texture2D


## true si el retrato viene de assets_generated (no es placeholder).
static func is_generated(id: String, emotion: String = "neutral") -> bool:
	return FileAccess.file_exists(Paths.portrait(id, emotion))


## Vacía la caché (por ejemplo, después de generar retratos nuevos con B5).
static func clear_cache() -> void:
	_cache.clear()
