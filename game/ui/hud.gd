class_name Hud
extends CanvasLayer
## HUD del pueblo: reloj, acto, evidencias, lugar actual, pista de interacción, avisos
## y botones de Diario y Pausa (para jugar también con el mouse).

signal journal_pressed
signal pause_pressed

const FEAR_NAMES: Array[String] = ["Tranquilo", "Inquieto", "Asustado", "Aterrado"]
const FEAR_COLORS: Array[Color] = [Color("5fae7a"), Color("e0b02c"), Color("e07a2c"), Color("d0504a")]

var journal_button: Button
var _fear_label: Label
var _fear_bar: ProgressBar
var _fear_fill: StyleBoxFlat
var _clock: Label
var _counts: Label
var _place: Label
var _prompt: Label
var _toasts: VBoxContainer
var _hint: Label


func _ready() -> void:
	layer = 5
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)

	var box: PanelContainer = _panel(root)
	box.position = Vector2(16, 14)
	var col: VBoxContainer = VBoxContainer.new()
	box.add_child(col)
	_clock = UiKit.label("", 26, UiKit.ACCENT)
	col.add_child(_clock)
	_counts = UiKit.label("", 17)
	col.add_child(_counts)
	var fear_row: HBoxContainer = HBoxContainer.new()
	fear_row.add_theme_constant_override("separation", 8)
	col.add_child(fear_row)
	_fear_label = UiKit.label("", 15, UiKit.MUTED)
	_fear_label.custom_minimum_size = Vector2(92, 0)
	fear_row.add_child(_fear_label)
	_fear_bar = ProgressBar.new()
	_fear_bar.show_percentage = false
	_fear_bar.custom_minimum_size = Vector2(120, 10)
	_fear_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fear_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fbg: StyleBoxFlat = StyleBoxFlat.new()
	fbg.bg_color = Color(0.1, 0.08, 0.14)
	_fear_fill = StyleBoxFlat.new()
	_fear_bar.add_theme_stylebox_override("background", fbg)
	_fear_bar.add_theme_stylebox_override("fill", _fear_fill)
	fear_row.add_child(_fear_bar)
	set_fear(Night.fear)

	_place = UiKit.label("", 20, UiKit.INK)
	_place.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_outline(_place)
	root.add_child(_place)

	_prompt = UiKit.label("", 20, UiKit.INK)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 46)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_outline(_prompt)
	root.add_child(_prompt)

	_hint = UiKit.label("", 14, UiKit.MUTED)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_outline(_hint)
	root.add_child(_hint)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(buttons)
	journal_button = _small_button("Diario (Tab)", func() -> void: journal_pressed.emit())
	buttons.add_child(journal_button)
	buttons.add_child(_small_button("Pausa (Esc)", func() -> void: pause_pressed.emit()))
	set_accuse_ready(false)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.alignment = BoxContainer.ALIGNMENT_CENTER
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func refresh() -> void:
	_clock.text = "%s · Acto %s" % [Night.clock_text(), TownLayout.act_roman(GameState.act())]
	_counts.text = "Evidencias: %d · Deducciones: %d" % [
		GameState.evidence_ids().size(), (GameState.world.get("deductions", []) as Array).size()]


## Miedo del jugador (0-100): barra y palabra con el color del nivel.
func set_fear(value: float) -> void:
	var lvl: int = 3 if value >= 80.0 else 2 if value >= 60.0 else 1 if value >= 35.0 else 0
	_fear_bar.value = value
	_fear_fill.bg_color = FEAR_COLORS[lvl]
	_fear_label.text = FEAR_NAMES[lvl]
	_fear_label.add_theme_color_override("font_color", FEAR_COLORS[lvl])


func fear_text() -> String:
	return _fear_label.text


func clock_label() -> String:
	return _clock.text


func set_place(location_id: String) -> void:
	_place.text = ContentDB.display_name(location_id) if location_id != "" else "Calles de San Jacinto"


func set_prompt(text: String) -> void:
	_prompt.text = text


func toast(text: String, color: Color = UiKit.ACCENT) -> void:
	var p: PanelContainer = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = UiKit.label(text, 19, color)
	p.add_child(l)
	_toasts.add_child(p)
	var t: Tween = p.create_tween()
	t.tween_interval(2.8)
	t.tween_property(p, "modulate:a", 0.0, 0.6)
	t.tween_callback(p.queue_free)


func set_accuse_ready(is_ready: bool) -> void:
	_hint.text = "Clic o WASD: caminar · Clic o E: hablar y examinar"
	if is_ready:
		_hint.text += "   ·   Ya puedes acusar desde el diario"
		_hint.add_theme_color_override("font_color", UiKit.ACCENT)
	else:
		_hint.add_theme_color_override("font_color", UiKit.MUTED)
	if journal_button:
		journal_button.add_theme_color_override("font_color", UiKit.ACCENT if is_ready else UiKit.INK)


func toast_count() -> int:
	return _toasts.get_child_count()


func prompt_text() -> String:
	return _prompt.text


func _small_button(text: String, on_press: Callable) -> Button:
	var b: Button = UiKit.button(text, on_press, 150)
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.focus_mode = Control.FOCUS_NONE  # que E o Enter no lo activen sin querer
	return b


func _panel(parent: Control) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.78)
	sb.border_color = UiKit.VIOLET.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _outline(l: Label) -> void:
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
