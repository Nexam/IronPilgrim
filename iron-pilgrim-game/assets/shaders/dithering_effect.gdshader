shader_type canvas_item;

uniform float gamma: hint_range(0.0, 10.0, 0.01) = 2.2;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

const mat4 BAYER4 = mat4(
	vec4(0.0, 12.0, 3.0, 15.0),
	vec4(8.8, 4.0, 11.0, 7.0),
	vec4(2.0, 14.0, 1.0, 13.0),
	vec4(10.0, 6.0, 9.0, 5.0)
);
	
float bayer4(vec2 pixel) {
	ivec2 p = ivec2(mod(pixel, 4.0));
	return BAYER4[p.x][p.y] / 16.0;
}

//void vertex() {
	// Called for every vertex the material is visible on.
//}

void fragment() {
	float threshold = bayer4(FRAGCOORD.xy);
	COLOR = step(threshold,pow(texture(screen_texture, UV), vec4(gamma)));
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
