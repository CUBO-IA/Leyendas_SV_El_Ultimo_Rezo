extends CanvasLayer
## Cambio de escenas con fundido a negro.  await SceneRouter.go(SceneRouter.TOWN)

const TITLE := "res://scenes/title.tscn"
const OPTIONS := "res://scenes/options.tscn"
const TOWN := "res://scenes/town.tscn"

var _rect: ColorRect
var _busy: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func is_busy() -> bool:
	return _busy


func go(path: String, duration: float = 0.35) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade(1.0, duration)
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("No se pudo abrir la escena %s (%s)" % [path, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade(0.0, duration)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _fade(alpha: float, duration: float) -> void:
	var t: Tween = create_tween()
	t.tween_property(_rect, "color:a", alpha, duration)
	await t.finished
