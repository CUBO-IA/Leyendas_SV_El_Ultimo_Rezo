class_name FearOverlay
extends CanvasLayer
## Viñeta del miedo: los bordes de la pantalla se oscurecen y se cierran con el miedo
## del jugador (Night.fear) y laten al ritmo del corazón cuando el miedo es alto.
## Debajo del HUD; no recibe clics.

const SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.25, 1.0));
	float inner = mix(0.62, 0.22, intensity) - pulse * 0.035;
	float v = smoothstep(inner, inner + 0.42, d);
	COLOR = vec4(0.03, 0.0, 0.04, v * mix(0.25, 0.92, intensity));
}
"""

var intensity: float = 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _target: float = 0.0
var _beat: float = 0.0


func _ready() -> void:
	layer = 4
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	set_fear(Night.fear, true)


## fear 0-100. Por debajo de 20 no se nota nada.
func set_fear(fear: float, instant: bool = false) -> void:
	_target = clampf((fear - 20.0) / 80.0, 0.0, 1.0)
	if instant:
		intensity = _target


func _process(delta: float) -> void:
	intensity = move_toward(intensity, _target, delta * 0.5)
	var pulse: float = 0.0
	if intensity > 0.45:
		_beat += delta * lerpf(1.0, 1.6, intensity) * TAU  # mismo ritmo que el latido
		pulse = pow(maxf(0.0, sin(_beat)), 6.0)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("pulse", pulse)
