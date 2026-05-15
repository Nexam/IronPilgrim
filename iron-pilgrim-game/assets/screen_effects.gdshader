shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;

uniform float depth_edge_strength = 1.0;
uniform float normal_edge_strength = 1.0;
uniform float edge_threshold : hint_range(0.0, 1.0, 0.001) = 0.08;
uniform vec4 edge_color : source_color = vec4(0.02, 0.018, 0.015, 1.0);

void vertex(){
	POSITION = vec4(VERTEX.xy, .5, .5);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;

	vec3 scene_col = texture(screen_texture, uv).rgb;

	float d0 = texture(depth_texture, uv).r;
	float d1 = texture(depth_texture, uv + vec2(px.x, 0.0)).r;
	float d2 = texture(depth_texture, uv + vec2(-px.x, 0.0)).r;
	float d3 = texture(depth_texture, uv + vec2(0.0, px.y)).r;
	float d4 = texture(depth_texture, uv + vec2(0.0, -px.y)).r;

	float depth_edge = abs(d0 - d1) + abs(d0 - d2) + abs(d0 - d3) + abs(d0 - d4);

	vec3 n0 = texture(normal_texture, uv).xyz * 2.0 - 1.0;
	vec3 n1 = texture(normal_texture, uv + vec2(px.x, 0.0)).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normal_texture, uv + vec2(-px.x, 0.0)).xyz * 2.0 - 1.0;
	vec3 n3 = texture(normal_texture, uv + vec2(0.0, px.y)).xyz * 2.0 - 1.0;
	vec3 n4 = texture(normal_texture, uv + vec2(0.0, -px.y)).xyz * 2.0 - 1.0;

	float normal_edge =
		distance(n0, n1) +
		distance(n0, n2) +
		distance(n0, n3) +
		distance(n0, n4);

	float edge = depth_edge * depth_edge_strength + normal_edge * normal_edge_strength;
	edge = smoothstep(edge_threshold, edge_threshold * 2.0, edge) * edge_color.a;

	ALBEDO = mix(scene_col, edge_color.rgb, edge);
}