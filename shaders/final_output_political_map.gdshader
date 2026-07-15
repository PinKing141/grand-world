shader_type spatial;
render_mode unshaded;
uniform sampler2D subview_image : source_color, filter_linear;
uniform sampler2D ocean_texture : source_color, filter_linear;
uniform sampler2D terrain_class_map : filter_nearest;
// Physical ground layer baked by tools/terrain/build_terrain_base.py. Every
// colour mapmode (political now; religion/ideology later) is a wash over it.
uniform sampler2D terrain_base_map : source_color, filter_linear;
uniform sampler2D height_map : filter_linear;
uniform sampler2D lookup_map : filter_nearest, repeat_disable;
uniform sampler2D owner_color_map : source_color, filter_nearest, repeat_disable;
// Deterministic full-resolution derivative of canonical water provinces.
// White means inland lake; black means ocean or non-water.
uniform sampler2D lake_mask : filter_nearest;
uniform sampler2D realm_color_map : filter_nearest;
uniform sampler2D subject_cue_map : filter_nearest;
uniform sampler2D control_state_map : filter_nearest;
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
uniform sampler2D province_edge_lattice : filter_nearest, repeat_disable;
uniform sampler2D noise_texture : filter_linear;

// Zoom-normalized screen-space border hierarchy. 0 is the widest strategic
// view and 1 is the closest regional view. Widths are measured in output
// pixels from SDF derivatives, so camera zoom never makes them balloon.
uniform float strategic_zoom : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform vec4 sovereign_border_color : source_color = vec4(0.075, 0.058, 0.045, 1.0);
uniform vec4 subject_border_color : source_color = vec4(0.29, 0.22, 0.14, 1.0);
uniform vec4 province_border_color : source_color = vec4(0.10, 0.085, 0.07, 1.0);
uniform float province_border_strategic_width : hint_range(0.5, 2.0, 0.05) = 0.80;
uniform float province_border_close_width : hint_range(0.8, 3.0, 0.05) = 1.45;
uniform float province_border_opacity : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform vec4 coast_border_color : source_color = vec4(0.018, 0.035, 0.055, 1.0);
uniform vec4 lake_surface_color : source_color = vec4(0.045, 0.14, 0.19, 1.0);
uniform vec4 lake_border_color : source_color = vec4(0.045, 0.085, 0.105, 1.0);
uniform vec4 occupation_color : source_color = vec4(0.48, 0.24, 0.58, 1.0);
uniform vec4 player_occupation_color : source_color = vec4(0.55, 0.28, 0.70, 1.0);
uniform vec4 enemy_occupation_color : source_color = vec4(0.84, 0.35, 0.16, 1.0);
uniform bool war_goal_enabled = false;
uniform vec2 war_goal_province = vec2(-1.0);
uniform vec4 war_goal_color : source_color = vec4(1.0, 0.78, 0.12, 1.0);
// 0 normal, 1 red-green safe, 2 blue-yellow safe, 3 high contrast.
uniform int accessibility_profile = 0;
uniform float accessibility_pattern_boost : hint_range(1.0, 2.0, 0.05) = 1.0;


uniform float noise_threshold : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float min_center : hint_range(0.0, 0.16, 0.01) = 0.16;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.0;


bool province_matches(vec2 encoded_id, vec2 target_id)
{
	vec2 tolerance = vec2(0.5 / 255.0);
	return all(lessThanEqual(abs(encoded_id - target_id), tolerance));
}


