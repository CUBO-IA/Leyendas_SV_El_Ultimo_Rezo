class_name VoiceActivity
extends RefCounted
## Decide cuándo el jugador terminó de hablar a partir del volumen del micrófono.
## Se alimenta cada cuadro con feed(nivel_db, delta) y responde:
##   ""          -> sigue escuchando
##   "end"       -> habló y luego hubo SILENCE_END_S de silencio
##   "no_speech" -> pasaron NO_SPEECH_S sin que se oyera voz
## El umbral se adapta al ruido de fondo: voz = nivel > piso de ruido + MARGIN_DB.

const SILENCE_END_S := 1.1
const NO_SPEECH_S := 8.0
const MIN_SPEECH_S := 0.15  ## voz acumulada para dar por hecho que habló
const MARGIN_DB := 14.0
const MIN_THRESHOLD_DB := -58.0

var heard_speech: bool = false
var elapsed: float = 0.0
var _floor_db: float = 0.0
var _speech_s: float = 0.0
var _silence_s: float = 0.0
var _started: bool = false


func threshold_db() -> float:
	return maxf(_floor_db + MARGIN_DB, MIN_THRESHOLD_DB)


func feed(level_db: float, delta: float) -> String:
	elapsed += delta
	if level_db <= -79.5 and not heard_speech:
		# El medidor aún no tiene datos (primeros cuadros): no sirve para calibrar.
		return "no_speech" if elapsed >= NO_SPEECH_S else ""
	if not _started:
		_started = true
		_floor_db = level_db
	# El piso baja de inmediato y sube despacio (1.5 dB/s): sigue al ruido, no a la voz
	# (entre palabras el nivel cae y lo vuelve a fijar).
	_floor_db = minf(level_db, _floor_db + 1.5 * delta)
	if level_db > threshold_db():
		_speech_s += delta
		_silence_s = 0.0
		if _speech_s >= MIN_SPEECH_S:
			heard_speech = true
	else:
		_silence_s += delta
	if heard_speech and _silence_s >= SILENCE_END_S:
		return "end"
	if not heard_speech and elapsed >= NO_SPEECH_S:
		return "no_speech"
	return ""
