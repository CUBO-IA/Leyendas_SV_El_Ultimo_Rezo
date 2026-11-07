class_name InteriorLayout
extends RefCounted
## Planos de los interiores en baldosas de 16 px. Los objetos examinables son los
## de world.json para ese lugar; aquí solo se dice dónde van.

const TILE := 16
enum Tile { STONE, STONE2, WOOD, WOOD2, CARPET, WALL, WALL_WINDOW, GRASS, GRASS2, PATH }

## Cada sala: size, piso, alfombra, utilería (sprite, baldosa, choca), velas,
## objetos, puertas (destino, texto, baldosa, sprite) y dónde aparece según de dónde viene.
## Opcionales (salas al aire libre como el cementerio): carpet_tile (baldosa del camino),
## windows (ventanas en el muro de arriba), dim (color de la noche), fog (niebla).
const ROOMS: Dictionary = {
	"iglesia": {
		"size": Vector2i(20, 14),
		"floor": Tile.STONE,
		"carpet": Rect2i(9, 3, 2, 10),
		"props": [
			["altar", Vector2i(8, 3), true],
			["banca", Vector2i(3, 6), true], ["banca", Vector2i(14, 6), true],
			["banca", Vector2i(3, 8), true], ["banca", Vector2i(14, 8), true],
			["banca", Vector2i(3, 10), true], ["banca", Vector2i(14, 10), true],
		],
		"candles": [Vector2i(6, 4), Vector2i(13, 4), Vector2i(2, 12), Vector2i(17, 12)],
		"objects": {"altar_mayor": Vector2i(10, 6), "puerta_lateral": Vector2i(18, 8)},
		"doors": [
			["town", "Salir a la plaza", Vector2i(10, 13), "puerta"],
			["campanario", "Subir al campanario", Vector2i(2, 4), "escalera"],
		],
		"spawns": {"town": Vector2i(10, 12), "campanario": Vector2i(3, 5)},
	},
	"campanario": {
		"size": Vector2i(12, 11),
		"floor": Tile.WOOD,
		"carpet": Rect2i(),
		"props": [["campana", Vector2i(4, 2), false], ["cuerda", Vector2i(5, 4), false]],
		"candles": [Vector2i(2, 9)],
		"objects": {"cuerda_campana": Vector2i(6, 6), "trampilla_campanario": Vector2i(9, 7),
			"puerta_campanario": Vector2i(2, 7)},
		"doors": [["iglesia", "Bajar a la iglesia", Vector2i(6, 10), "escalera"]],
		"spawns": {"iglesia": Vector2i(6, 9)},
	},
	# Acto II: se entra por el portón del cementerio (TownLayout.DOORS).
	"cementerio": {
		"size": Vector2i(20, 14),
		"floor": Tile.GRASS,
		"carpet": Rect2i(9, 2, 2, 11),
		"carpet_tile": Tile.PATH,
		"windows": false,
		"dim": Color(0.30, 0.33, 0.48),
		"fog": true,
		"props": [
			["mausoleo", Vector2i(2, 2), true], ["cipres", Vector2i(17, 2), true],
			["cipres", Vector2i(7, 2), true], ["tumba", Vector2i(13, 3), true],
			["lapida", Vector2i(3, 7), true], ["lapida", Vector2i(5, 7), true],
			["cruz", Vector2i(7, 7), true], ["lapida", Vector2i(12, 7), true],
			["cruz", Vector2i(14, 7), true], ["lapida", Vector2i(16, 7), true],
			["cruz", Vector2i(3, 10), true], ["lapida", Vector2i(5, 10), true],
			["lapida", Vector2i(7, 10), true], ["lapida", Vector2i(12, 10), true],
			["cruz", Vector2i(14, 10), true], ["lapida", Vector2i(16, 10), true],
			["flores", Vector2i(5, 8), false], ["flores", Vector2i(12, 11), false],
		],
		"candles": [Vector2i(6, 8), Vector2i(13, 8), Vector2i(8, 11)],
		"objects": {"tumba_sin_nombre": Vector2i(14, 5), "muro_cementerio": Vector2i(18, 4)},
		"doors": [["town", "Salir al pueblo", Vector2i(10, 13), "reja"]],
		"spawns": {"town": Vector2i(10, 12)},
	},
}


static func has_object(object_id: String) -> bool:
	for room: Dictionary in ROOMS.values():
		if (room["objects"] as Dictionary).has(object_id):
			return true
	return false


static func to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE - 2)
