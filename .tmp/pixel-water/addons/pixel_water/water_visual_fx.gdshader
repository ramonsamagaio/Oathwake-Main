shader_type canvas_item;
render_mode unshaded, world_vertex_coords;

// One screen read handles tint, depth darkening and a very small mipmap blur.
// God rays are procedural, so the effect needs no animated textures or 2D lights.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec4 shallow_tint : source_color = vec4(0.78, 0.94, 1.06, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.68, 0.86, 1.02, 1.0);
uniform float base_tint_strength : hint_range(0.0, 0.5) = 0.16;
uniform float deep_tint_extra : hint_range(0.0, 0.3) = 0.06;
uniform float depth_darkening : hint_range(0.0, 0.25) = 0.065;
uniform float max_blur_lod : hint_range(0.0, 2.0) = 0.62;

uniform vec4 ray_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float ray_strength : hint_range(0.0, 0.5) = 0.13;
uniform float ray_pixel_step : hint_range(1.0, 16.0) = 6.0;
uniform float ray_period_px : hint_range(80.0, 520.0) = 285.0;
uniform float ray_speed : hint_range(0.0, 2.0) = 0.20;

varying vec2 water_world_pos;

const float TAU = 6.28318530718;

void vertex() {
    water_world_pos = VERTEX;
}

void fragment() {
    // Vertex COLOR channels are used as a tiny per-column data stream:
    // R = normalized depth inside this water column (0 surface, 1 bottom)
    // G = whether this connected body is large enough for light shafts
    // B = absolute column-depth factor (shallow puddles stay almost unaffected)
    float normalized_depth = clamp(COLOR.r, 0.0, 1.0);
    float ray_mask = clamp(COLOR.g, 0.0, 1.0);
    float column_depth_factor = clamp(COLOR.b, 0.0, 1.0);
    float absolute_depth = normalized_depth * column_depth_factor;

    // Mipmap LOD gives a cheap, subtle depth blur. Near the surface it is zero.
    float blur_lod = max_blur_lod * smoothstep(0.18, 1.0, absolute_depth);
    vec4 scene = textureLod(screen_texture, SCREEN_UV, blur_lod);

    vec3 tint_rgb = mix(shallow_tint.rgb, deep_tint.rgb, absolute_depth);
    float tint_amount = base_tint_strength + deep_tint_extra * absolute_depth;
    vec3 rgb = mix(scene.rgb, scene.rgb * tint_rgb, tint_amount);

    // Very restrained depth falloff. This is intentionally not a dramatic fog.
    rgb *= 1.0 - depth_darkening * smoothstep(0.08, 1.0, absolute_depth);

    // Pixel-quantized procedural shafts. Multiple phases keep them from looking
    // like one repeating sine stripe, while slow pulses fade individual rays in/out.
    float px = max(ray_pixel_step, 1.0);
    vec2 p = floor(water_world_pos / px) * px;
    float period = max(ray_period_px, 1.0);

    float diagonal_a = p.x + p.y * 0.24;
    float diagonal_b = p.x * 0.73 - p.y * 0.14;

    float wave_a = sin(diagonal_a * (TAU / period) + TIME * ray_speed);
    float wave_b = sin(diagonal_b * (TAU / (period * 0.72)) - TIME * ray_speed * 0.71 + 1.8);

    float shaft_a = pow(max(wave_a, 0.0), 13.0);
    float shaft_b = pow(max(wave_b, 0.0), 18.0);

    float group_a = floor(p.x / period);
    float group_b = floor(p.x / (period * 0.72));
    float pulse_a = 0.50 + 0.50 * sin(TIME * 0.47 + group_a * 1.91);
    float pulse_b = 0.50 + 0.50 * sin(TIME * 0.39 + group_b * 2.37 + 0.8);

    float rays = (shaft_a * pulse_a + shaft_b * pulse_b * 0.72) * ray_mask;
    float ray_depth_fade = mix(1.0, 0.48, smoothstep(0.48, 1.0, normalized_depth));
    rgb += ray_color.rgb * rays * ray_strength * ray_depth_fade;

    COLOR = vec4(rgb, 1.0);
}
