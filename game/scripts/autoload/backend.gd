extends Node
## Única puerta del cliente hacia el motor. Dos modos:
##  - "mock": responde con contract/fixtures/ y simula avances (sin motor).
##  - "http": llama a API_BASE_URL (el motor FastAPI).
##
## Cada llamada se puede esperar y devuelve {ok: bool, data: Dictionary, error: Dictionary}:
##     var r: Dictionary = await Backend.talk("chonita", "¿Qué vio?")
## Además emite response_received / request_failed para quien prefiera señales.
## Si la respuesta trae "state", GameState se actualiza solo.
##
## Modo y URL se guardan en user://settings.cfg. Se pueden forzar al arrancar:
##     Godot --path game -- --backend=http --api=http://127.0.0.1:8000

signal response_received(kind: String, data: Dictionary)
signal request_failed(kind: String, error: Dictionary)
signal mode_changed(mode: String)
signal busy_changed(busy: bool)

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_URL := "http://127.0.0.1:8000"
const MODES: Array[String] = ["mock", "http"]

var mode: String = "mock"
var base_url: String = DEFAULT_URL
var timeout_s: float = 20.0
var mock_delay_s: float = 0.25  ## latencia simulada del mock

var _mock: MockBackend
var _http: HttpBackend
var _pending: int = 0


func _ready() -> void:
	_mock = MockBackend.new()
	_http = HttpBackend.new()
	_http.name = "Http"
	add_child(_http)
	_load_settings()
	_apply_cmdline()
	print("[Backend] modo=%s url=%s" % [mode, base_url])


# ---------- API pública ----------

func health() -> Dictionary:
	return await _call("health", HTTPClient.METHOD_GET, "/health", null)


func new_session(player_name: String = "Investigador", demo: bool = false) -> Dictionary:
	var body: Dictionary = {"player_name": player_name}
	if demo:
		body["demo"] = true
	GameState.reset()
	return await _call("session", HTTPClient.METHOD_POST, "/session", body)


func get_session() -> Dictionary:
	return await _call("get_session", HTTPClient.METHOD_GET,
		"/session/%s" % GameState.session_id().uri_encode(), null)


func talk(npc_id: String, text: String, want_audio: bool = false) -> Dictionary:
	return await _call("talk", HTTPClient.METHOD_POST, "/talk", {
		"session_id": GameState.session_id(), "npc_id": npc_id,
		"text": text, "want_audio": want_audio})


func present(npc_id: String, evidence_id: String, want_audio: bool = false) -> Dictionary:
	return await _call("present", HTTPClient.METHOD_POST, "/present", {
		"session_id": GameState.session_id(), "npc_id": npc_id,
		"evidence_id": evidence_id, "want_audio": want_audio})


func examine(object_id: String) -> Dictionary:
	return await _call("examine", HTTPClient.METHOD_POST, "/examine", {
		"session_id": GameState.session_id(), "object_id": object_id})


func accuse(suspect_id: String, evidence_ids: Array[String], decision: String) -> Dictionary:
	return await _call("accuse", HTTPClient.METHOD_POST, "/accuse", {
		"session_id": GameState.session_id(), "suspect_id": suspect_id,
		"evidence_ids": evidence_ids, "decision": decision})


## Voz del jugador a texto. wav: archivo WAV completo (A5).
func stt(wav: PackedByteArray) -> Dictionary:
	if mode == "mock":
		return await _call("stt", HTTPClient.METHOD_POST, "/stt", {})
	_set_busy(1)
	var res: Dictionary = await _http.request_raw(base_url + "/stt", wav, "audio/wav", timeout_s)
	_set_busy(-1)
	_emit("stt", res)
	return res


## URL absoluta de un audio_url relativo ("/audio/x.mp3"). Vacío en mock o si es null.
func audio_full_url(audio_url: Variant) -> String:
	if mode == "mock" or audio_url == null or str(audio_url) == "":
		return ""
	return base_url + str(audio_url)


func is_busy() -> bool:
	return _pending > 0


# ---------- configuración ----------

func set_mode(new_mode: String) -> void:
	if new_mode not in MODES or new_mode == mode:
		return
	mode = new_mode
	mode_changed.emit(mode)


func set_base_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	if base_url == "":
		base_url = DEFAULT_URL


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # conserva las otras secciones (audio)
	cfg.set_value("backend", "mode", mode)
	cfg.set_value("backend", "base_url", base_url)
	var err: Error = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("No se pudo guardar %s (%s)" % [SETTINGS_PATH, error_string(err)])


func _load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var m: String = str(cfg.get_value("backend", "mode", mode))
	if m in MODES:
		mode = m
	set_base_url(str(cfg.get_value("backend", "base_url", base_url)))


func _apply_cmdline() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):
			var m: String = arg.get_slice("=", 1)
			if m in MODES:
				mode = m
		elif arg.begins_with("--api="):
			set_base_url(arg.substr(6))


# ---------- despacho ----------

func _call(kind: String, method: int, path: String, body: Variant) -> Dictionary:
	_set_busy(1)
	var res: Dictionary
	if mode == "mock":
		await get_tree().create_timer(mock_delay_s).timeout
		res = _mock.handle(kind, body if body is Dictionary else {})
	else:
		res = await _http.request_json(method, base_url + path, body, timeout_s)
	_set_busy(-1)
	_emit(kind, res)
	return res


func _emit(kind: String, res: Dictionary) -> void:
	if not bool(res.get("ok", false)):
		var err: Dictionary = res.get("error", {})
		var code: String = str(err.get("error", "?"))
		var line: String = "[Backend] %s falló: %s — %s" % [kind, code, err.get("detail", "")]
		# Los errores de juego (evidence_not_owned, location_locked…) son flujo normal;
		# solo los de conexión o del motor merecen una advertencia.
		if code in ["network", "timeout", "internal"]:
			push_warning(line)
		else:
			print(line)
		request_failed.emit(kind, err)
		return
	var data: Dictionary = res["data"]
	if kind == "session" or kind == "get_session":
		GameState.apply_state(data)
	elif data.get("state") is Dictionary:
		GameState.apply_state(data["state"])
	if kind == "accuse":
		GameState.end_game(data)
	response_received.emit(kind, data)


func _set_busy(delta: int) -> void:
	var was: bool = _pending > 0
	_pending = maxi(0, _pending + delta)
	if was != (_pending > 0):
		busy_changed.emit(_pending > 0)
