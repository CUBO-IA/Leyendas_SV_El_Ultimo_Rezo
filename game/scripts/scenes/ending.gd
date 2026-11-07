extends Control
## Final de la partida: fondo según ending.scene, título y texto letra a letra.
## Lee GameState.last_ending (lo deja Backend tras /accuse).

const BG := "res://assets/endings/%s.png"
const TITLE_COLORS: Dictionary = {
	"malo": Color("d0504a"), "gris": Color("b8b4c4"), "verdadero": Color("f0b048"),
}

var ending: Dictionary = {}
var _text: Label
var _buttons: HBoxContainer


func _ready() -> void:
	theme = UiKit.theme()
	ending = GameState.last_ending
	if ending.is_empty():
		# Abierta directo desde el editor: muestra el final malo de las fixtures.
		var f: Variant = Paths.read_json(Paths.fixture("ending__malo"))
		ending = f if f is Dictionary else {"ending_id": "malo", "title": "Fin", "text": "", "scene": ""}
	UiKit.background(self)

	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var path: String = BG % str(ending.get("scene", ""))
	if ResourceLoader.exists(path):
		bg.texture = load(path) as Texture2D
	bg.modulate.a = 0.0
	add_child(bg)
	create_tween().tween_property(bg, "modulate:a", 1.0, 1.6)

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -330
	shade.color = Color(0.02, 0.01, 0.04, 0.82)
	add_child(shade)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -320
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var kind: Label = UiKit.label("Final %s" % str(ending.get("ending_id", "")), 18, UiKit.MUTED)
	col.add_child(kind)
	var title: Label = UiKit.label(str(ending.get("title", "")), 44,
		TITLE_COLORS.get(str(ending.get("ending_id", "")), UiKit.ACCENT))
	col.add_child(title)
	_text = UiKit.label(str(ending.get("text", "")), 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.visible_ratio = 0.0
	col.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.modulate.a = 0.0
	col.add_child(_buttons)
	var again: Button = UiKit.button("Volver al título", _to_title, 260)
	_buttons.add_child(again)

	var t: Tween = create_tween()
	t.tween_interval(1.2)
	t.tween_property(_text, "visible_ratio", 1.0, maxf(2.0, _text.text.length() / 45.0))
	t.tween_property(_buttons, "modulate:a", 1.0, 0.5)
	t.tween_callback(again.grab_focus)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		_buttons.modulate.a = 1.0
		(_buttons.get_child(0) as Button).grab_focus()
		get_viewport().set_input_as_handled()


func _to_title() -> void:
	GameState.reset()
	SceneRouter.go(SceneRouter.TITLE)
