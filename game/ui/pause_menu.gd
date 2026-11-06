class_name PauseMenu
extends CanvasLayer
## Menú de pausa (Esc): Continuar o volver al título. Pausa el árbol mientras está abierto.

var _root: Control
var _first: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var col: VBoxContainer = UiKit.centered_column(_root, 14)
	var title: Label = UiKit.label("Pausa", 40, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_first = UiKit.button("Continuar", close)
	col.add_child(_first)
	col.add_child(UiKit.button("Volver al título", _to_title))
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	_first.grab_focus()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


func _to_title() -> void:
	close()
	SceneRouter.go(SceneRouter.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
