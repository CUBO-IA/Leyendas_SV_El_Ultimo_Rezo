class_name Interrogation
extends CanvasLayer
## Pantalla de interrogatorio: retrato con emoción, nivel, confianza y miedo,
## conversación libre (Enter envía) y "Presentar evidencia".
##     await interrogation.open("alcides")   # vuelve cuando el jugador sale (Esc)
## Las reglas (niveles, deducciones) las decide el motor; aquí solo se muestran.

signal closed
signal contradiction_shown(level: String)

const FALLBACK_LINES: Array[String] = [
	"Déjeme pensar... es que esta noche ando con los nervios de punta.",
	"Ay, no sé ni qué decirle. Espéreme tantito.",
	"Mire... (se queda callado, mirando hacia la iglesia).",
]
const EMOTION_COLORS: Dictionary = {
	"neutral": Color("9a90a8"), "nervioso": Color("e0b02c"), "enojado": Color("d0504a"),
	"asustado": Color("7b4fa8"), "triste": Color("4f7bb8"), "aliviado": Color("5fae7a"),
}
const EMOTION_NAMES: Dictionary = {
	"neutral": "tranquilo", "nervioso": "nervioso", "enojado": "enojado",
	"asustado": "asustado", "triste": "triste", "aliviado": "aliviado",
}

## Segundos antes de la frase de respaldo mientras se espera al motor.
var wait_fallback_s: float = 15.0
var witness_id: String = ""
var emotion: String = "neutral"

var _root: Control
var _main: Control
var _portrait: TextureRect
var _frame: PanelContainer
var _name: Label
var _role: Label
var _emotion: Label
var _level: Label
var _trust: ProgressBar
var _fear: ProgressBar
var _trust_n: Label
var _fear_n: Label
var _log: RichTextLabel
var _waiting: Label
var _question: LineEdit
var _send: Button
var _present_btn: Button
var _picker: Control
var _picker_list: ItemList
var _picker_desc: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _flash: ColorRect
var _sfx_hit: AudioStreamPlayer
var _sfx_item: AudioStreamPlayer
var _sfx_voice: AudioStreamPlayer

var _busy: bool = false
var _request_token: int = 0
var _answered_token: int = 0
var _type_tween: Tween
var _voice_accum: float = 0.0
var _picker_ids: Array[String] = []
var _wait_timer: Timer


func _ready() -> void:
	layer = 8
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func _exit_tree() -> void:
	# Un sonido que sigue sonando al cerrar el juego deja su reproducción retenida.
	for p: AudioStreamPlayer in [_sfx_hit, _sfx_item, _sfx_voice]:
		p.stop()


# ---------- abrir / cerrar ----------

func open(id: String) -> void:
	witness_id = id
	var w: Dictionary = ContentDB.witness(id)
	_name.text = str(w.get("name", id))
	_role.text = str(w.get("role", ""))
	_log.clear()
	_log.visible_characters = -1
	_picker.visible = false
	_banner.visible = false
	_set_emotion("neutral")
	_refresh_gauges()
	var history: Array = GameState.transcript(id)
	if history.is_empty():
		# Primera vez: su presentación pública, sin llamar al motor.
		_add_line("npc", str(w.get("intro", "...")), true)
	else:
		for line: Dictionary in history.slice(maxi(0, history.size() - 8)):
			_append_line(str(line["who"]), str(line["text"]))
	_root.visible = true
	_set_busy(false)
	_question.grab_focus()
	await closed


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	_question.release_focus()
	closed.emit()


func _input_event_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")


func _input(event: InputEvent) -> void:
	if not _root.visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key and key.pressed and not key.echo and key.ctrl_pressed and (key.physical_keycode == KEY_E or key.keycode == KEY_E):
		get_viewport().set_input_as_handled()
		open_picker()
		return
	if not _input_event_cancel(event):
		return
	get_viewport().set_input_as_handled()
	if _picker.visible:
		_picker.visible = false
		_question.grab_focus()
	elif _banner.visible:
		_banner.visible = false
	elif not _busy:
		close()


# ---------- preguntar ----------

