extends Node
## Partidas compartidas (experimental): varios jugadores se unen a la MISMA partida
## ("Unirse a una partida" en el título) y se ven moverse por el mapa. Por aquí viaja dónde
## está cada quien; cuando alguien cambia la partida (examina, presenta, habla), el motor
## avisa y esta partida se vuelve a leer; si alguien acusa, llega el final para todos.
## Ver server/app/presence.py.
##
## Solo funciona con Backend en modo "http" (en el modo demo/mock no se conecta).
## Las escenas a pie llaman update_local() cada cuadro; las señales avisan de los demás.

signal peer_updated(id: String, data: Dictionary)
signal peer_left(id: String)
signal connection_changed(online: bool)
signal ended_by_peer(ending: Dictionary)  ## otro jugador de la partida acusó

const SEND_INTERVAL := 0.1     ## 10 veces por segundo mientras te mueves
const HEARTBEAT := 1.0         ## y una vez por segundo aunque estés quieto
const RECONNECT_EVERY := 3.0
const SETTINGS_PATH := "user://settings.cfg"

var player_name: String = ""
var enabled: bool = true  ## Opciones: "Ver a los demás jugadores"
var my_id: String = ""
var others: Dictionary = {}  ## id -> {id, name, scene, x, y, f, m}

var _ws: WebSocketPeer
var _state: int = WebSocketPeer.STATE_CLOSED
var _send_wait: float = 0.0
var _beat_wait: float = 0.0
var _retry_wait: float = 0.0
var _last_sent: Dictionary = {}
var _wanted: bool = false  ## alguna escena a pie pidió conexión
var _syncing: bool = false
var _sync_again: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	for arg: String in OS.get_cmdline_user_args():  # -- --name=Fer
		if arg.begins_with("--name="):
			player_name = arg.substr(7).strip_edges()


static func default_name() -> String:
	var n: String = OS.get_environment("USERNAME")
	if n == "":
		n = OS.get_environment("COMPUTERNAME")
	return n.substr(0, 20) if n != "" else "Investigador"


## ws://host:puerto/ws/presence a partir de la URL del motor (http -> ws, https -> wss).
static func ws_url(base_url: String) -> String:
	var u: String = base_url.strip_edges().trim_suffix("/")
	if u.begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.begins_with("http://"):
		u = "ws://" + u.substr(7)
	return u + "/ws/presence"


func is_online() -> bool:
	return _state == WebSocketPeer.STATE_OPEN and my_id != ""


## La escena a pie avisa dónde está el jugador local (cada cuadro).
func update_local(scene: String, pos: Vector2, facing: String, moving: bool, delta: float) -> void:
	_wanted = true
	if not is_online():
		return
	_send_wait -= delta
	_beat_wait -= delta
	var msg: Dictionary = {"t": "pos", "s": GameState.session_id(), "scene": scene, "x": snappedf(pos.x, 0.1),
		"y": snappedf(pos.y, 0.1), "f": facing, "m": moving}
	var changed: bool = msg != _last_sent
	if (changed and _send_wait <= 0.0) or _beat_wait <= 0.0:
		_ws.send_text(JSON.stringify(msg))
		_last_sent = msg
		_send_wait = SEND_INTERVAL
		_beat_wait = HEARTBEAT


func _process(delta: float) -> void:
	var active: bool = enabled and _wanted and Backend.mode == "http"
	if not active:
		if _ws != null:
			disconnect_now()
		return
	if _ws == null:
		_retry_wait -= delta
		if _retry_wait <= 0.0:
			_connect()
		return
	_ws.poll()
	var st: int = _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and _state != WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "hello", "s": GameState.session_id(), "code": Backend.access_code,
			"name": player_name if player_name != "" else default_name()}))
	_state = st
	if st == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			handle_message(_ws.get_packet().get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED:
		_drop_all()
		_ws = null
		_retry_wait = RECONNECT_EVERY


func _connect() -> void:
	_ws = WebSocketPeer.new()
	var err: Error = _ws.connect_to_url(ws_url(Backend.base_url))
	if err != OK:
		push_warning("[Presence] no se pudo conectar: %s" % error_string(err))
		_ws = null
		_retry_wait = RECONNECT_EVERY
		return
	_state = WebSocketPeer.STATE_CONNECTING


func disconnect_now() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_state = WebSocketPeer.STATE_CLOSED
	_drop_all()


func _drop_all() -> void:
	var was_online: bool = my_id != ""
	my_id = ""
	_last_sent = {}
	for id: String in others.keys():
		peer_left.emit(id)
	others.clear()
	if was_online:
		connection_changed.emit(false)


## Procesa un mensaje del motor (separado de _process para las pruebas).
func handle_message(text: String) -> void:
	var json: JSON = JSON.new()  # parse() no llena la consola de errores con mensajes malos
	if json.parse(text) != OK or not json.data is Dictionary:
		return
	var m: Dictionary = json.data
	match str(m.get("t", "")):
		"welcome":
			my_id = str(m.get("id", ""))
			connection_changed.emit(true)
		"state":
			for p: Variant in m.get("players", []):
				if p is Dictionary:
					_upsert(p)
		"pos":
			_upsert(m)
		"leave":
			var id: String = str(m.get("id", ""))
			if others.erase(id):
				peer_left.emit(id)
		"world":  # alguien cambió la partida: se vuelve a leer
			if str(m.get("s", "")) == GameState.session_id():
				sync_world()
		"ended":  # alguien acusó: este es el final, para todos
			if str(m.get("s", "")) == GameState.session_id() and not bool(GameState.world.get("ended", false)):
				var ending: Dictionary = m.get("ending", {}) if m.get("ending") is Dictionary else {}
				GameState.end_game(ending)
				ended_by_peer.emit(ending)


## Vuelve a leer la partida (si ya hay una lectura en curso, repite una vez al terminar).
func sync_world() -> void:
	if _syncing:
		_sync_again = true
		return
	_syncing = true
	await Backend.get_session()
	_syncing = false
	if _sync_again:
		_sync_again = false
		sync_world()


func _upsert(p: Dictionary) -> void:
	var id: String = str(p.get("id", ""))
	if id == "" or id == my_id:
		return
	if p.has("s") and str(p["s"]) != GameState.session_id():
		return  # es de otra partida
	var d: Dictionary = {"id": id, "name": str(p.get("name", "?")), "scene": str(p.get("scene", "")),
		"x": float(p.get("x", 0.0)), "y": float(p.get("y", 0.0)), "f": str(p.get("f", "down")),
		"m": bool(p.get("m", false))}
	others[id] = d
	peer_updated.emit(id, d)


# ---------- ajustes ----------

func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # conserva backend y audio
	cfg.set_value("presence", "name", player_name)
	cfg.set_value("presence", "enabled", enabled)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = str(cfg.get_value("presence", "name", ""))
		enabled = bool(cfg.get_value("presence", "enabled", true))
