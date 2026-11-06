class_name MessageBox
extends CanvasLayer
## Caja de texto inferior con efecto letra a letra y retrato opcional.
##     await message_box.show_message("Comal", "Todavía caliente...")
## E, Espacio, Enter o clic: completa el texto si se está escribiendo; si no, cierra.

signal closed

const CHARS_PER_SEC := 60.0

var _panel: PanelContainer
var _portrait: TextureRect
var _title: Label
var _body: RichTextLabel
var _more: Label
var _tween: Tween


func _ready() -> void:
	layer = 10
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 24)
	_panel.offset_top = -210
	_panel.offset_bottom = -24
	root.add_child(_panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(150, 150)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_title = UiKit.label("", 24, UiKit.ACCENT)
	col.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_color_override("default_color", UiKit.INK)
	col.add_child(_body)
	_more = UiKit.label("E ▸", 16, UiKit.MUTED)
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_more)
	hide_box()


func is_open() -> bool:
	return _panel.visible


func show_message(title: String, text: String, portrait: Texture2D = null) -> void:
	_title.text = title
	_body.text = text
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_panel.visible = true
	_more.visible = false
	_body.visible_ratio = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_body, "visible_ratio", 1.0, maxf(0.2, text.length() / CHARS_PER_SEC))
	_tween.tween_callback(func() -> void: _more.visible = true)
	await closed


func hide_box() -> void:
	_panel.visible = false


func is_typing() -> bool:
	return _panel.visible and _body.visible_ratio < 1.0


## Avanza: completa el texto o cierra la caja.
func advance() -> void:
	if not _panel.visible:
		return
	if is_typing():
		if _tween:
			_tween.kill()
		_body.visible_ratio = 1.0
		_more.visible = true
		return
	hide_box()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or click:
		get_viewport().set_input_as_handled()
		advance()
