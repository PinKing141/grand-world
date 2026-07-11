shader_type spatial;
render_mode unshaded;
uniform sampler2D subview_image : source_color, filter_linear;
uniform sampler2D ocean_texture : source_color, filter_linear;
uniform sampler2D terrain_class_map : filter_nearest;
// Physical ground layer baked by tools/terrain/build_terrain_base.py. Every
// colour mapmode (political now; religion/ideology later) is a wash over it.
uniform sampler2D terrain_base_map : source_color, filter_linear;
uniform sampler2D height_map : filter_linear;
uniform sampler2D lookup_map : filter_nearest;
uniform vec4 deep_ocean_color : source_color = vec4(0.018, 0.075, 0.14, 1.0);
// How strongly the active mapmode colour covers the terrain underneath.
uniform float overlay_strength : hint_range(0.0, 1.0, 0.01) = 0.9;
// Ground texture shows through as brightness detail, not as a colour wash,
// so mapmode hues stay saturated instead of turning milky.
uniform float terrain_texture_strength : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float unowned_biome_brightness : hint_range(0.5, 1.25, 0.01) = 0.92;
uniform float impassable_biome_brightness : hint_range(0.5, 1.25, 0.01) = 0.88;
uniform float wasteland_desaturation : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float wasteland_hatch_strength : hint_range(0.0, 0.3, 0.01) = 0.06;
uniform float wasteland_hatch_period : hint_range(4.0, 64.0, 1.0) = 22.0;
// Hillshade emboss derived from the baked elevation texture. This is what
// makes mountain ranges read as raised 3D relief.
uniform float relief_strength : hint_range(0.0, 16.0, 0.1) = 7.0;
uniform float relief_owned_factor : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float relief_max : hint_range(0.0, 0.5, 0.01) = 0.26;
uniform float relief_elevation_lift : hint_range(0.0, 0.5, 0.01) = 0.10;
// True geometric displacement: the terrain mesh's vertices are raised by the
// heightmap, so mountains physically stand off the map plane.
uniform float terrain_height_scale : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform bool hover_enabled = false;
uniform bool selection_enabled = false;
uniform vec2 hovered_province = vec2(-1.0);
uniform vec2 selected_province = vec2(-1.0);
uniform vec4 hover_color : source_color = vec4(1.0, 0.83, 0.25, 1.0);
uniform vec4 selection_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
// 0 = political, 1 = terrain, 2 = debug province IDs.
uniform int map_mode = 0;
// Selected-country territory highlight: matches the country's political
// colour in the subviewport image, so no per-province state is needed.
uniform bool country_selection_enabled = false;
uniform vec4 selected_country_color : source_color = vec4(0.0);

uniform sampler2D distance_field : filter_linear;
uniform sampler2D noise_texture : filter_linear;


uniform float noise_threshold : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float min_center : hint_range(0.0, 0.16, 0.01) = 0.16;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.0;


