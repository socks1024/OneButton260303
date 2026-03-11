shader_type spatial;

// 屏幕空间 深度+法线 边缘检测描边 Shader（后处理方式）
// 使用方式：
//   将此 Shader 材质应用到一个全屏 MeshInstance3D（QuadMesh, size=(2,2)）上
//   该 MeshInstance3D 应作为 Camera3D 的子节点

render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

// 描边颜色
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// 描边线宽（采样偏移像素数）
uniform float outline_width : hint_range(0.5, 5.0, 0.1) = 1.0;
// 深度边缘检测灵敏度（值越小越灵敏）
uniform float depth_threshold : hint_range(0.001, 1.0, 0.001) = 0.05;
// 法线边缘检测灵敏度（值越小越灵敏）
uniform float normal_threshold : hint_range(0.0, 2.0, 0.01) = 0.5;
// 描边开始淡出的距离（米）
uniform float fade_start : hint_range(1.0, 200.0, 1.0) = 30.0;
// 描边完全消失的距离（米）
uniform float fade_end : hint_range(1.0, 500.0, 1.0) = 80.0;

// 深度纹理和法线纹理
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_linear;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// 从深度缓冲采样并转换为线性深度
float get_linear_depth(vec2 uv, mat4 inv_proj) {
	float depth_raw = texture(depth_texture, uv).r;
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = inv_proj * ndc;
	view.xyz /= view.w;
	return -view.z;
}

// 采样视图空间法线
vec3 get_normal(vec2 uv) {
	vec3 n = texture(normal_texture, uv).xyz;
	// Godot 的法线纹理存储格式：xy 在 [0,1] 范围，需要重映射
	n.xy = n.xy * 2.0 - 1.0;
	// 重建 z 分量
	n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0));
	return normalize(n);
}

void vertex() {
	// 全屏四边形：直接使用顶点坐标作为位置，禁用所有变换
	POSITION = vec4(VERTEX.xy, 0.9999, 1.0);
}

void fragment() {
	vec2 pixel_size = vec2(1.0) / VIEWPORT_SIZE;
	vec2 offset = pixel_size * outline_width;

	// 先采样原始屏幕颜色
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;

	// 当前像素的线性深度
	float depth_center = get_linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);

	// Roberts Cross 算子采样四个对角方向
	vec2 uv_tl = SCREEN_UV + vec2(-offset.x, -offset.y); // 左上
	vec2 uv_tr = SCREEN_UV + vec2( offset.x, -offset.y); // 右上
	vec2 uv_bl = SCREEN_UV + vec2(-offset.x,  offset.y); // 左下
	vec2 uv_br = SCREEN_UV + vec2( offset.x,  offset.y); // 右下

	// === 深度边缘检测 ===
	float d_tl = get_linear_depth(uv_tl, INV_PROJECTION_MATRIX);
	float d_tr = get_linear_depth(uv_tr, INV_PROJECTION_MATRIX);
	float d_bl = get_linear_depth(uv_bl, INV_PROJECTION_MATRIX);
	float d_br = get_linear_depth(uv_br, INV_PROJECTION_MATRIX);

	// 对所有5个采样点（中心+四角）计算独立的距离衰减权重
	// 任何一个采样点在远处，都会降低该区域的边缘检测强度
	float w_center = 1.0 - smoothstep(fade_start, fade_end, depth_center);
	float w_tl = 1.0 - smoothstep(fade_start, fade_end, d_tl);
	float w_tr = 1.0 - smoothstep(fade_start, fade_end, d_tr);
	float w_bl = 1.0 - smoothstep(fade_start, fade_end, d_bl);
	float w_br = 1.0 - smoothstep(fade_start, fade_end, d_br);

	// 取所有采样点中最小的权重：只要有一个采样点在远处，就衰减整个区域
	float min_weight = min(w_center, min(min(w_tl, w_tr), min(w_bl, w_br)));
	float distance_fade = min_weight * min_weight;

	// 动态深度阈值：远处深度缓冲精度低，噪声大，需要更高的阈值来过滤
	// 近处(1米)使用原始阈值，远处(fade_end)阈值放大4倍
	float dynamic_depth_th = depth_threshold * (1.0 + 3.0 * smoothstep(0.0, fade_end, depth_center));

	// Roberts Cross: 使用相对深度差（除以中心深度），使远近灵敏度一致
	float rel_diff1 = abs(d_tl - d_br) / max(depth_center, 0.01);
	float rel_diff2 = abs(d_tr - d_bl) / max(depth_center, 0.01);
	float depth_diff = length(vec2(rel_diff1, rel_diff2));
	// smoothstep 替代 step：避免在阈值边界产生硬切换线
	float depth_edge = smoothstep(dynamic_depth_th * 0.5, dynamic_depth_th * 1.5, depth_diff);

	// === 法线边缘检测 ===
	vec3 n_tl = get_normal(uv_tl);
	vec3 n_tr = get_normal(uv_tr);
	vec3 n_bl = get_normal(uv_bl);
	vec3 n_br = get_normal(uv_br);

	// 动态法线阈值：远处法线也有类似的精度问题
	float dynamic_normal_th = normal_threshold * (1.0 + 2.0 * smoothstep(0.0, fade_end, depth_center));

	// Roberts Cross 法线差值
	float normal_diff = length(n_tl - n_br) + length(n_tr - n_bl);
	// smoothstep 替代 step：避免在阈值边界产生硬切换线
	float normal_edge = smoothstep(dynamic_normal_th * 0.5, dynamic_normal_th * 1.5, normal_diff);

	// 合并深度和法线边缘，乘以距离衰减（完全连续，无任何硬切换或布尔判断）
	float edge = max(depth_edge, normal_edge) * distance_fade;

	// 将描边颜色与屏幕颜色混合：边缘处叠加描边色，非边缘处显示原色
	vec3 final_color = mix(screen_color, outline_color.rgb, edge * outline_color.a);
	ALBEDO = final_color;
	ALPHA = 1.0;
}
