class_name Accusation
extends CanvasLayer
## Acusación: elegir 1 de los 6 sospechosos, las evidencias (máximo 10, como el
## contrato) y la decisión: revelar la verdad o negociar con la entidad.
##     var ending: Dictionary = await accusation.open()   # vacío si se cancela
## El motor decide el final; aquí solo se arma la petición.

signal finished(ending: Dictionary)

const MAX_EVIDENCE := 10
const DECISIONS: Dictionary = {
	"revelar": ["Revelar la verdad", "Cuentas al pueblo todo lo que descubriste, cueste lo que cueste."],
	"negociar": ["Negociar con la entidad", "Callas a cambio de que devuelva a los nueve."],
}

var suspect_id: String = ""
var decision: String = ""

var _root: Control
var _suspect_buttons: Dictionary = {}
var _suspect_info: Label
var _evidence_box: GridContainer
var _checks: Dictionary = {}  ## evidence_id -> CheckBox
var _count: Label
var _decision_buttons: Dictionary = {}
var _decision_info: Label
var _confirm: Button
var _error: Label
var _busy: bool = false


func _ready() -> void:
	layer = 11
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> Dictionary:
	suspect_id = ""
	decision = ""
	_error.text = ""
	for b: Button in _suspect_buttons.values():
		b.button_pressed = false
	for b: Button in _decision_buttons.values():
		b.button_pressed = false
	_suspect_info.text = "Elige a quién acusas."
	_decision_info.text = ""
	_fill_evidence()
	_update()
	_root.visible = true
	(_suspect_buttons.values()[0] as Button).grab_focus()
	return await finished


func cancel() -> void:
	if _root.visible and not _busy:
		_root.visible = false
		finished.emit({})


func _input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		cancel()


# ---------- selección ----------

func choose_suspect(id: String) -> void:
	suspect_id = id
	for sid: String in _suspect_buttons:
		(_suspect_buttons[sid] as Button).set_pressed_no_signal(sid == id)
	var s: Dictionary = ContentDB.suspect(id)
	_suspect_info.text = "%s — %s. %s" % [s.get("name", id), s.get("epithet", ""), s.get("intro", "")]
	_update()


func choose_decision(d: String) -> void:
	decision = d
	for k: String in _decision_buttons:
		(_decision_buttons[k] as Button).set_pressed_no_signal(k == d)
	_decision_info.text = DECISIONS[d][1]
	_update()


func set_evidence(id: String, on: bool) -> void:
	if not _checks.has(id):
		return
	var cb: CheckBox = _checks[id]
	if on and not cb.button_pressed and selected_evidence().size() >= MAX_EVIDENCE:
		return  # el contrato admite máximo 10
	cb.button_pressed = on
	_update()


func selected_evidence() -> Array[String]:
	var out: Array[String] = []
	for id: String in _checks:
		if (_checks[id] as CheckBox).button_pressed:
			out.append(id)
	return out


func _update() -> void:
	var n: int = selected_evidence().size()
	_count.text = "Pruebas elegidas: %d de %d como máximo" % [n, MAX_EVIDENCE]
	for id: String in _checks:
		var cb: CheckBox = _checks[id]
		cb.disabled = not cb.button_pressed and n >= MAX_EVIDENCE
	_confirm.disabled = _busy or suspect_id == "" or decision == ""


func confirm() -> void:
	if _confirm.disabled:
		return
	_busy = true
	_update()
	_error.text = ""
	var r: Dictionary = await Backend.accuse(suspect_id, selected_evidence(), decision)
	_busy = false
	if not r["ok"]:
		_error.text = str(r["error"].get("detail", "No se pudo acusar."))
		_update()
		return
	_root.visible = false
	finished.emit(r["data"])


# ---------- construcción ----------

func _fill_evidence() -> void:
	for c: Node in _evidence_box.get_children():
		c.queue_free()
	_checks.clear()
	for id: String in GameState.evidence_ids():
		var cb: CheckBox = CheckBox.new()
		cb.text = ContentDB.display_name(id)
		cb.add_theme_font_size_override("font_size", 17)
		cb.tooltip_text = str(ContentDB.evidence_item(id).get("description", ""))
		cb.toggled.connect(func(_on: bool) -> void: _update())
		_evidence_box.add_child(cb)
		_checks[id] = cb


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.04, 0.01, 0.03, 0.94)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(UiKit.label("¿Quién se llevó a los nueve?", 32, UiKit.ACCENT))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for id: String in ContentDB.suspect_ids():
		var b: Button = Button.new()
		b.toggle_mode = true
		b.text = ContentDB.display_name(id)
		b.icon = Portraits.get_texture(id, "neutral")
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(196, 210)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(choose_suspect.bind(id))
		row.add_child(b)
		_suspect_buttons[id] = b
	_suspect_info = UiKit.label("", 17, UiKit.MUTED)
	_suspect_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_suspect_info)

	var mid: HBoxContainer = HBoxContainer.new()
	mid.add_theme_constant_override("separation", 24)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)
	var evcol: VBoxContainer = VBoxContainer.new()
	evcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(evcol)
	_count = UiKit.label("", 18)
	evcol.add_child(_count)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	evcol.add_child(scroll)
	_evidence_box = GridContainer.new()
	_evidence_box.columns = 2
	_evidence_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_evidence_box)

	var dcol: VBoxContainer = VBoxContainer.new()
	dcol.custom_minimum_size = Vector2(380, 0)
	dcol.add_theme_constant_override("separation", 8)
	mid.add_child(dcol)
	dcol.add_child(UiKit.label("¿Qué haces con la verdad?", 18))
	for k: String in DECISIONS:
		var b: Button = UiKit.button(DECISIONS[k][0], choose_decision.bind(k), 380)
		b.toggle_mode = true
		dcol.add_child(b)
		_decision_buttons[k] = b
	_decision_info = UiKit.label("", 16, UiKit.MUTED)
	_decision_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dcol.add_child(_decision_info)

	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	_error = UiKit.label("", 17, UiKit.DANGER)
	_error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_error)
	bottom.add_child(UiKit.button("Volver (Esc)", cancel, 180))
	_confirm = UiKit.button("Acusar", confirm, 220)
	bottom.add_child(_confirm)