bool province_matches(vec2 encoded_id, vec2 target_id)
{
	vec2 tolerance = vec2(0.5 / 255.0);
	return all(lessThanEqual(abs(encoded_id - target_id), tolerance));
}
void vertex()
{
	float elevation_sample = texture(height_map, UV).r;
	VERTEX += NORMAL * elevation_sample * terrain_height_scale;
}
void fragment()
{


	// The political lookup is hardware-filtered in one sample. Province and
	// country distance fields draw the authoritative borders, so the former
	// multi-tap diagonal reconstruction only added full-screen GPU cost.
	vec2 tex_size = vec2(textureSize(subview_image, 0));
	vec2 ip = UV * tex_size;

	vec4 original_color = texture(subview_image, UV);
	vec4 s = original_color;


	// The CPU-baked class texture is authoritative. Its red channel encodes:
	// 0 = water, 1/3 = owned land, 2/3 = unowned land, 1 = impassable.
	// This avoids guessing land from texture brightness every frame.
	float terrain_class = texture(terrain_class_map, UV).r;
	vec3 terrain_rgb = texture(ocean_texture, UV).rgb;
	vec3 ground_rgb = texture(terrain_base_map, UV).rgb;

	// Low-cost northwest hillshade. The prior eight-neighbour filter was the
	// largest shader cost while panning; this diagonal gradient preserves the
	// raised-relief read with only two neighbouring samples.
	vec2 height_texel = 1.0 / vec2(textureSize(height_map, 0));
	float elevation = texture(height_map, UV).r;
	float elevation_nw = texture(height_map, UV - height_texel * 2.0).r;
	float elevation_se = texture(height_map, UV + height_texel * 2.0).r;
	float directional = elevation_nw - elevation_se;
	float relief_shade = clamp(directional * relief_strength, -relief_max, relief_max);

	if (terrain_class < 0.17)
	{
		vec3 ocean_surface = terrain_rgb * vec3(0.62, 0.80, 1.12);
		s = vec4(mix(deep_ocean_color.rgb, ocean_surface, 0.78), 1.0);
	}
	else if (terrain_class < 0.50)
	{
		// Mapmode colour over the physical ground, CK/EU-style. The ground
		// contributes shading detail through its luminance so the colour keeps
		// its saturation; only a small amount of true ground colour bleeds in.
		float ground_luma = dot(ground_rgb, vec3(0.2126, 0.7152, 0.0722));
		vec3 mapmode_rgb = s.rgb * mix(1.0, 0.72 + 0.56 * ground_luma, terrain_texture_strength);
		float active_overlay = map_mode == 0 ? overlay_strength : 0.0;
		bool country_matches_selection = country_selection_enabled
			&& all(lessThan(abs(original_color.rgb - selected_country_color.rgb), vec3(0.02)));
		s.rgb = mix(ground_rgb, mapmode_rgb, active_overlay);
		s.rgb *= 1.0 + (relief_shade + elevation * relief_elevation_lift) * relief_owned_factor;
		if (map_mode == 0 && country_matches_selection)
		{
			s.rgb = mix(s.rgb, s.rgb * 1.32 + vec3(0.07), 0.55);
		}
		s.a = 1.0;

		if (noise_strength > 0.001)
		{
			float df_province = texture(distance_field, UV).r;
			float center_factor = smoothstep(min_center, 1.0, df_province);
			float noise = texture(noise_texture, UV).r;
			float noise_factor = smoothstep(noise_threshold, 1.0, noise);
			s.rgb = mix(s.rgb, vec3(1.0), center_factor * noise_factor * noise_strength);
		}
	}
	else if (terrain_class < 0.83)
	{
		s = vec4(ground_rgb * unowned_biome_brightness * (1.0 + relief_shade + elevation * relief_elevation_lift), 1.0);
	}
	else
	{
		// Impassable wasteland: keep the ground colour readable (ice stays icy,
		// mountains stay rocky) but mark it as non-playable with a slight
		// desaturation and a faint diagonal hatch.
		vec3 wasteland = ground_rgb * impassable_biome_brightness * (1.0 + relief_shade + elevation * relief_elevation_lift);
		float wasteland_luma = dot(wasteland, vec3(0.2126, 0.7152, 0.0722));
		wasteland = mix(wasteland, vec3(wasteland_luma), wasteland_desaturation);
		float hatch_wave = sin((ip.x + ip.y) * 6.2831853 / wasteland_hatch_period);
		wasteland *= 1.0 - wasteland_hatch_strength * smoothstep(0.25, 0.9, hatch_wave);
		s = vec4(wasteland, 1.0);
	}

	vec2 encoded_province = texture(lookup_map, UV).rg;
	if (map_mode == 2)
	{
		// Debug view: raw province IDs from the lookup texture.
		s.rgb = terrain_class < 0.17 ? vec3(0.04, 0.07, 0.11) : vec3(encoded_province, 0.35);
	}
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