func ask(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _busy:
		return
	_question.text = ""
	_add_line("player", text)
	var r: Dictionary = await _request(func() -> Dictionary: return await Backend.talk(witness_id, text))
	_handle_response(r, false)


func present(evidence_id: String) -> void:
	if _busy:
		return
	_picker.visible = false
	_add_line("player", "[Muestra: %s]" % ContentDB.display_name(evidence_id))
	var r: Dictionary = await _request(func() -> Dictionary: return await Backend.present(witness_id, evidence_id))
	_handle_response(r, true)


## Lanza la petición; si tarda más de wait_fallback_s, el testigo dice una frase de
## respaldo mientras tanto (la respuesta real se muestra igual cuando llega).
func _request(request_fn: Callable) -> Dictionary:
	_set_busy(true)
	_request_token += 1
	var token: int = _request_token
	_wait_timer.start(wait_fallback_s)
	var r: Dictionary = await request_fn.call()
	_answered_token = token
	_wait_timer.stop()
	_set_busy(false)
	return r


func _on_wait_timeout() -> void:
	var token: int = _request_token
	if _answered_token < token and _root.visible:
		_add_line("npc", FALLBACK_LINES[token % FALLBACK_LINES.size()], true)


func _handle_response(r: Dictionary, presenting: bool) -> void:
	if not _root.visible:
		return
	if not r["ok"]:
		var err: Dictionary = r["error"]
		_add_line("system", str(err.get("detail", "No hubo respuesta.")))
		_question.grab_focus()
		return
	var d: Dictionary = r["data"]
	_set_emotion(str(d.get("emotion", "neutral")))
	_add_line("npc", str(d.get("reply", "...")), true)
	_refresh_gauges()
	var deductions: Array = d.get("new_deductions", [])
	var evidence: Array = d.get("new_evidence", [])
	var broke: bool = bool(d.get("contradiction", false)) if presenting else not deductions.is_empty()
	if broke:
		_contradiction(str(d.get("level", "")), deductions, evidence)
	elif not evidence.is_empty():
		_sfx_item.play()
	for ev: Variant in evidence:
		_add_line("system", "Nueva evidencia: %s" % ContentDB.display_name(str(ev)))
	_question.grab_focus()


# ---------- contradicción ----------

func _contradiction(level: String, deductions: Array, evidence: Array) -> void:
	_sfx_hit.play()
	_shake()
	var flash: Tween = create_tween()
	_flash.color.a = 0.45
	flash.tween_property(_flash, "color:a", 0.0, 0.5)
	_banner_title.text = "¡Confesión!" if level == "confesion" else "¡Contradicción!"
	var lines: Array[String] = []
	for d: Variant in deductions:
		lines.append(str((d as Dictionary).get("text", "")))
	for ev: Variant in evidence:
		lines.append("Te entrega: %s" % ContentDB.display_name(str(ev)))
	_banner_text.text = "\n".join(lines)
	_banner.visible = true
	_banner.modulate.a = 1.0
	var t: Tween = _banner.create_tween()
	t.tween_interval(5.0)
	t.tween_property(_banner, "modulate:a", 0.0, 0.6)
	t.tween_callback(func() -> void: _banner.visible = false)
	contradiction_shown.emit(level)


func _shake() -> void:
	var t: Tween = create_tween()
	for i: int in 8:
		var amp: float = 14.0 * (1.0 - i / 8.0)
		t.tween_property(_main, "position", Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), 0.04)
	t.tween_property(_main, "position", Vector2.ZERO, 0.05)


func is_shaking() -> bool:
	return _main.position != Vector2.ZERO


# ---------- estado visible ----------

func _set_emotion(e: String) -> void:
	emotion = e if EMOTION_COLORS.has(e) else "neutral"
	_portrait.texture = Portraits.get_texture(witness_id, emotion)
	_emotion.text = "Se ve %s" % EMOTION_NAMES[emotion]
	var sb: StyleBoxFlat = (_frame.get_theme_stylebox("panel") as StyleBoxFlat)
	sb.border_color = EMOTION_COLORS[emotion]
	_emotion.add_theme_color_override("font_color", EMOTION_COLORS[emotion])


func _refresh_gauges() -> void:
	var n: Dictionary = GameState.npc(witness_id)
	var level: String = str(n.get("level", "inicial"))
	_level.text = GameState.level_name(level)
	var lc: Color = {"inicial": UiKit.MUTED, "confrontada": UiKit.ACCENT, "confesion": Color("5fae7a")}.get(level, UiKit.MUTED)
	_level.add_theme_color_override("font_color", lc)
	_trust.value = int(n.get("trust", 0))
	_fear.value = int(n.get("fear", 0))
	_trust_n.text = "%d/10" % int(_trust.value)
	_fear_n.text = "%d/10" % int(_fear.value)


