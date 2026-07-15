shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

varying flat int troop_count;
varying vec4 counter_color;

float rectangle(vec2 point, vec2 center, vec2 half_size) {
	vec2 distance_to_edge = abs(point - center) - half_size;
	float signed_distance = max(distance_to_edge.x, distance_to_edge.y);
	return 1.0 - smoothstep(-0.018, 0.018, signed_distance);
}

bool segment_enabled(int digit, int segment) {
	if (segment == 0) { return digit != 1 && digit != 4; }
	if (segment == 1) { return digit != 5 && digit != 6; }
	if (segment == 2) { return digit != 2; }
	if (segment == 3) { return digit != 1 && digit != 4 && digit != 7; }
	if (segment == 4) { return digit == 0 || digit == 2 || digit == 6 || digit == 8; }
	if (segment == 5) { return digit != 1 && digit != 2 && digit != 3 && digit != 7; }
	return digit != 0 && digit != 1 && digit != 7;
}

float draw_digit(vec2 point, int digit) {
	float ink = 0.0;
	if (segment_enabled(digit, 0)) { ink = max(ink, rectangle(point, vec2(0.5, 0.10), vec2(0.27, 0.055))); }
	if (segment_enabled(digit, 1)) { ink = max(ink, rectangle(point, vec2(0.80, 0.30), vec2(0.055, 0.18))); }
	if (segment_enabled(digit, 2)) { ink = max(ink, rectangle(point, vec2(0.80, 0.70), vec2(0.055, 0.18))); }
	if (segment_enabled(digit, 3)) { ink = max(ink, rectangle(point, vec2(0.5, 0.90), vec2(0.27, 0.055))); }
	if (segment_enabled(digit, 4)) { ink = max(ink, rectangle(point, vec2(0.20, 0.70), vec2(0.055, 0.18))); }
	if (segment_enabled(digit, 5)) { ink = max(ink, rectangle(point, vec2(0.20, 0.30), vec2(0.055, 0.18))); }
	if (segment_enabled(digit, 6)) { ink = max(ink, rectangle(point, vec2(0.5, 0.50), vec2(0.27, 0.055))); }
	return ink;
}

void vertex() {
	troop_count = int(round(clamp(INSTANCE_CUSTOM.r, 0.0, 1.0) * 99999.0));
	counter_color = COLOR;
}

void fragment() {
	float border = max(max(step(UV.x, 0.035), step(0.965, UV.x)), max(step(UV.y, 0.07), step(0.93, UV.y)));
	vec3 background = vec3(0.025, 0.055, 0.035);
	vec3 border_color = vec3(0.34, 0.48, 0.22);
	vec3 result = mix(background, border_color, border);

	vec2 digits_uv = (UV - vec2(0.075, 0.14)) / vec2(0.85, 0.72);
	float ink = 0.0;
	if (digits_uv.x >= 0.0 && digits_uv.x < 1.0 && digits_uv.y >= 0.0 && digits_uv.y <= 1.0) {
		int cell = clamp(int(floor(digits_uv.x * 5.0)), 0, 4);
		int divisor = 1;
		if (cell == 0) { divisor = 10000; }
		else if (cell == 1) { divisor = 1000; }
		else if (cell == 2) { divisor = 100; }
		else if (cell == 3) { divisor = 10; }
		int digit = (troop_count / divisor) % 10;
		bool digit_visible = troop_count >= divisor || cell == 4;
		if (digit_visible) {
			ink = draw_digit(vec2(fract(digits_uv.x * 5.0), digits_uv.y), digit);
		}
	}
	result = mix(result, counter_color.rgb, ink);
	ALBEDO = result;
	ALPHA = counter_color.a;
}