vec3 apply_accessibility_profile(vec3 color)
{
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	if (accessibility_profile == 1)
	{
		// Rotate the ambiguous red/green opponent channel toward an
		// orange/blue channel while retaining luminance and authored variation.
		float red_green = color.r - color.g;
		float blue = color.b - luma;
		vec3 safe = vec3(
			luma + red_green * 0.34 - blue * 0.08,
			luma + red_green * 0.10 + blue * 0.12,
			luma - red_green * 0.44 + blue * 0.48
		);
		return clamp(mix(color, safe, 0.58), vec3(0.0), vec3(1.0));
	}
	if (accessibility_profile == 2)
	{
		// Move blue/yellow separation toward magenta/green and reinforce luma.
		float blue_yellow = color.b - 0.5 * (color.r + color.g);
		float red_green = color.r - color.g;
		vec3 safe = vec3(
			luma - blue_yellow * 0.42 + red_green * 0.18,
			luma + blue_yellow * 0.34 - red_green * 0.12,
			luma + red_green * 0.36
		);
		return clamp(mix(color, safe, 0.56), vec3(0.0), vec3(1.0));
	}
	if (accessibility_profile == 3)
	{
		float contrast_luma = smoothstep(0.16, 0.84, luma);
		vec3 chroma = color - vec3(luma);
		return clamp(vec3(contrast_luma) + chroma * 0.72, vec3(0.0), vec3(1.0));
	}
	return color;
}

float data_changed(vec4 first, vec4 second)
{
	return step(0.012, distance(first.rgb, second.rgb) + abs(first.a - second.a));
}

vec4 realm_at(vec2 uv)
{
	vec2 encoded_id = texture(lookup_map, clamp(uv, vec2(0.0), vec2(1.0))).rg;
	return texture(realm_color_map, encoded_id);
}

float screen_border_mask(float distance_value, float edge_value, float width_pixels)
{
	float derivative_width = max(fwidth(distance_value), 0.00001);
	float distance_pixels = max(distance_value - edge_value, 0.0) / derivative_width;
	float half_width = max(width_pixels * 0.5, 0.05);
	return 1.0 - smoothstep(max(half_width - 0.7, 0.0), half_width + 0.7, distance_pixels);
}

vec3 classify_canonical_edge(ivec2 first_pixel, ivec2 second_pixel, ivec2 map_size)
{
	first_pixel = clamp(first_pixel, ivec2(0), map_size - ivec2(1));
	second_pixel = clamp(second_pixel, ivec2(0), map_size - ivec2(1));
	vec2 first_id = texelFetch(lookup_map, first_pixel, 0).rg;
	vec2 second_id = texelFetch(lookup_map, second_pixel, 0).rg;
	float first_terrain = texelFetch(terrain_class_map, first_pixel, 0).r;
	float second_terrain = texelFetch(terrain_class_map, second_pixel, 0).r;
	float first_water = 1.0 - step(0.17, first_terrain);
	float second_water = 1.0 - step(0.17, second_terrain);
	float coast = abs(first_water - second_water);
	if (coast > 0.5 || first_water > 0.5)
	{
		return vec3(0.0, 0.0, coast);
	}
	vec4 first_owner = texture(owner_color_map, first_id);
	vec4 second_owner = texture(owner_color_map, second_id);
	vec4 first_realm = texture(realm_color_map, first_id);
	vec4 second_realm = texture(realm_color_map, second_id);
	float owner_change = data_changed(first_owner, second_owner);
	float realm_change = data_changed(first_realm, second_realm);
	return vec3(owner_change * (1.0 - realm_change), owner_change * realm_change, 0.0);
}


