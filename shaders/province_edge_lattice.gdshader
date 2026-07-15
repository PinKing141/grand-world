shader_type canvas_item;

// Canonical province boundaries live between source texels. R stores the
// vertical edge between (x - 1, y) and (x, y); G stores the horizontal edge
// between (x, y - 1) and (x, y). Each adjacency is therefore authored once.
uniform sampler2D lookup_map : filter_nearest, repeat_disable;


bool province_id_changed(vec2 first, vec2 second)
{
	vec2 tolerance = vec2(0.5 / 255.0);
	return any(greaterThan(abs(first - second), tolerance));
}


void fragment()
{
	ivec2 map_size = textureSize(lookup_map, 0);
	ivec2 pixel = clamp(ivec2(floor(UV * vec2(map_size))), ivec2(0), map_size - ivec2(1));
	vec2 center_id = texelFetch(lookup_map, pixel, 0).rg;
	float vertical_edge = 0.0;
	float horizontal_edge = 0.0;
	if (pixel.x > 0)
	{
		vertical_edge = province_id_changed(center_id, texelFetch(lookup_map, pixel - ivec2(1, 0), 0).rg) ? 1.0 : 0.0;
	}
	if (pixel.y > 0)
	{
		horizontal_edge = province_id_changed(center_id, texelFetch(lookup_map, pixel - ivec2(0, 1), 0).rg) ? 1.0 : 0.0;
	}
	COLOR = vec4(vertical_edge, horizontal_edge, 0.0, 1.0);
}
