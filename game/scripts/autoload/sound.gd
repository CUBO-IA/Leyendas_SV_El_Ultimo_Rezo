extends Node
## Todo el audio del cliente:
##  - buses Music, SFX y Voice con volumen propio (Opciones, user://settings.cfg);
##  - ambiente (música en bucle y viento) y campanadas;
##  - voz de los testigos: descarga el MP3 de audio_url y lo reproduce;
##  - micrófono: graba en un bus silenciado (AudioEffectRecord) y entrega un WAV.

signal voice_started
signal voice_finished

const SETTINGS_PATH := "user://settings.cfg"
const SFX := "res://assets/sfx/%s.wav"
const BUSES: Array[String] = ["Music", "SFX", "Voice"]
const MIC_BUS := "Mic"
const MAX_RECORD_S := 25.0  # el motor acepta hasta 30 s

var voice_enabled: bool = true
var mic_enabled: bool = true
## true: la pregunta dictada queda en la caja para corregirla; false: se envía sola.
var mic_review: bool = false
var volumes: Dictionary = {"Music": 0.45, "SFX": 0.8, "Voice": 1.0}

var _music: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _bell: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _voice_req: HTTPRequest
var _voice_token: int = 0
var _mic: AudioStreamPlayer
var _record: AudioEffectRecord
var _analyzer_idx: int = -1
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _record_timer: Timer
var _ambience: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)  # cerrar la ventana pasa por quit_clean()
	for b: String in BUSES:
		_ensure_bus(b)
	_setup_mic_bus()
	_music = _player("musica", "Music", true)
	_wind = _player("viento", "SFX", true)
	_wind.volume_db = -8.0
	_bell = _player("campanada", "SFX", false)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	_voice.finished.connect(func() -> void: voice_finished.emit())
	add_child(_voice)
	_voice_req = HTTPRequest.new()
	_voice_req.timeout = 25.0
	add_child(_voice_req)
	_record_timer = Timer.new()
	_record_timer.one_shot = true
	add_child(_record_timer)
	load_settings()


## Apaga todo el audio y sale un instante después: el hilo de audio suelta las
## reproducciones en su siguiente ciclo (si no, Godot avisa de recursos retenidos).
func quit_clean(exit_code: int = 0) -> void:
	shutdown()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(exit_code)