// Returns the nearest exact screen-pixel distance to: any province edge,
// internal-realm/subject edge, sovereign edge, and coast edge. Classification
// occurs on the undilated adjacency; visual widths are applied afterwards.
vec4 canonical_edge_distances_pixels(vec2 uv)
{
	ivec2 map_size = textureSize(province_edge_lattice, 0);
	vec2 source_position = clamp(uv, vec2(0.0), vec2(0.999999)) * vec2(map_size);
	ivec2 cell = clamp(ivec2(floor(source_position)), ivec2(0), map_size - ivec2(1));
	vec2 local_position = source_position - vec2(cell);
	vec2 source_texels_per_pixel = max(fwidth(source_position), vec2(0.0001));
	vec2 current_edges = texelFetch(province_edge_lattice, cell, 0).rg;
	vec4 distances = vec4(100000.0);
	if (current_edges.r > 0.5)
	{
		float edge_distance = local_position.x / source_texels_per_pixel.x;
		vec3 edge_class = classify_canonical_edge(cell - ivec2(1, 0), cell, map_size);
		distances.x = min(distances.x, edge_distance);
		if (edge_class.x > 0.5) distances.y = min(distances.y, edge_distance);
		if (edge_class.y > 0.5) distances.z = min(distances.z, edge_distance);
		if (edge_class.z > 0.5) distances.w = min(distances.w, edge_distance);
	}
	if (current_edges.g > 0.5)
	{
		float edge_distance = local_position.y / source_texels_per_pixel.y;
		vec3 edge_class = classify_canonical_edge(cell - ivec2(0, 1), cell, map_size);
		distances.x = min(distances.x, edge_distance);
		if (edge_class.x > 0.5) distances.y = min(distances.y, edge_distance);
		if (edge_class.y > 0.5) distances.z = min(distances.z, edge_distance);
		if (edge_class.z > 0.5) distances.w = min(distances.w, edge_distance);
	}
	if (cell.x + 1 < map_size.x)
	{
		float right_edge = texelFetch(province_edge_lattice, cell + ivec2(1, 0), 0).r;
		if (right_edge > 0.5)
		{
			float edge_distance = (1.0 - local_position.x) / source_texels_per_pixel.x;
			vec3 edge_class = classify_canonical_edge(cell, cell + ivec2(1, 0), map_size);
			distances.x = min(distances.x, edge_distance);
			if (edge_class.x > 0.5) distances.y = min(distances.y, edge_distance);
			if (edge_class.y > 0.5) distances.z = min(distances.z, edge_distance);
			if (edge_class.z > 0.5) distances.w = min(distances.w, edge_distance);
		}
	}
	if (cell.y + 1 < map_size.y)
	{
		float bottom_edge = texelFetch(province_edge_lattice, cell + ivec2(0, 1), 0).g;
		if (bottom_edge > 0.5)
		{
			float edge_distance = (1.0 - local_position.y) / source_texels_per_pixel.y;
			vec3 edge_class = classify_canonical_edge(cell, cell + ivec2(0, 1), map_size);
			distances.x = min(distances.x, edge_distance);
			if (edge_class.x > 0.5) distances.y = min(distances.y, edge_distance);
			if (edge_class.y > 0.5) distances.z = min(distances.z, edge_distance);
			if (edge_class.z > 0.5) distances.w = min(distances.w, edge_distance);
		}
	}
	return distances;
}


