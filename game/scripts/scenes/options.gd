extends Control
## Opciones: modo del Backend (mock/http), API_BASE_URL y prueba de conexión.

var _mode: OptionButton
var _url: LineEdit
var _result: Label


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


func _apply() -> void:
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
		_result.text = "Conectado: %s · modelo %s · %s" % [
			d.get("status", "?"), d.get("model", "?"),
			"listo" if bool(d.get("warm", false)) else "calentando"]
	else:
		_result.add_theme_color_override("font_color", UiKit.DANGER)
		_result.text = "Falló: %s" % r["error"].get("detail", "")


func _on_save() -> void:
	_apply()
	Backend.save_settings()
	SceneRouter.go(SceneRouter.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.TITLE)
