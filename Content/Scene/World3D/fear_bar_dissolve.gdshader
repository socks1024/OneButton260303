shader_type canvas_item;

// 条的主颜色（由脚本在运行时设置）
uniform vec4 bar_color : source_color = vec4(0.0, 1.0, 0.2, 1.0);
// 两端溶解过渡的距离（0.0 ~ 0.5，占条总宽度的比例）
uniform float fade_distance : hint_range(0.0, 0.5, 0.01) = 0.15;
// 溶解浓淡强度（值越大，溶解边缘越"浓"，过渡越陡）
uniform float fade_intensity : hint_range(0.1, 10.0, 0.1) = 3.0;
// 噪声扰动强度（让边缘更像溶解而非线性渐变）
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.3;
// 噪声缩放（控制噪声纹理的密度）
uniform float noise_scale : hint_range(1.0, 50.0, 0.5) = 12.0;
// 条的尺寸（由脚本传入，用于按像素等比采样噪声）
uniform vec2 bar_size = vec2(1000.0, 16.0);

// 简易伪噪声函数（无需外部纹理）
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep 插值

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// 计算距离两端的线性渐变因子
	float left_fade = smoothstep(0.0, fade_distance, UV.x);
	float right_fade = smoothstep(0.0, fade_distance, 1.0 - UV.x);
	float edge_factor = min(left_fade, right_fade);

	// 用像素坐标做等比采样，以高度为基准归一化，避免噪声被拉伸
	vec2 pixel_coord = UV * bar_size;
	vec2 noise_uv = pixel_coord / bar_size.y * noise_scale;
	float noise = value_noise(noise_uv);
	float dissolve = edge_factor - noise_strength * (noise - 0.5);

	// 用强度参数控制过渡的陡峭程度
	float alpha = clamp(pow(clamp(dissolve, 0.0, 1.0), 1.0 / fade_intensity), 0.0, 1.0);

	COLOR = vec4(bar_color.rgb, bar_color.a * alpha);
}
