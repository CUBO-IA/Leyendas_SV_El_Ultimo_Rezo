extends Control
## Opciones: modo del Backend (mock/http), API_BASE_URL y prueba de conexión.

var _mode: OptionButton
var _url: LineEdit
var _result: Label
var _voice: CheckBox
var _mic: CheckBox
var _sliders: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	UiKit.background(self)
	var col: VBoxContainer = UiKit.centered_column(self, 14)
	col.add_child(UiKit.label("Opciones", 44, UiKit.ACCENT))

	col.add_child(UiKit.label("Motor de diálogo", 20, UiKit.MUTED))
	_mode = OptionButton.new()
	_mode.add_item("Mock (fixtures, sin motor)")
	_mode.add_item("HTTP (motor real)")
	_mode.selected = Backend.MODES.find(Backend.mode)
	_mode.custom_minimum_size = Vector2(520, 48)
	col.add_child(_mode)

	col.add_child(UiKit.label("API_BASE_URL", 20, UiKit.MUTED))
	_url = LineEdit.new()
	_url.text = Backend.base_url
	_url.placeholder_text = Backend.DEFAULT_URL
	_url.custom_minimum_size = Vector2(520, 48)
	col.add_child(_url)

	col.add_child(UiKit.label("Sonido", 20, UiKit.MUTED))
	_voice = _check("Voz de los personajes (Magpie TTS)", Sound.voice_enabled)
	col.add_child(_voice)
	_mic = _check("Hablar con el micrófono (mantén Tab en el interrogatorio)", Sound.mic_enabled)
	col.add_child(_mic)
	for bus: String in Sound.BUSES:
		col.add_child(_slider(bus))

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UiKit.button("Probar conexión", _on_test, 254))
	row.add_child(UiKit.button("Guardar y volver", _on_save, 254))
	col.add_child(row)

	_result = UiKit.label("", 18, UiKit.MUTED)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(520, 60)
	col.add_child(_result)
	_mode.grab_focus()


func _check(text: String, on: bool) -> CheckBox:
	var c: CheckBox = CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 18)
	return c


const BUS_NAMES: Dictionary = {"Music": "Música", "SFX": "Efectos", "Voice": "Voces"}


func _slider(bus: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = UiKit.label(BUS_NAMES.get(bus, bus), 18)
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Sound.volumes[bus])
	s.custom_minimum_size = Vector2(400, 28)
	s.value_changed.connect(func(v: float) -> void: Sound.set_volume(bus, v))
	row.add_child(s)
	_sliders[bus] = s
	return row


func _apply() -> void:
	Sound.voice_enabled = _voice.button_pressed
	Sound.mic_enabled = _mic.button_pressed
	Backend.set_mode(Backend.MODES[_mode.selected])
	Backend.set_base_url(_url.text)
	_url.text = Backend.base_url


func _on_test() -> void:
	_apply()
	_result.add_theme_color_override("font_color", UiKit.MUTED)
	_result.text = "Probando %s…" % ("el mock" if Backend.mode == "mock" else Backend.base_url)
	var r: Dictionary = await Backend.health()
	if not is_inside_tree():
		return
	if r["ok"]:
		var d: Dictionary = r["data"]
		_result.add_theme_color_override("font_color", UiKit.ACCENT)
		_result.text = "Conectado: %s · modelo %s · %s · voz %s · micrófono %s" % [
			d.get("status", "?"), d.get("model", "?"),
			"listo" if bool(d.get("warm", false)) else "calentando",
			"sí" if bool(d.get("tts", false)) else "no", "sí" if bool(d.get("stt", false)) else "no"]
	else:
		_result.add_theme_color_override("font_color", UiKit.DANGER)
		_result.text = "Falló: %s" % r["error"].get("detail", "")


func _on_save() -> void:
	_apply()
	Backend.save_settings()
	Sound.save_settings()
	SceneRouter.go(SceneRouter.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.TITLE)
