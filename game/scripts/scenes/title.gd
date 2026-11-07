extends Control
## Pantalla de título: Nueva partida, Opciones, Salir.

var _buttons: Array[Button] = []
var _status: Label
var _error: Label


func _ready() -> void:
	theme = UiKit.theme()
	UiKit.background(self)
	var col: VBoxContainer = UiKit.centered_column(self, 14)

	var title: Label = UiKit.label("Leyendas SV", 64, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub: Label = UiKit.label("El Último Rezo de las Ánimas", 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var town: Label = UiKit.label("San Jacinto de las Ánimas · víspera del Día de los Difuntos", 18, UiKit.MUTED)
	town.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(town)
	col.add_child(Control.new())  # aire

	for spec: Array in [["Nueva partida", _on_new_game], ["Opciones", _on_options], ["Salir", _on_quit]]:
		var b: Button = UiKit.button(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(b)
		_buttons.append(b)

	_error = UiKit.label("", 18, UiKit.DANGER)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(640, 0)
	col.add_child(_error)

	_status = UiKit.label("", 16, UiKit.MUTED)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(_status)
	_buttons[0].grab_focus()
	Sound.play_ambience("title")
	_check_backend()


func _check_backend() -> void:
	_status.text = "Backend: %s · comprobando…" % Backend.mode
	var r: Dictionary = await Backend.health()
	if not is_inside_tree():
		return
	if r["ok"]:
		var d: Dictionary = r["data"]
		_status.text = "Backend: %s · %s · modelo %s%s" % [
			Backend.mode, d.get("status", "?"), d.get("model", "?"),
			"" if bool(d.get("warm", false)) else " (calentando)"]
	else:
		_status.text = "Backend: %s · sin conexión (%s)" % [Backend.mode, r["error"].get("detail", "")]


func _set_enabled(enabled: bool) -> void:
	for b: Button in _buttons:
		b.disabled = not enabled


func _on_new_game() -> void:
	_set_enabled(false)
	_error.text = ""
	var r: Dictionary = await Backend.new_session()
	if r["ok"]:
		SceneRouter.go(SceneRouter.TOWN)
	else:
		_error.text = "No se pudo crear la partida: %s\nRevisa Opciones o usa el modo mock." % r["error"].get("detail", "")
		_set_enabled(true)


func _on_options() -> void:
	SceneRouter.go(SceneRouter.OPTIONS)


func _on_quit() -> void:
	Sound.quit_clean()
