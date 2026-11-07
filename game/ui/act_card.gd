class_name ActCard
extends CanvasLayer
## Tarjeta al empezar cada acto: título, hora y unas líneas de ambiente (sin spoilers).
## Aparece, se queda HOLD segundos y se desvanece; una tecla o un clic la quita antes.
## No congela el juego (las pruebas y el jugador siguen como siempre).

const HOLD := 4.5
const ACTS: Dictionary = {
	1: ["Acto I", "La víspera de los Difuntos",
		"Se fue la luz en todo San Jacinto y, en siete minutos, nueve personas desaparecieron. Alguien en este pueblo miente."],
	2: ["Acto II", "La hora de los muertos",
		"Pasó la medianoche. La niebla baja del cementerio y la quebrada suena más fuerte que nunca. Los muertos también tienen algo que decir."],
	3: ["Acto III", "El último rezo",
		"La iglesia abrió sus puertas. El campanario, sellado por veinte años, espera. Ya puedes acusar."],
}

var _root: Control
var _title: Label
var _name: Label
var _clock: Label
var _text: Label
var _tween: Tween


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	_root.visible = false
	add_child(_root)
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.01, 0.04, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var col: VBoxContainer = UiKit.centered_column(_root, 12)
	(col.get_parent() as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UiKit.label("", 26, UiKit.MUTED)
	_name = UiKit.label("", 48, UiKit.ACCENT)
	_clock = UiKit.label("", 22, UiKit.VIOLET.lightened(0.35))
	_text = UiKit.label("", 21)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(760, 0)
	for l: Label in [_title, _name, _clock, _text]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)


func is_showing() -> bool:
	return _root.visible


func shown_text() -> String:
	return "%s · %s" % [_title.text, _name.text] if _root.visible else ""


func show_act(act: int, clock_text: String) -> void:
	var a: Array = ACTS.get(act, [])
	if a.is_empty():
		return
	_title.text = a[0]
	_name.text = a[1]
	_clock.text = clock_text
	_text.text = a[2]
	_root.visible = true
	_root.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, 0.8)
	_tween.tween_interval(HOLD)
	_tween.tween_callback(hide_card)


func hide_card() -> void:
	if not _root.visible:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, 0.6)
	_tween.tween_callback(func() -> void: _root.visible = false)


func _input(event: InputEvent) -> void:
	if not _root.visible or _root.modulate.a < 0.5:
		return
	var key: bool = event is InputEventKey and (event as InputEventKey).pressed
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if key or click:
		hide_card()  # no se marca como atendido: la tecla también sirve al juego