func level_text() -> String:
	return _level.text


func gauges() -> Vector2i:
	return Vector2i(int(_trust.value), int(_fear.value))


func banner_text() -> String:
	return _banner_text.text if _banner.visible else ""


func log_text() -> String:
	return _log.get_parsed_text()


func _set_busy(b: bool) -> void:
	_busy = b
	_question.editable = not b
	_send.disabled = b
	_present_btn.disabled = b or GameState.evidence_ids().is_empty()
	_waiting.visible = b


# ---------- conversación ----------

func _add_line(who: String, text: String, typed: bool = false) -> void:
	GameState.add_line(witness_id, who, text)
	_append_line(who, text, typed)


func _append_line(who: String, text: String, typed: bool = false) -> void:
	var before: int = _log.get_total_character_count()
	if before > 0:
		_log.append_text("\n\n")
	match who:
		"player":
			_log.append_text("[color=#9a90a8]Tú:[/color] [color=#cfc6b6]%s[/color]" % _escape(text))
		"npc":
			_log.append_text("[color=#e08a2c]%s:[/color] %s" % [_name.text, _escape(text)])
		_:
			_log.append_text("[color=#b58fe0][i]%s[/i][/color]" % _escape(text))
	if _type_tween:
		_type_tween.kill()
	if typed and who == "npc":
		var total: int = _log.get_total_character_count()
		_log.visible_characters = before
		_type_tween = create_tween()
		_type_tween.tween_property(_log, "visible_characters", total, maxf(0.3, (total - before) / 55.0))
		_type_tween.tween_callback(func() -> void: _log.visible_characters = -1)
	else:
		_log.visible_characters = -1


func is_typing() -> bool:
	return _log.visible_characters != -1


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_waiting.text = "%s está pensando%s" % [_name.text, ".".repeat(1 + floori(Time.get_ticks_msec() / 350.0) % 3)]
	if is_typing():
		_voice_accum += delta
		if _voice_accum > 0.07:
			_voice_accum = 0.0
			_sfx_voice.pitch_scale = randf_range(0.85, 1.15)
			_sfx_voice.play()


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


# ---------- selector de evidencias ----------

func open_picker() -> void:
	if _busy:
		return
	_picker_list.clear()
	_picker_ids = GameState.evidence_ids()
	for id: String in _picker_ids:
		_picker_list.add_item(ContentDB.display_name(id))
	_picker_desc.text = "Elige una evidencia para mostrársela a %s." % _name.text
	_picker.visible = true
	if not _picker_ids.is_empty():
		_picker_list.select(0)
		_on_pick_selected(0)
		_picker_list.grab_focus()


func _on_pick_selected(i: int) -> void:
	var e: Dictionary = ContentDB.evidence_item(_picker_ids[i])
	_picker_desc.text = "%s\n\n%s" % [e.get("name", ""), e.get("description", "")]


func _close_picker() -> void:
	_picker.visible = false
	_question.grab_focus()


func _on_banner_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		_banner.visible = false


func _on_pick_confirm() -> void:
	var sel: PackedInt32Array = _picker_list.get_selected_items()
	if not sel.is_empty():
		present(_picker_ids[sel[0]])


