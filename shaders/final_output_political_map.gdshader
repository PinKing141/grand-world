shader_type spatial;
render_mode unshaded;
uniform sampler2D subview_image : source_color, filter_linear;
uniform sampler2D ocean_texture : source_color, filter_linear;
uniform sampler2D terrain_class_map : filter_nearest;
uniform sampler2D lookup_map : filter_nearest;
uniform vec4 deep_ocean_color : source_color = vec4(0.018, 0.075, 0.14, 1.0);
uniform vec4 unowned_land_color : source_color = vec4(0.38, 0.40, 0.30, 1.0);
uniform vec4 impassable_color : source_color = vec4(0.24, 0.24, 0.20, 1.0);
uniform float owned_terrain_strength : hint_range(0.0, 0.5, 0.01) = 0.16;
uniform bool hover_enabled = false;
uniform bool selection_enabled = false;
uniform vec2 hovered_province = vec2(-1.0);
uniform vec2 selected_province = vec2(-1.0);
uniform vec4 hover_color : source_color = vec4(1.0, 0.83, 0.25, 1.0);
uniform vec4 selection_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);

uniform sampler2D distance_field : filter_linear;
uniform sampler2D noise_texture : filter_linear;


uniform float noise_threshold : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float min_center : hint_range(0.0, 0.16, 0.01) = 1.0;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.3;


// Parameters
uniform float threshold = 0.00001;
uniform float aa_scale = 17.6;
uniform float base_line_thickness = 0.38197;
const int ML = 0;

// Diagonal line blending logic
bool diag(inout vec4 sum, vec2 ip, vec2 p1, vec2 p2, float thickness)
{
	vec4 v1 = texelFetch(subview_image, ivec2(ip + p1), ML);
	vec4 v2 = texelFetch(subview_image, ivec2(ip + p2), ML);

	if (length(v1 - v2) < threshold)
	{
		vec2 dir = normalize(vec2((p2 - p1).y, -(p2 - p1).x));
		vec2 lp = ip - (floor(ip + p1) + vec2(0.5));
		float l = clamp((thickness - dot(lp, dir)) * aa_scale, 0.0, 1.0);
		sum = mix(sum, v1, l);
		return true;
	}
	return false;
}
bool province_matches(vec2 encoded_id, vec2 target_id)
{
	vec2 tolerance = vec2(0.5 / 255.0);
	return all(lessThanEqual(abs(encoded_id - target_id), tolerance));
}
void fragment()
{


	// Apply smoothing
	vec2 tex_size = vec2(textureSize(subview_image, 0));
	vec2 ip = UV * tex_size;

	vec4 original_color =  texelFetch(subview_image, ivec2(ip), ML);
	vec4 s = original_color;

	if (diag(s, ip, vec2(-1, 0), vec2(0, 1), base_line_thickness))
	{
		diag(s, ip, vec2(-1, 0), vec2(1, 1), 0.25);
		diag(s, ip, vec2(-1, -1), vec2(0, 1), 0.25);
	}
	if (diag(s, ip, vec2(0, 1), vec2(1, 0), base_line_thickness))
	{
		diag(s, ip, vec2(0, 1), vec2(1, -1), 0.25);
		diag(s, ip, vec2(-1, 1), vec2(1, 0), 0.25);
	}
	if (diag(s, ip, vec2(1, 0), vec2(0, -1), base_line_thickness))
	{
		diag(s, ip, vec2(1, 0), vec2(-1, -1), 0.25);
		diag(s, ip, vec2(1, 1), vec2(0, -1), 0.25);
	}
	if (diag(s, ip, vec2(0, -1), vec2(-1, 0), base_line_thickness))
	{
		diag(s, ip, vec2(0, -1), vec2(-1, 1), 0.25);
		diag(s, ip, vec2(1, -1), vec2(-1, 0), 0.25);
	}


	// The CPU-baked class texture is authoritative. Its red channel encodes:
	// 0 = water, 1/3 = owned land, 2/3 = unowned land, 1 = impassable.
	// This avoids guessing land from texture brightness every frame.
	float terrain_class = texture(terrain_class_map, UV).r;
	vec3 terrain_rgb = texture(ocean_texture, UV).rgb;
	float terrain_luma = dot(terrain_rgb, vec3(0.2126, 0.7152, 0.0722));
	float terrain_detail = smoothstep(0.12, 0.82, terrain_luma);

	if (terrain_class < 0.17)
	{
		vec3 ocean_surface = terrain_rgb * vec3(0.62, 0.80, 1.12);
		s = vec4(mix(deep_ocean_color.rgb, ocean_surface, 0.78), 1.0);
	}
	else if (terrain_class < 0.50)
	{
		// Keep country colours readable while allowing a restrained terrain relief.
		float terrain_shade = mix(0.86, 1.10, terrain_detail);
		s.rgb = mix(s.rgb, s.rgb * terrain_shade, owned_terrain_strength);
		s.a = 1.0;

		float df_province = texture(distance_field, UV).r;

		float center_factor = smoothstep(min_center, 1.0, df_province);

		float noise = texture(noise_texture, UV).r;

		float noise_factor = smoothstep(noise_threshold, 1.0, noise); // Wider range = softer

		float white_amount = center_factor * noise_factor * noise_strength;

		s.rgb = mix(s.rgb, vec3(1.0), white_amount);
	}
	else if (terrain_class < 0.83)
	{
		float terrain_shade = mix(0.82, 1.10, terrain_detail);
		s = vec4(unowned_land_color.rgb * terrain_shade, 1.0);
	}
	else
	{
		float terrain_shade = mix(0.76, 1.08, terrain_detail);
		s = vec4(impassable_color.rgb * terrain_shade, 1.0);
	}

	vec2 encoded_province = texture(lookup_map, UV).rg;
	if (hover_enabled && province_matches(encoded_province, hovered_province))
	{
		s.rgb = mix(s.rgb, hover_color.rgb, 0.38);
	}
	if (selection_enabled && province_matches(encoded_province, selected_province))
	{
		s.rgb = mix(s.rgb, selection_color.rgb, 0.58);
	}

	ALBEDO = s.rgb;
}
