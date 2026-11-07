extends Node
## La noche que corre: reloj vivo, campanadas por tiempo y miedo del jugador.
## Todo es del cliente (no cambia el contrato): el motor fija la hora de cada acto y
## aquí solo se cuentan los minutos que pasan mientras se explora o interroga, sin
## llegar nunca a la hora del acto siguiente.
##
##  - Reloj: 1 minuto de juego cada SECONDS_PER_MINUTE segundos reales.
##  - Campanadas: una en cada cuarto de hora; a la hora en punto, tantas como la hora
##    (las doce a medianoche).
##  - Miedo (0-100): sube con el tiempo, las campanadas y los lugares de muertos;
##    baja junto a un farol o dentro de la iglesia. Es ambiente: no castiga.
## ExploreBase activa la noche (active) y le dice dónde está el jugador (place).

signal clock_changed(text: String)
signal bell_rang(strikes: int, label: String)
signal fear_changed(value: float)

const SECONDS_PER_MINUTE := 12.0
## Hora máxima de cada acto (un minuto antes del siguiente; el acto 3 es el último).
const ACT_CAP: Dictionary = {1: "00:12", 2: "00:46", 3: "01:30"}
const FEAR_PER_SECOND := 0.12      ## el paso del tiempo
const FEAR_DANGER_PER_SECOND := 0.7  ## en el cementerio, la quebrada o el campanario
const CALM_LAMP_PER_SECOND := 2.2  ## junto a un farol
const CALM_SAFE_PER_SECOND := 1.0  ## dentro de la iglesia
const FEAR_HOUR_BELL := 8.0
const FEAR_QUARTER_BELL := 3.0
const FEAR_NEW_ACT := 10.0
const DANGER_PLACES: Array[String] = ["cementerio", "quebrada", "campanario"]
const SAFE_PLACES: Array[String] = ["iglesia"]

var active: bool = false
var minutes: float = 0.0  ## minutos de juego desde que empezó el acto actual
var fear: float = 0.0
var place: String = ""  ## zona o interior donde está el jugador
var near_lamp: bool = false

var _act: int = 0
var _session: String = ""
var _last_minute: int = 0
var _emitted_fear: float = -1.0


func _ready() -> void:
	GameState.world_changed.connect(_on_world_changed)


func reset() -> void:
	minutes = 0.0
	fear = 0.0
	place = ""
	near_lamp = false
	_act = 0
	_last_minute = 0
	_emitted_fear = -1.0


func _on_world_changed(state: Dictionary) -> void:
	var sid: String = str(state.get("session_id", ""))
	if sid != _session:
		_session = sid
		reset()
	var a: int = int(state.get("act", 1))
	if a != _act:
		if _act != 0:
			add_fear(FEAR_NEW_ACT)  # cambia el acto: la noche se pone peor
		_act = a
		minutes = 0.0
		_last_minute = now_minutes()
		clock_changed.emit(clock_text())


# ---------- reloj ----------

## Minutos desde la medianoche (23:47 -> -13; 00:13 -> 13).
static func to_minutes(hhmm: String) -> int:
	var p: PackedStringArray = hhmm.split(":")
	if p.size() != 2:
		return 0
	var m: int = int(p[0]) * 60 + int(p[1])
	return m - 24 * 60 if int(p[0]) >= 12 else m


static func from_minutes(m: int) -> String:
	var day: int = posmod(m, 24 * 60)
	return "%02d:%02d" % [floori(day / 60.0), day % 60]


func now_minutes() -> int:
	var base: int = to_minutes(str(GameState.world.get("clock", "23:47")))
	var cap: int = maxi(base, to_minutes(str(ACT_CAP.get(GameState.act(), "01:30"))))
	return mini(base + floori(minutes), cap)


func clock_text() -> String:
	return GameState.format_clock(from_minutes(now_minutes()))


func _process(delta: float) -> void:
	if not active or not GameState.has_session() or bool(GameState.world.get("ended", false)):
		return
	tick(delta)


## Avanza la noche delta segundos reales (separado de _process para las pruebas).
func tick(delta: float) -> void:
	advance_minutes(delta / SECONDS_PER_MINUTE)
	var rate: float = FEAR_PER_SECOND
	if place in DANGER_PLACES:
		rate += FEAR_DANGER_PER_SECOND
	if near_lamp:
		rate -= CALM_LAMP_PER_SECOND
	elif place in SAFE_PLACES:
		rate -= CALM_SAFE_PER_SECOND
	add_fear(rate * delta)


func advance_minutes(game_minutes: float) -> void:
	minutes += game_minutes
	var now: int = now_minutes()
	if now == _last_minute:
		return
	for m: int in range(_last_minute + 1, now + 1):
		if posmod(m, 60) == 0:
			var hour: int = posmod(floori(m / 60.0), 12)
			var strikes: int = 12 if hour == 0 else hour
			var label: String = "Medianoche: la campana da las doce" if strikes == 12 \
				else "La campana da la una" if strikes == 1 else "La campana da las %d" % strikes
			add_fear(FEAR_HOUR_BELL)
			bell_rang.emit(strikes, label)
		elif posmod(m, 15) == 0:
			add_fear(FEAR_QUARTER_BELL)
			bell_rang.emit(1, "Suena un cuarto de hora")
	_last_minute = now
	clock_changed.emit(clock_text())


# ---------- miedo ----------

func add_fear(amount: float) -> void:
	fear = clampf(fear + amount, 0.0, 100.0)
	if absf(fear - _emitted_fear) >= 0.5 or (fear in [0.0, 100.0] and fear != _emitted_fear):
		_emitted_fear = fear
		fear_changed.emit(fear)


## 0 tranquilo · 1 inquieto (>=35) · 2 asustado (>=60) · 3 aterrado (>=80)
func fear_level() -> int:
	return 3 if fear >= 80.0 else 2 if fear >= 60.0 else 1 if fear >= 35.0 else 0
