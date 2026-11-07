class_name Hud
extends CanvasLayer
## HUD del pueblo: reloj, acto, evidencias, lugar actual, pista de interacción y avisos.

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
	set_accuse_ready(false)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.alignment = BoxContainer.ALIGNMENT_CENTER
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func refresh() -> void:
	_clock.text = "%s · Acto %s" % [GameState.clock_text(), TownLayout.act_roman(GameState.act())]
	_counts.text = "Evidencias: %d · Deducciones: %d" % [
		GameState.evidence_ids().size(), (GameState.world.get("deductions", []) as Array).size()]


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
	_hint.text = "WASD/flechas: caminar · E: interactuar · Tab: diario · Esc: pausa"
	if is_ready:
		_hint.text += "   ·   Ya puedes acusar desde el diario"
		_hint.add_theme_color_override("font_color", UiKit.ACCENT)
	else:
		_hint.add_theme_color_override("font_color", UiKit.MUTED)


func toast_count() -> int:
	return _toasts.get_child_count()


func prompt_text() -> String:
	return _prompt.text


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
