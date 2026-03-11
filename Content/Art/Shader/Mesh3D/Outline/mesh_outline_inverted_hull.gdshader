shader_type spatial;

// 3D 网格描边（视空间外扩）：用于材质的 next_pass
// 相比直接在裁剪空间偏移 XY，更不容易出现宽描边时的撕裂/分离。
render_mode unshaded, cull_front, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width_px : hint_range(1.0, 128.0, 1.0) = 3.0;

void vertex() {
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// 将“像素宽度”换算为当前深度下的“视空间长度”。
	// NDC 的 y 偏移：ndc = (view_y * PROJECTION_MATRIX[1][1]) / -view_z
	float depth = max(-view_pos.z, 0.0001);
	float view_per_pixel = (2.0 * depth) / (VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]);
	float expand = outline_width_px * view_per_pixel;

	view_pos += view_normal * expand;
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
