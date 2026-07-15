shader_type canvas_item;
render_mode unshaded;

// Each MultiMesh instance supplies its glyph's normalized atlas rectangle as
// INSTANCE_CUSTOM: xy is the top-left UV and zw is the UV size.
// MSDF channels are signed-distance data, not sRGB colour. Gamma conversion
// moves the 0.5 contour and destroys thin strokes at regional zoom.
uniform sampler2D msdf_atlas : filter_linear;
// Country names are clean atlas ink. Readability comes from LOD/collision
// policy, not a label-sized glow or background plate.
uniform vec4 fill_color : source_color = vec4(0.93, 0.89, 0.75, 0.98);
uniform float msdf_pixel_range = 16.0;

varying flat vec4 glyph_uv_rect;

float median3(float red, float green, float blue) {
	return max(min(red, green), min(max(red, green), blue));
}

float screen_pixel_range(vec2 atlas_uv) {
	vec2 atlas_size = vec2(textureSize(msdf_atlas, 0));
	vec2 unit_range = vec2(msdf_pixel_range) / atlas_size;
	vec2 screen_texture_size = vec2(1.0) / max(fwidth(atlas_uv), vec2(0.000001));
	return max(0.5 * dot(unit_range, screen_texture_size), 1.0);
}

void vertex() {
	glyph_uv_rect = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 atlas_uv = glyph_uv_rect.xy + UV * glyph_uv_rect.zw;
	vec3 sample_value = texture(msdf_atlas, atlas_uv).rgb;
	float signed_distance = median3(sample_value.r, sample_value.g, sample_value.b) - 0.5;
	float screen_distance = screen_pixel_range(atlas_uv) * signed_distance;
	float fill_alpha = clamp(screen_distance + 0.5, 0.0, 1.0);
	if (fill_alpha <= 0.001) {
		discard;
	}
	COLOR = vec4(fill_color.rgb, fill_color.a * fill_alpha);
}