func shutdown() -> void:
	_voice_token += 1
	_voice_req.cancel_request()
	_ambience = "none"
	for c: Node in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
	if is_recording():
		_record.set_recording_active(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_clean()  # cerrar con la X de la ventana


# ---------- ambiente ----------

## "title": solo música · "town": música y viento · "interior": música baja · "ending" · "none".
func play_ambience(kind: String) -> void:
	if kind == _ambience:
		return
	_ambience = kind
	var music_db: float = {"title": 0.0, "town": -3.0, "interior": -7.0, "ending": -2.0}.get(kind, -80.0)
	if kind == "none":
		_music.stop()
	elif not _music.playing:
		_music.play()
	_fade(_music, music_db)
	if kind == "town":
		if not _wind.playing:
			_wind.play()
		_fade(_wind, -8.0)
	else:
		_fade(_wind, -40.0)


func ambience() -> String:
	return _ambience


## Campanadas (una cada `interval` s; las doce de medianoche van más seguidas).
func bell(times: int = 1, interval: float = 2.4) -> void:
	for i: int in times:
		_bell.play()
		await get_tree().create_timer(interval).timeout


## Latido según el miedo: 0 lo apaga; 1 es el más fuerte y rápido.
func set_heartbeat(level: float) -> void:
	if _heart == null:
		_heart = _player("latido", "SFX", true)
	if level <= 0.0:
		if _heart.playing:
			_heart.stop()
		return
	_heart.volume_db = lerpf(-22.0, -4.0, clampf(level, 0.0, 1.0))
	_heart.pitch_scale = lerpf(0.95, 1.6, clampf(level, 0.0, 1.0))
	if not _heart.playing:
		_heart.play()


func heartbeat_playing() -> bool:
	return _heart != null and _heart.playing


func play_sfx(sfx_name: String, db: float = 0.0) -> void:
	var p: AudioStreamPlayer = _player(sfx_name, "SFX", false)
	p.volume_db = db
	p.finished.connect(p.queue_free)
	p.play()


# ---------- voz de los testigos ----------

## Descarga y reproduce el MP3 de una respuesta. Corta la voz anterior.
func play_voice(audio_url: Variant) -> void:
	var url: String = Backend.audio_full_url(audio_url)
	if not voice_enabled or url == "":
		return
	_voice_token += 1
	var token: int = _voice_token
	_voice.stop()
	_voice_req.cancel_request()
	var err: Error = _voice_req.request(url, HttpBackend.auth_headers([]))
	if err != OK:
		push_warning("[Sound] no se pudo pedir la voz: %s" % error_string(err))
		return
	var out: Array = await _voice_req.request_completed
	if token != _voice_token:
		return  # llegó otra respuesta mientras tanto
	if int(out[0]) != HTTPRequest.RESULT_SUCCESS or int(out[1]) != 200:
		print("[Sound] voz no disponible (%s, HTTP %s)" % [out[0], out[1]])
		return
	var mp3: AudioStreamMP3 = AudioStreamMP3.new()
	mp3.data = out[3]
	_voice.stream = mp3
	_voice.play()
	voice_started.emit()


func stop_voice() -> void:
	_voice_token += 1
	_voice_req.cancel_request()
	_voice.stop()


func is_voice_playing() -> bool:
	return _voice.playing


func voice_length() -> float:
	return _voice.stream.get_length() if _voice.stream else 0.0


# ---------- micrófono ----------

func mic_available() -> bool:
	return mic_enabled and bool(ProjectSettings.get_setting("audio/driver/enable_input", false)) \
		and not AudioServer.get_input_device_list().is_empty()


func is_recording() -> bool:
	return _record != null and _record.is_recording_active()


func start_recording() -> bool:
	if not mic_available() or is_recording():
		return false
	if _mic == null:
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = MIC_BUS
		add_child(_mic)
	_mic.play()
	_record.set_recording_active(true)
	_record_timer.start(MAX_RECORD_S)
	return true


## Detiene la grabación y devuelve el WAV completo (vacío si no hubo audio).
func stop_recording() -> PackedByteArray:
	if not is_recording():
		return PackedByteArray()
	_record_timer.stop()
	_record.set_recording_active(false)
	var rec: AudioStreamWAV = _record.get_recording()
	_mic.stop()
	if rec == null or rec.data.is_empty():
		return PackedByteArray()
	return wav_bytes(rec)


func record_time_left() -> float:
	return _record_timer.time_left


## Volumen actual del micrófono en dB (-80 = silencio o sin grabar). Sirve para
## dibujar el medidor y para detectar cuándo el jugador dejó de hablar.
func mic_level_db() -> float:
	if not is_recording():
		return -80.0
	if _analyzer == null:
		var bus: int = AudioServer.get_bus_index(MIC_BUS)
		_analyzer = AudioServer.get_bus_effect_instance(bus, _analyzer_idx) as AudioEffectSpectrumAnalyzerInstance
		if _analyzer == null:
			return -80.0
	var m: Vector2 = _analyzer.get_magnitude_for_frequency_range(
		100.0, 4000.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
	return maxf(linear_to_db(maxf(m.x, m.y)), -80.0)


static func wav_bytes(stream: AudioStreamWAV) -> PackedByteArray:
	var path: String = "user://ultima_pregunta.wav"
	if stream.save_to_wav(path) != OK:
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


# ---------- volúmenes y ajustes ----------

func set_volume(bus_name: String, linear: float) -> void:
	volumes[bus_name] = clampf(linear, 0.0, 1.0)
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volumes[bus_name], 0.0001)))
		AudioServer.set_bus_mute(idx, volumes[bus_name] <= 0.001)


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		voice_enabled = bool(cfg.get_value("audio", "voice_enabled", voice_enabled))
		mic_enabled = bool(cfg.get_value("audio", "mic_enabled", mic_enabled))
		mic_review = bool(cfg.get_value("audio", "mic_review", mic_review))
		for b: String in BUSES:
			volumes[b] = float(cfg.get_value("audio", "volume_" + b.to_lower(), volumes[b]))
	for b: String in BUSES:
		set_volume(b, volumes[b])


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # conserva las otras secciones (backend)
	cfg.set_value("audio", "voice_enabled", voice_enabled)
	cfg.set_value("audio", "mic_enabled", mic_enabled)
	cfg.set_value("audio", "mic_review", mic_review)
	for b: String in BUSES:
		cfg.set_value("audio", "volume_" + b.to_lower(), volumes[b])
	cfg.save(SETTINGS_PATH)


# ---------- internos ----------

func _ensure_bus(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _setup_mic_bus() -> void:
	var idx: int = _ensure_bus(MIC_BUS)
	AudioServer.set_bus_mute(idx, true)  # lo grabado no sale por los parlantes
	for i: int in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectRecord:
			_record = AudioServer.get_bus_effect(idx, i)
		elif AudioServer.get_bus_effect(idx, i) is AudioEffectSpectrumAnalyzer:
			_analyzer_idx = i
	if _record == null:
		_record = AudioEffectRecord.new()
		_record.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(idx, _record)
	if _analyzer_idx == -1:
		# Medidor de nivel: lee el audio del micrófono sin modificarlo.
		var an: AudioEffectSpectrumAnalyzer = AudioEffectSpectrumAnalyzer.new()
		an.buffer_length = 0.1
		an.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
		AudioServer.add_bus_effect(idx, an)
		_analyzer_idx = AudioServer.get_bus_effect_count(idx) - 1


func _player(sfx_name: String, bus_name: String, loop: bool) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	var s: AudioStreamWAV = load(SFX % sfx_name) as AudioStreamWAV
	if loop and s:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.bus = bus_name
	add_child(p)
	return p


func _fade(p: AudioStreamPlayer, db: float, secs: float = 1.2) -> void:
	var t: Tween = create_tween()
	t.tween_property(p, "volume_db", db, secs)
