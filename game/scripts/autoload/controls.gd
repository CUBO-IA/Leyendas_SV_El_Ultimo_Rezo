extends Node
## Registra las acciones de entrada en código (más legible que el InputMap serializado).
##  move_*: WASD y flechas · interact: E · pause: Esc · journal: Tab (A4)

const BINDINGS: Dictionary = {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"pause": [KEY_ESCAPE],
	"journal": [KEY_TAB],
}


func _ready() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in BINDINGS[action]:
			# Tecla física (independiente de la distribución) y lógica (teclas simuladas,
			# escritorio remoto): cualquiera de las dos activa la acción.
			var phys: InputEventKey = InputEventKey.new()
			phys.physical_keycode = key as Key
			InputMap.action_add_event(action, phys)
			var logical: InputEventKey = InputEventKey.new()
			logical.keycode = key as Key
			InputMap.action_add_event(action, logical)
