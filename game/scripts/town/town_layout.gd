class_name TownLayout
extends RefCounted
## Plano de San Jacinto en baldosas de 16 px. Solo posiciones: qué hay en cada lugar
## (objetos, testigos, si está abierto) sale de world.json, characters.json y del
## WorldState del motor.

const TILE := 16
const MAP_SIZE := Vector2i(64, 46)

## Índices del atlas assets/town/tiles.png (mismo orden que TILES en make_town_art.py).
enum Tile { GRASS, GRASS2, FLOWERS, COBBLE, COBBLE2, PLAZA, PLAZA2, DIRT, WATER, WATER2, HEDGE }

## Esquina superior izquierda de cada fachada (assets/town/facades/{id}.png).
## El tamaño sale de la imagen. La puerta queda abajo al centro.
const BUILDINGS: Dictionary = {
	"cementerio": Vector2i(1, 2),
	"caseta_vigilancia": Vector2i(15, 7),
	"iglesia": Vector2i(27, 2),
	"casa_parroquial": Vector2i(39, 7),
	"pupuseria": Vector2i(12, 15),
	"puesto_policial": Vector2i(46, 15),
	"kiosco": Vector2i(30, 18),
	"terminal": Vector2i(4, 31),
	"mercado": Vector2i(13, 30),
	"casa_portillo": Vector2i(24, 32),
	"cantina": Vector2i(36, 32),
}

const PLAZA_RECT := Rect2i(22, 13, 20, 15)
const RIVER_RECT := Rect2i(57, 0, 3, 46)
const BANK_RECT := Rect2i(55, 0, 2, 46)

## Calles empedradas (x, y, ancho, alto).
const STREETS: Array[Rect2i] = [
	Rect2i(2, 28, 54, 2),    # calle principal
	Rect2i(10, 20, 12, 2),   # plaza -> pupusería
	Rect2i(42, 20, 13, 2),   # plaza -> puesto policial -> quebrada
	Rect2i(5, 10, 17, 2),    # camino del cementerio y la caseta
	Rect2i(20, 10, 2, 10),   # bajada hacia la plaza
	Rect2i(31, 12, 2, 2),    # puerta de la iglesia
	Rect2i(38, 12, 7, 1),    # frente de la casa parroquial
	Rect2i(41, 12, 2, 2),
	Rect2i(31, 28, 2, 11),   # hacia el sur
	Rect2i(22, 37, 22, 2),   # frente de Portillo y cantina
	Rect2i(3, 34, 19, 2),    # frente de terminal y mercado
	Rect2i(11, 29, 2, 6),
]

const LAMPS: Array[Vector2i] = [
	Vector2i(22, 13), Vector2i(41, 13), Vector2i(22, 27), Vector2i(41, 27),
	Vector2i(10, 22), Vector2i(54, 22), Vector2i(30, 30), Vector2i(6, 27),
	Vector2i(47, 27), Vector2i(22, 11), Vector2i(34, 39), Vector2i(14, 36),
]

const PLAYER_START := Vector2i(31, 24)

## Dónde se para cada testigo (solo aparecen los que trae la partida).
const WITNESS_SPOTS: Dictionary = {
	"chonita": Vector2i(15, 21),
	"tonito": Vector2i(25, 23),
	"ramirez": Vector2i(49, 21),
	"padre_mauricio": Vector2i(40, 13),
	"alcides": Vector2i(18, 11),
	"mercedes": Vector2i(26, 38),
	# Extras (Acto II / testigos restantes)
	"chepe": Vector2i(7, 35),
	"pilo": Vector2i(9, 36),
	"beto": Vector2i(18, 35),
	"chente": Vector2i(39, 38),
}

## Posición de cada objeto examinable de world.json.
const OBJECT_SPOTS: Dictionary = {
	"puerta_iglesia": Vector2i(30, 13),
	"suelo_plaza": Vector2i(36, 25),
	"empedrado_plaza": Vector2i(27, 26),
	"banca_lustrabotas": Vector2i(24, 22),
	"mostrador_pupuseria": Vector2i(13, 20),
	"comal": Vector2i(17, 20),
	"tablero_electrico": Vector2i(46, 20),
	"archivero_policial": Vector2i(51, 20),
	"escritorio_parroco": Vector2i(39, 12),
	"armario_archivos": Vector2i(44, 12),
	"frente_caseta": Vector2i(16, 10),
	"silla_caseta": Vector2i(14, 9),
	"album_familiar": Vector2i(24, 37),
	"altar_muertos": Vector2i(29, 37),
	"mesa_cantina": Vector2i(36, 37),
	"libreta_cantinero": Vector2i(41, 37),
	"asiento_bus": Vector2i(6, 34),
	"tablero_rutas": Vector2i(8, 34),
	"carreton_beto": Vector2i(16, 34),
	"tumba_sin_nombre": Vector2i(4, 11),
	"muro_cementerio": Vector2i(11, 11),
	"orilla_quebrada": Vector2i(56, 10),
	"piedras_quebrada": Vector2i(56, 33),
}
# Los objetos de la iglesia y el campanario están en InteriorLayout.

## Puertas del pueblo: destino -> [baldosa, texto de la pista].
const DOORS: Dictionary = {
	"iglesia": [Vector2i(32, 13), "Entrar a la iglesia"],
}

## Zonas con nombre para el HUD (la primera que contiene al jugador gana).
const ZONES: Array = [
	["iglesia", Rect2i(26, 1, 12, 12)],
	["casa_parroquial", Rect2i(38, 6, 8, 7)],
	["caseta_vigilancia", Rect2i(13, 6, 9, 6)],
	["cementerio", Rect2i(0, 1, 13, 12)],
	["pupuseria", Rect2i(10, 14, 11, 9)],
	["puesto_policial", Rect2i(43, 14, 11, 9)],
	["plaza", Rect2i(22, 13, 20, 15)],
	["terminal", Rect2i(2, 30, 9, 7)],
	["mercado", Rect2i(11, 29, 11, 8)],
	["casa_portillo", Rect2i(22, 31, 10, 9)],
	["cantina", Rect2i(34, 31, 10, 9)],
	["quebrada", Rect2i(54, 0, 10, 46)],
]


static func to_world(tile: Vector2i) -> Vector2:
	## Centro-abajo de la baldosa: ahí van los pies de personajes y objetos.
	return Vector2(tile.x * TILE + TILE / 2.0, tile.y * TILE + TILE - 2)


static func zone_at(world_pos: Vector2) -> String:
	var tile: Vector2i = Vector2i(floori(world_pos.x / TILE), floori(world_pos.y / TILE))
	for z: Array in ZONES:
		if (z[1] as Rect2i).has_point(tile):
			return z[0]
	return ""


static func act_roman(act: int) -> String:
	return ["", "I", "II", "III"][clampi(act, 0, 3)]
