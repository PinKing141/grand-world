shader_type spatial;
render_mode unshaded;
uniform sampler2D subview_image : source_color, filter_linear;
uniform sampler2D ocean_texture : source_color, filter_linear;
uniform sampler2D lookup_map : filter_nearest;
uniform vec4 ocean_color : source_color;
uniform vec4 wasteland_color : source_color = vec4(0.20, 0.22, 0.20, 1.0);
uniform float terrain_land_threshold : hint_range(0.0, 1.0, 0.01) = 0.34;
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
const float EPSILON = 0.001;

bool colors_equal(vec4 a, vec4 b)
{
	return all(lessThan(abs(a - b), vec4(EPSILON)));
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


	if(s.a < 0.1){
		vec4 terrain_sample = texture(ocean_texture, UV);
		float land_factor = smoothstep(terrain_land_threshold - 0.08, terrain_land_threshold + 0.08, terrain_sample.g);
		vec3 ocean_surface = terrain_sample.rgb * vec3(0.65, 0.82, 1.08);
		s = vec4(mix(ocean_surface, wasteland_color.rgb, land_factor), 1.0);
		}
	else if(colors_equal(s, ocean_color)){
			s = texture(ocean_texture, UV);
		}
	else
	{
	float df_province = texture(distance_field, UV).r;


	float center_factor = smoothstep(min_center, 1.0, df_province);

	float noise = texture(noise_texture, UV).r;

	float noise_factor = smoothstep(noise_threshold, 1.0, noise); // Wider range = softer

	float white_amount = center_factor * noise_factor * noise_strength;

	s.rgb = mix(s.rgb, vec3(1.0), white_amount);
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
