shader_type spatial;

render_mode diffuse_toon, specular_disabled, cull_back;

// Gradient
uniform float gradient_origin_y = 0.0;
uniform float gradient_height = 1.0;
uniform float gradient_contrast = 1.0;

uniform vec4 bottom_color : source_color = vec4(0.97, 0.45, 0.0, 1.0);
uniform vec4 top_color : source_color = vec4(1.0, 0.75, 0.25, 1.0);

// Toon lighting5
uniform vec4 shadow_color : source_color = vec4(0.22, 0.29, 0.45, 1.0);
uniform float toon_edge : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float toon_softness : hint_range(0.0, 1.0, 0.01) = 0.03;

uniform bool use_uv_pattern = false;

uniform sampler2D pattern_texture;
uniform float pattern_scale = 1.0;
uniform float pattern_strength : hint_range(0.0, 1.0, 0.01) = 0.2;

varying float height_gradient;
varying vec3 local_pos;
varying vec3 local_normal;

uniform vec4 cavity_color : source_color = vec4(0.18, 0.12, 0.10, 1.0);
uniform float cavity_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float cavity_power : hint_range(0.1, 50.0, 0.1) = 2.0;
uniform bool invert_cavity = false;

uniform vec4 wear_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float wear_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float wear_threshold : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float wear_softness : hint_range(0.0, 0.5, 0.01) = 0.1;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;

	float safe_height = max(gradient_height, 0.0001);

	float height_value = (VERTEX.y - gradient_origin_y) / safe_height;
	height_value = clamp(height_value, 0.0, 1.0);

	height_gradient = pow(height_value, gradient_contrast);
}


void fragment() {
	vec3 gradient_color = mix(
		bottom_color.rgb,
		top_color.rgb,
		height_gradient
	);
	
	float pattern = 1.0;
	
	if (use_uv_pattern){
		pattern = texture(pattern_texture, UV * pattern_scale).r;
	}
	else{
		vec3 p = local_pos * pattern_scale;
		vec3 n = abs(normalize(local_normal));
		n /= max(n.x + n.y + n.z, 0.0001);

		float tx = texture(pattern_texture, p.yz).r;
		float ty = texture(pattern_texture, p.xz).r;
		float tz = texture(pattern_texture, p.xy).r;

		pattern = tx * n.x + ty * n.y + tz * n.z;
	}
	gradient_color *= mix(1.0, pattern, pattern_strength);
	
	float cavity = 1.0-abs(local_normal.y);
	cavity = clamp(pow(cavity, cavity_power),0.0,1.0);
	if (invert_cavity){
		cavity = 1.0-cavity;
	}
	gradient_color = mix(
		gradient_color,
		cavity_color.rgb,
		cavity * cavity_strength
	);
	
	float upward = clamp(local_normal.y * 0.5 + 0.5, 0.0, 1.0);

	float wear_mask = smoothstep(
		wear_threshold,
		wear_threshold + wear_softness,
		upward
	);

	gradient_color = mix(
		gradient_color,
		wear_color.rgb,
		wear_mask * wear_strength
	);

	ALBEDO = gradient_color;

	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}


void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float light_value = clamp(ndotl * 0.5 + 0.5, 0.0, 1.0);

	float toon_value = smoothstep(
		toon_edge - toon_softness,
		toon_edge + toon_softness,
		light_value
	);

	vec3 ramp_color = mix(shadow_color.rgb, vec3(1.0), toon_value);

	DIFFUSE_LIGHT += ramp_color * ATTENUATION;
}