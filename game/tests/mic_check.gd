extends Node
## Chequeo del micrófono real con el detector de voz (con ventana; headless no tiene audio):
##   Godot --path game res://tests/mic_check.tscn -- --backend=http
## Graba hasta que el detector decide (o 15 s), imprime el nivel cada 0.25 s y,
## con el motor corriendo, transcribe lo grabado por /stt.

var _vad: VoiceActivity = VoiceActivity.new()
var _t: float = 0.0
var _next_print: float = 0.0
var _done: bool = false


func _ready() -> void:
	print("[mic] dispositivos: ", AudioServer.get_input_device_list(), " · disponible: ", Sound.mic_available())
	if not Sound.start_recording():
		print("[mic] no se pudo grabar")
		Sound.quit_clean(1)
		return
	print("[mic] grabando: habla y luego guarda silencio")


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var level: float = Sound.mic_level_db()
	var verdict: String = _vad.feed(level, delta)
	if _t >= _next_print:
		_next_print += 0.25
		print("[mic] t=%.2f nivel=%.1f dB umbral=%.1f voz=%s" % [_t, level, _vad.threshold_db(), _vad.heard_speech])
	if verdict != "" or _t > 15.0:
		_done = true
		_finish(verdict if verdict != "" else "tope")


func _finish(verdict: String) -> void:
	var wav: PackedByteArray = Sound.stop_recording()
	print("[mic] fin: %s a los %.2f s · WAV %d bytes" % [verdict, _t, wav.size()])
	if Backend.mode == "http" and wav.size() > 8000:
		var r: Dictionary = await Backend.stt(wav)
		print("[mic] transcripción: ", r["data"].get("text", "") if r["ok"] else r["error"])
	Sound.quit_clean(0)
