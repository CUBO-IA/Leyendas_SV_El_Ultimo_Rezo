class_name UiKit
extends RefCounted
## Estilo compartido (paleta nocturna de Día de Difuntos) y fábricas de controles.

const BG := Color("0d0b14")
const PANEL := Color("1a1626")
const INK := Color("efe6cf")
const MUTED := Color("9a90a8")
const ACCENT := Color("e08a2c")  # naranja de cempasúchil
const VIOLET := Color("7b4fa8")  # papel picado morado
const DANGER := Color("d0504a")


static func theme() -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = PANEL
		sb.border_color = VIOLET
		sb.set_border_width_all(2)
		sb.set_content_margin_all(10)
		match state:
			"hover":
				sb.border_color = ACCENT
			"pressed":
				sb.bg_color = VIOLET.darkened(0.4)
				sb.border_color = ACCENT
			"disabled":
				sb.border_color = MUTED.darkened(0.4)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = ACCENT
		t.set_stylebox(state, "Button", sb)
		t.set_stylebox(state if state != "hover" else "normal", "LineEdit", sb)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", MUTED)
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = VIOLET.darkened(0.3)
	panel.set_border_width_all(2)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


static func background(parent: Control) -> ColorRect:
	var bg: ColorRect = ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg


static func label(text: String, size: int = 20, color: Color = INK) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, min_width: int = 280) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.pressed.connect(on_press)
	return b


static func centered_column(parent: Control, separation: int = 16) -> VBoxContainer:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", separation)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	return col
