class_name FogOverlay
extends CanvasLayer
## Niebla que se arrastra por la pantalla (ruido fractal que se desplaza). Aparece en el
## pueblo desde el Acto II y siempre en el cementerio; ExploreBase pone la densidad.
## Debajo de la viñeta del miedo y del HUD; no recibe clics.

const SHADER := """
shader_type canvas_item;
uniform float density : hint_range(0.0, 1.0) = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 p = UV * vec2(4.0, 2.4);
	float n = fbm(p + vec2(TIME * 0.05, TIME * 0.012));
	n = smoothstep(0.35, 0.85, n + 0.15 * fbm(p * 1.7 - vec2(TIME * 0.03, 0.0)));
	float low = smoothstep(0.1, 0.9, UV.y);  // más espesa abajo, como niebla de suelo
	COLOR = vec4(0.72, 0.74, 0.86, n * density * mix(0.45, 0.85, low));
}
"""

var density: float = 0.0
var _target: float = 0.0
var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 3
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	_apply()


func set_density(value: float, instant: bool = false) -> void:
	_target = clampf(value, 0.0, 1.0)
	if instant:
		density = _target
		_apply()


func _process(delta: float) -> void:
	if not is_equal_approx(density, _target):
		density = move_toward(density, _target, delta * 0.25)
		_apply()


func _apply() -> void:
	_mat.set_shader_parameter("density", density)
	_rect.visible = density > 0.01
