shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D icon_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(4.0, 3.0);
uniform float icon_index = 0.0;

varying float cluster_count_coordinate;
varying vec4 marker_colour;

float box_coverage(vec2 point, vec2 half_size, float smoothing) {
	vec2 distance = abs(point) - half_size;
	float signed_distance = length(max(distance, vec2(0.0))) + min(max(distance.x, distance.y), 0.0);
	return 1.0 - smoothstep(-smoothing, smoothing, signed_distance);
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

float digit_coverage(vec2 point, int digit) {
	float coverage = 0.0;
	if (segment_enabled(digit, 0)) { coverage = max(coverage, box_coverage(point - vec2(0.0, -0.43), vec2(0.25, 0.055), 0.025)); }
	if (segment_enabled(digit, 1)) { coverage = max(coverage, box_coverage(point - vec2(0.30, -0.22), vec2(0.055, 0.19), 0.025)); }
	if (segment_enabled(digit, 2)) { coverage = max(coverage, box_coverage(point - vec2(0.30, 0.22), vec2(0.055, 0.19), 0.025)); }
	if (segment_enabled(digit, 3)) { coverage = max(coverage, box_coverage(point - vec2(0.0, 0.43), vec2(0.25, 0.055), 0.025)); }
	if (segment_enabled(digit, 4)) { coverage = max(coverage, box_coverage(point - vec2(-0.30, 0.22), vec2(0.055, 0.19), 0.025)); }
	if (segment_enabled(digit, 5)) { coverage = max(coverage, box_coverage(point - vec2(-0.30, -0.22), vec2(0.055, 0.19), 0.025)); }
	if (segment_enabled(digit, 6)) { coverage = max(coverage, box_coverage(point, vec2(0.25, 0.055), 0.025)); }
	return coverage;
}

void vertex() {
	cluster_count_coordinate = INSTANCE_CUSTOM.g;
	marker_colour = COLOR;
}

void fragment() {
	float slot_count = atlas_grid.x * atlas_grid.y;
	float slot = clamp(icon_index, 0.0, slot_count - 1.0);
	vec2 cell = vec2(mod(slot, atlas_grid.x), floor(slot / atlas_grid.x));
	vec4 icon = texture(icon_atlas, (cell + UV) / atlas_grid);
	float luminance = dot(icon.rgb, vec3(0.299, 0.587, 0.114));
	vec3 dark_ink = vec3(0.055, 0.043, 0.032);
	vec3 base_colour = mix(dark_ink, marker_colour.rgb, smoothstep(0.18, 0.78, luminance));
	float alpha = icon.a * marker_colour.a;

	int cluster_count = int(floor(cluster_count_coordinate * 255.0 + 0.5));
	if (cluster_count > 1) {
		vec2 badge_point = (UV - vec2(0.79, 0.21)) / 0.19;
		float badge = 1.0 - smoothstep(0.88, 1.0, length(badge_point));
		float badge_inner = 1.0 - smoothstep(0.70, 0.82, length(badge_point));
		vec3 badge_colour = mix(dark_ink, vec3(0.91, 0.70, 0.25), badge_inner);
		int shown_count = min(cluster_count, 99);
		float digits = 0.0;
		if (shown_count < 10) {
			digits = digit_coverage(badge_point * 1.35, shown_count);
		} else {
			int tens = shown_count / 10;
			int ones = shown_count - tens * 10;
			digits = max(
				digit_coverage((badge_point - vec2(-0.29, 0.0)) * vec2(1.65, 1.35), tens),
				digit_coverage((badge_point - vec2(0.29, 0.0)) * vec2(1.65, 1.35), ones)
			);
		}
		badge_colour = mix(badge_colour, dark_ink, digits);
		base_colour = mix(base_colour, badge_colour, badge);
		alpha = max(alpha, badge * marker_colour.a);
	}
	ALBEDO = base_colour;
	ALPHA = alpha;
}
