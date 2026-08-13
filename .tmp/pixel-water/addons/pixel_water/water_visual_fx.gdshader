shader_type canvas_item;
render_mode unshaded, world_vertex_coords;

// Presentation-only underwater pass. The screen texture is read only inside
// water geometry; physics and the conservative water solver are untouched.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec4 shallow_tint : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.72, 0.86, 0.98, 1.0);
uniform float base_tint_strength : hint_range(0.0, 0.5) = 0.14;
uniform float deep_tint_extra : hint_range(0.0, 0.3) = 0.055;
uniform float depth_darkening : hint_range(0.0, 0.25) = 0.055;
uniform float max_blur_lod : hint_range(0.0, 2.0) = 0.55;

uniform vec4 ray_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float ray_strength : hint_range(0.0, 0.5) = 0.11;
uniform float ray_pixel_step : hint_range(1.0, 16.0) = 6.0;
uniform float ray_period_px : hint_range(80.0, 520.0) = 285.0;
uniform float ray_speed : hint_range(0.0, 2.0) = 0.20;

varying vec2 water_world_pos;
varying vec4 water_data;

void vertex() {
    water_world_pos = VERTEX;
    // CanvasItem COLOR is also the fragment output, so preserve the primitive
    // data explicitly in a varying instead of reading COLOR directly later.
    water_data = COLOR;
}

void fragment() {
    // Primitive data:
    // R = normalized vertical position in this water column (0 surface, 1 bottom)
    // G = connected water body is large enough for light shafts
    // B = absolute column-depth factor
    float normalized_depth = clamp(water_data.r, 0.0, 1.0);
    float ray_mask = clamp(water_data.g, 0.0, 1.0);
    float column_depth_factor = clamp(water_data.b, 0.0, 1.0);
    float absolute_depth = normalized_depth * column_depth_factor;

    // Mipmap LOD is effectively zero near the surface and rises very gently in
    // deep water. This is deliberately restrained for pixel-art readability.
    float blur_lod = max_blur_lod * smoothstep(0.36, 1.0, absolute_depth);
    vec4 scene = textureLod(screen_texture, SCREEN_UV, blur_lod);

    vec3 tint_rgb = mix(shallow_tint.rgb, deep_tint.rgb, absolute_depth);
    float tint_amount = base_tint_strength + deep_tint_extra * absolute_depth;
    vec3 rgb = mix(scene.rgb, scene.rgb * tint_rgb, tint_amount);

    // Very slight optical falloff with depth.
    rgb *= 1.0 - depth_darkening * smoothstep(0.16, 1.0, absolute_depth);

    // Pixel-quantized moving shafts. TAU is a Godot built-in constant, so do not
    // redeclare it here. Multiple phases avoid a single obvious sine stripe.
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
    float ray_depth_fade = mix(1.0, 0.45, smoothstep(0.52, 1.0, normalized_depth));
    rgb += ray_color.rgb * rays * ray_strength * ray_depth_fade;

    COLOR = vec4(clamp(rgb, vec3(0.0), vec3(1.0)), 1.0);
}
