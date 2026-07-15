shader_type canvas_item;
render_mode unshaded;
uniform vec4 ocean_color : source_color;
const float EPSILON = 0.0001;
uniform sampler2D country_distance_field : source_color, filter_linear;

uniform sampler2D lookup_map : filter_nearest;
uniform sampler2D color_map : source_color, filter_nearest;
uniform sampler2D realm_color_map : source_color, filter_nearest;
uniform sampler2D subject_cue_map : filter_nearest;
uniform float edge_smoothness : hint_range(0.0, 2., 0.001) = 0.01;
uniform float edge_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float gradient_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float edge_size : hint_range(0.0, 1.0, 0.001) = 0.1;
uniform vec4 subject_border_color : source_color = vec4(0.25, 0.20, 0.14, 1.0);
uniform float subject_border_opacity : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform vec4 coastline_color : source_color = vec4(0.018, 0.045, 0.075, 1.0);
uniform float coastline_opacity : hint_range(0.0, 1.0, 0.01) = 0.78;
// Runtime borders are drawn in the final screen-space shader so they retain
// stable pixel widths across zoom bands. Keep this switch for editor bakes.
uniform bool bake_borders = true;
bool colors_equal(vec4 a, vec4 b)
{
	return all(lessThan(abs(a - b), vec4(EPSILON)));
}
vec4 get_province_color(vec2 uv)
{
	vec4 lookup = texture(lookup_map, uv);
	vec2 province_id = lookup.rg;
	return texture(color_map, province_id);
}
vec4 get_realm_color(vec2 uv)
{
	vec2 province_id = texture(lookup_map, uv).rg;
	return texture(realm_color_map, province_id);
}
float color_changed(vec4 first, vec4 second)
{
	return step(0.015, distance(first.rgb, second.rgb) + abs(first.a - second.a));
}

void fragment()
{
	vec2 uv = UV;
	float df = texture(country_distance_field, UV).r;

	vec4 province_color = get_province_color(uv);
	vec4 realm_color = get_realm_color(uv);
	vec2 map_texel = 2.0 / vec2(textureSize(lookup_map, 0));
	vec2 left_uv = clamp(uv - vec2(map_texel.x, 0.0), vec2(0.0), vec2(1.0));
	vec2 right_uv = clamp(uv + vec2(map_texel.x, 0.0), vec2(0.0), vec2(1.0));
	vec2 up_uv = clamp(uv - vec2(0.0, map_texel.y), vec2(0.0), vec2(1.0));
	vec2 down_uv = clamp(uv + vec2(0.0, map_texel.y), vec2(0.0), vec2(1.0));
	vec4 owner_left = get_province_color(left_uv);
	vec4 owner_right = get_province_color(right_uv);
	vec4 owner_up = get_province_color(up_uv);
	vec4 owner_down = get_province_color(down_uv);
	float owner_edge = max(max(color_changed(province_color, owner_left), color_changed(province_color, owner_right)), max(color_changed(province_color, owner_up), color_changed(province_color, owner_down)));
	float realm_edge = max(max(color_changed(realm_color, get_realm_color(left_uv)), color_changed(realm_color, get_realm_color(right_uv))), max(color_changed(realm_color, get_realm_color(up_uv)), color_changed(realm_color, get_realm_color(down_uv))));
	float coast_edge = max(
		max(colors_equal(owner_left, ocean_color) ? 1.0 : 0.0, colors_equal(owner_right, ocean_color) ? 1.0 : 0.0),
		max(colors_equal(owner_up, ocean_color) ? 1.0 : 0.0, colors_equal(owner_down, ocean_color) ? 1.0 : 0.0));
	float internal_realm_edge = owner_edge * (1.0 - realm_edge);
	vec3 hierarchy_border = mix(border_color.rgb, subject_border_color.rgb, internal_realm_edge);
	float hierarchy_opacity = mix(1.0, subject_border_opacity, internal_realm_edge);
	if (!colors_equal(province_color, ocean_color) && coast_edge > 0.5)
	{
		hierarchy_border = coastline_color.rgb;
		hierarchy_opacity = coastline_opacity;
	}

	float gradient_factor = smoothstep(edge_threshold - edge_smoothness,
			edge_threshold + edge_smoothness,
			df);
	float country_width = max(edge_smoothness, fwidth(df) * 0.75);
	float country_border_mask = 1.0 - smoothstep(
			edge_size - country_width,
			edge_size + country_width,
			df);
	vec3 gradient_color = mix(hierarchy_border, province_color.rgb, gradient_factor);
	vec3 final_color = bake_borders ? mix(province_color.rgb, gradient_color, gradient_strength) : province_color.rgb;
	final_color = mix(final_color, hierarchy_border, country_border_mask * hierarchy_opacity * owner_edge * (bake_borders ? 1.0 : 0.0));
	vec4 output = vec4(final_color.rgb, province_color.a);
	if (colors_equal(province_color, ocean_color)) {
			output = ocean_color;
	}
	COLOR = output;

}