# ---------- construcción de la interfaz ----------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.06, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	_main = Control.new()
	_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_main)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	_main.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	margin.add_child(row)

	# Columna izquierda: retrato y estado.
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	_frame = PanelContainer.new()
	var fsb: StyleBoxFlat = StyleBoxFlat.new()
	fsb.bg_color = Color(0.06, 0.05, 0.09)
	fsb.set_border_width_all(4)
	fsb.set_content_margin_all(6)
	_frame.add_theme_stylebox_override("panel", fsb)
	left.add_child(_frame)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(340, 340)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame.add_child(_portrait)
	_name = UiKit.label("", 30, UiKit.ACCENT)
	left.add_child(_name)
	_role = UiKit.label("", 18, UiKit.MUTED)
	left.add_child(_role)
	_emotion = UiKit.label("", 18)
	left.add_child(_emotion)
	var lvl_row: HBoxContainer = HBoxContainer.new()
	lvl_row.add_child(UiKit.label("Testimonio: ", 18, UiKit.MUTED))
	_level = UiKit.label("", 20)
	lvl_row.add_child(_level)
	left.add_child(lvl_row)

	# Columna derecha: barras, conversación y entrada.
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	var gauges_row: HBoxContainer = HBoxContainer.new()
	gauges_row.add_theme_constant_override("separation", 24)
	right.add_child(gauges_row)
	var tg: Array = _gauge("Confianza", Color("5fae7a"))
	gauges_row.add_child(tg[0])
	_trust = tg[1]
	_trust_n = tg[2]
	var fg: Array = _gauge("Miedo", UiKit.DANGER)
	gauges_row.add_child(fg[0])
	_fear = fg[1]
	_fear_n = fg[2]

	var log_panel: PanelContainer = PanelContainer.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.add_theme_font_size_override("normal_font_size", 20)
	_log.add_theme_font_size_override("italics_font_size", 18)
	_log.add_theme_color_override("default_color", UiKit.INK)
	log_panel.add_child(_log)

	_waiting = UiKit.label("", 17, UiKit.MUTED)
	right.add_child(_waiting)

	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	right.add_child(input_row)
	_question = LineEdit.new()
	_question.placeholder_text = "Pregúntale algo y pulsa Enter…"
	_question.max_length = 300
	_question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_question.custom_minimum_size = Vector2(0, 50)
	_question.add_theme_font_size_override("font_size", 20)
	_question.text_submitted.connect(ask)
	input_row.add_child(_question)
	_send = UiKit.button("Preguntar", func() -> void: ask(_question.text), 140)
	input_row.add_child(_send)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	right.add_child(actions)
	_present_btn = UiKit.button("Presentar evidencia (Ctrl+E)", open_picker, 320)
	actions.add_child(_present_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(UiKit.label("Esc: volver al pueblo", 16, UiKit.MUTED))

	_build_picker()
	_build_banner()
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.1, 0.1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_wait_timer = Timer.new()
	_wait_timer.one_shot = true
	_wait_timer.timeout.connect(_on_wait_timeout)
	add_child(_wait_timer)
	_sfx_hit = _player("res://assets/sfx/contradiccion.wav", 0.0)
	_sfx_item = _player("res://assets/sfx/evidencia.wav", -4.0)
	_sfx_voice = _player("res://assets/sfx/voz.wav", -18.0)


func _gauge(title: String, color: Color) -> Array:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = HBoxContainer.new()
	var t: Label = UiKit.label(title, 18, UiKit.MUTED)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var n: Label = UiKit.label("", 18)
	head.add_child(n)
	box.add_child(head)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 10
	bar.step = 1
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.08, 0.14)
	bg.border_color = UiKit.VIOLET.darkened(0.4)
	bg.set_border_width_all(2)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	return [box, bar, n]


func _build_picker() -> void:
	_picker = Control.new()
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.visible = false
	_root.add_child(_picker)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	center.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiKit.label("Presentar evidencia", 28, UiKit.ACCENT))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	_picker_list = ItemList.new()
	_picker_list.custom_minimum_size = Vector2(340, 340)
	_picker_list.add_theme_font_size_override("font_size", 19)
	_picker_list.item_selected.connect(_on_pick_selected)
	_picker_list.item_activated.connect(func(_i: int) -> void: _on_pick_confirm())
	row.add_child(_picker_list)
	_picker_desc = UiKit.label("", 18)
	_picker_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_picker_desc.custom_minimum_size = Vector2(380, 340)
	_picker_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(_picker_desc)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(buttons)
	buttons.add_child(UiKit.button("Cancelar", _close_picker, 160))
	buttons.add_child(UiKit.button("Mostrar", _on_pick_confirm, 160))


func _build_banner() -> void:
	_banner = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.03, 0.05, 0.96)
	sb.border_color = UiKit.ACCENT
	sb.set_border_width_all(3)
	sb.set_content_margin_all(18)
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 104)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.custom_minimum_size = Vector2(720, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.gui_input.connect(_on_banner_input)
	_banner.visible = false
	_root.add_child(_banner)
	var col: VBoxContainer = VBoxContainer.new()
	_banner.add_child(col)
	_banner_title = UiKit.label("", 36, UiKit.ACCENT)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_title)
	_banner_text = UiKit.label("", 20)
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.custom_minimum_size = Vector2(680, 0)
	col.add_child(_banner_text)


func _player(path: String, db: float) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = load(path) as AudioStream
	p.volume_db = db
	add_child(p)
	return p
