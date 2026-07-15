shader_type canvas_item;
render_mode unshaded;

uniform vec4 cool_tint : source_color = vec4(0.025, 0.045, 0.075, 0.09);
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.36;
uniform float lower_darkness : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float vignette = smoothstep(0.28, 1.22, length(centered * vec2(0.78, 1.0)));
	float lower_fade = smoothstep(0.48, 1.0, UV.y);
	float subtle_weave = (sin(UV.x * 1500.0) + sin(UV.y * 940.0)) * 0.006;
	float alpha = clamp(cool_tint.a + vignette * edge_darkness + lower_fade * lower_darkness + subtle_weave, 0.0, 0.72);
	COLOR = vec4(cool_tint.rgb, alpha);
}
