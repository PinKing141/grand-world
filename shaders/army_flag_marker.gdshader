shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D shield_atlas : source_color, filter_linear, repeat_disable;
uniform vec2 atlas_grid = vec2(32.0, 32.0);

varying float atlas_coordinate;
varying float marker_alpha;

void vertex() {
	atlas_coordinate = INSTANCE_CUSTOM.r;
	marker_alpha = COLOR.a;
}

void fragment() {
	float slot_count = atlas_grid.x * atlas_grid.y;
	float atlas_index = floor(clamp(atlas_coordinate, 0.0, 0.999999) * slot_count);
	vec2 cell = vec2(mod(atlas_index, atlas_grid.x), floor(atlas_index / atlas_grid.x));
	vec2 texel_size = 1.0 / vec2(textureSize(shield_atlas, 0));
	vec2 cell_min = cell / atlas_grid + texel_size * 0.5;
	vec2 cell_max = (cell + vec2(1.0)) / atlas_grid - texel_size * 0.5;
	vec2 atlas_uv = mix(cell_min, cell_max, UV);
	vec4 shield = texture(shield_atlas, atlas_uv);
	ALBEDO = shield.rgb;
	ALPHA = shield.a * marker_alpha;
}