float canonical_province_border_mask(float distance_pixels, float width_pixels)
{
	float half_width = max(width_pixels * 0.5, 0.05);
	return 1.0 - smoothstep(max(half_width - 0.5, 0.0), half_width + 0.5, distance_pixels);
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
	float lake_water = texture(lake_mask, UV).r;
	vec3 terrain_rgb = texture(ocean_texture, UV).rgb;
	vec3 ground_rgb = texture(terrain_base_map, UV).rgb;
	vec2 encoded_province = texture(lookup_map, UV).rg;

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
		// Keep coast water in the same restrained navy family as the open sea.
		// The former blue multiplier produced a neon/cyan rim around land.
		vec3 ocean_surface = terrain_rgb * vec3(0.66, 0.78, 0.90);
		vec3 open_water = mix(deep_ocean_color.rgb, ocean_surface, 0.56);
		vec3 inland_water = mix(lake_surface_color.rgb, ocean_surface, 0.16);
		s = vec4(mix(open_water, inland_water, lake_water), 1.0);
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
		if (map_mode == 0)
		{
			vec2 subject_cue = texture(subject_cue_map, encoded_province).rg;
			float subject_active = step(0.5, subject_cue.r);
			float diagonal_a = smoothstep(0.76, 0.96, 0.5 + 0.5 * sin((ip.x + ip.y) * 6.2831853 / 24.0));
			float diagonal_b = smoothstep(0.76, 0.96, 0.5 + 0.5 * sin((ip.x - ip.y) * 6.2831853 / 24.0));
			float appanage_dots = smoothstep(0.72, 0.94, 0.5 + 0.5 * sin(ip.x * 6.2831853 / 18.0))
				* smoothstep(0.72, 0.94, 0.5 + 0.5 * sin(ip.y * 6.2831853 / 18.0));
			float vassal_pattern = mix(appanage_dots, diagonal_a, smoothstep(0.32, 0.44, subject_cue.g));
			float subject_pattern = mix(vassal_pattern, max(diagonal_a, diagonal_b), smoothstep(0.62, 0.72, subject_cue.g));
			s.rgb *= 1.0 - subject_active * subject_pattern * 0.035 * accessibility_pattern_boost;
		}
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

	// Dynamic border hierarchy. The fill subviewport deliberately contains no
	// baked borders; these masks are evaluated at final output resolution.
	if (map_mode != 2 && terrain_class >= 0.17)
	{
		vec4 canonical_edge_distances = canonical_edge_distances_pixels(UV);
		float province_edge_distance = canonical_edge_distances.x;
		float country_width = mix(1.35, 2.35, strategic_zoom);
		float subject_width = mix(0.85, 1.55, strategic_zoom);
		float coast_width = mix(1.5, 2.35, strategic_zoom);
		float province_width = mix(province_border_strategic_width, province_border_close_width, strategic_zoom);
		float province_visibility = smoothstep(0.16, 0.46, strategic_zoom);
		float mode_border_factor = map_mode == 0 ? 1.0 : 0.42;
		float exact_hierarchy_weight = smoothstep(0.12, 0.32, strategic_zoom);
		float country_df = 1.0;
		float country_mask = 0.0;
		if (exact_hierarchy_weight < 0.999)
		{
			country_df = texture(distance_field, UV).r;
			country_mask = screen_border_mask(country_df, 0.10, country_width);
		}

		float province_mask = canonical_province_border_mask(province_edge_distance, province_width);
		s.rgb = mix(s.rgb, province_border_color.rgb, province_mask * province_visibility * province_border_opacity * mode_border_factor);

		float exact_subject_mask = canonical_province_border_mask(canonical_edge_distances.y, subject_width);
		float exact_sovereign_mask = canonical_province_border_mask(canonical_edge_distances.z, country_width);
		float exact_coast_mask = canonical_province_border_mask(canonical_edge_distances.w, coast_width);
		if (max(country_mask, max(exact_subject_mask, max(exact_sovereign_mask, exact_coast_mask))) > 0.001)
		{
			vec2 classification_texel = 6.0 / vec2(textureSize(lookup_map, 0));
			vec2 coast_texel = 3.0 / vec2(textureSize(terrain_class_map, 0));
			float water_nearby = 1.0 - step(0.17, min(
				min(texture(terrain_class_map, clamp(UV - vec2(coast_texel.x, 0.0), vec2(0.0), vec2(1.0))).r, texture(terrain_class_map, clamp(UV + vec2(coast_texel.x, 0.0), vec2(0.0), vec2(1.0))).r),
				min(texture(terrain_class_map, clamp(UV - vec2(0.0, coast_texel.y), vec2(0.0), vec2(1.0))).r, texture(terrain_class_map, clamp(UV + vec2(0.0, coast_texel.y), vec2(0.0), vec2(1.0))).r)
			));
			float lake_nearby = max(
				max(texture(lake_mask, clamp(UV - vec2(coast_texel.x, 0.0), vec2(0.0), vec2(1.0))).r, texture(lake_mask, clamp(UV + vec2(coast_texel.x, 0.0), vec2(0.0), vec2(1.0))).r),
				max(texture(lake_mask, clamp(UV - vec2(0.0, coast_texel.y), vec2(0.0), vec2(1.0))).r, texture(lake_mask, clamp(UV + vec2(0.0, coast_texel.y), vec2(0.0), vec2(1.0))).r)
			) * water_nearby;
			float ocean_nearby = water_nearby * (1.0 - lake_nearby);
			float subject_coverage = exact_subject_mask;
			float sovereign_coverage = exact_sovereign_mask;
			float coast_coverage = exact_coast_mask;
			if (exact_hierarchy_weight < 0.999)
			{
				vec4 realm_center = texture(realm_color_map, encoded_province);
				float realm_edge = max(
					max(data_changed(realm_center, realm_at(UV - vec2(classification_texel.x, 0.0))), data_changed(realm_center, realm_at(UV + vec2(classification_texel.x, 0.0)))),
					max(data_changed(realm_center, realm_at(UV - vec2(0.0, classification_texel.y))), data_changed(realm_center, realm_at(UV + vec2(0.0, classification_texel.y))))
				);
				float subject_edge = (1.0 - realm_edge) * (1.0 - water_nearby);
				float sovereign_edge = realm_edge * (1.0 - water_nearby);
				float subject_mask = screen_border_mask(country_df, 0.10, subject_width);
				float coast_mask = screen_border_mask(country_df, 0.10, coast_width);
				subject_coverage = mix(subject_mask * subject_edge, exact_subject_mask, exact_hierarchy_weight);
				sovereign_coverage = mix(country_mask * sovereign_edge, exact_sovereign_mask, exact_hierarchy_weight);
				coast_coverage = mix(coast_mask * water_nearby, exact_coast_mask, exact_hierarchy_weight);
			}
			s.rgb = mix(s.rgb, subject_border_color.rgb, subject_coverage * 0.72 * mode_border_factor);
			s.rgb = mix(s.rgb, sovereign_border_color.rgb, sovereign_coverage * 0.96 * mode_border_factor);
			s.rgb = mix(s.rgb, coast_border_color.rgb, coast_coverage * ocean_nearby * 0.96);
			s.rgb = mix(s.rgb, lake_border_color.rgb, coast_coverage * lake_nearby * 0.88);
		}

		vec3 control_state = texture(control_state_map, encoded_province).rgb;
		if (map_mode == 0 && control_state.r > 0.5)
		{
			vec3 active_occupation_color = occupation_color.rgb;
			if (control_state.g > 0.5)
				active_occupation_color = player_occupation_color.rgb;
			else if (control_state.b > 0.5)
				active_occupation_color = enemy_occupation_color.rgb;
			float occupation_outline = canonical_province_border_mask(province_edge_distance, mix(2.0, 3.0, strategic_zoom));
			float occupation_hatch = 0.5 + 0.5 * sin((ip.x + ip.y) * 6.2831853 / 18.0);
			s.rgb = mix(s.rgb, active_occupation_color, occupation_outline * 0.88);
			s.rgb = mix(s.rgb, active_occupation_color, smoothstep(0.62, 0.9, occupation_hatch) * 0.11 * accessibility_pattern_boost);
		}

		// Semantic priority: occupation remains visible beneath the war goal;
		// hover and selection are applied afterwards so direct interaction wins.
		if (map_mode == 0 && war_goal_enabled && province_matches(encoded_province, war_goal_province))
		{
			float goal_outer = canonical_province_border_mask(province_edge_distance, mix(4.4, 5.4, strategic_zoom));
			float goal_gap = canonical_province_border_mask(province_edge_distance, mix(3.0, 3.8, strategic_zoom));
			float goal_inner = canonical_province_border_mask(province_edge_distance, mix(1.4, 2.0, strategic_zoom));
			float outer_ring = clamp(goal_outer - goal_gap, 0.0, 1.0);
			float double_ring = max(outer_ring, goal_inner);
			s.rgb = mix(s.rgb, vec3(0.07, 0.05, 0.025), goal_outer * 0.64);
			s.rgb = mix(s.rgb, war_goal_color.rgb, double_ring * 0.98);
		}

		if (hover_enabled && province_matches(encoded_province, hovered_province))
		{
			float hover_outline = canonical_province_border_mask(province_edge_distance, mix(2.2, 3.2, strategic_zoom));
			s.rgb = mix(s.rgb, hover_color.rgb, hover_outline * 0.96);
		}
		if (selection_enabled && province_matches(encoded_province, selected_province))
		{
			float selection_outline = canonical_province_border_mask(province_edge_distance, mix(2.6, 3.8, strategic_zoom));
			s.rgb = mix(s.rgb, selection_color.rgb, selection_outline);
		}
	}

	ALBEDO = apply_accessibility_profile(s.rgb);
}
