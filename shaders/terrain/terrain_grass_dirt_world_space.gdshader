shader_type canvas_item;

uniform sampler2D grass_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D dirt_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D edge_overlay : source_color, filter_nearest;

uniform vec2 grass_repeat_pixels = vec2(256.0, 256.0);
uniform vec2 dirt_repeat_pixels = vec2(256.0, 256.0);
uniform vec2 world_offset = vec2(0.0, 0.0);
uniform float edge_shadow_strength : hint_range(0.0, 1.0) = 0.40;
uniform float edge_highlight_strength : hint_range(0.0, 1.0) = 0.08;

varying vec2 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 mirrored_world_uv(vec2 world_pixels, vec2 repeat_pixels) {
    vec2 normalized = world_pixels / max(repeat_pixels, vec2(1.0));
    vec2 cell = floor(normalized);
    vec2 local = fract(normalized);
    vec2 flip = mod(cell, vec2(2.0));
    return mix(local, vec2(1.0) - local, flip);
}

void fragment() {
    vec4 tile_data = texture(TEXTURE, UV);
    vec4 detail = texture(edge_overlay, UV);

    vec2 grass_uv = mirrored_world_uv(world_position + world_offset, grass_repeat_pixels);
    vec2 dirt_uv = mirrored_world_uv(world_position + world_offset, dirt_repeat_pixels);

    vec3 grass = texture(grass_texture, grass_uv).rgb;
    vec3 dirt = texture(dirt_texture, dirt_uv).rgb;
    float grass_mask = step(0.5, tile_data.r);

    vec3 final_color = mix(dirt, grass, grass_mask);
    final_color *= 1.0 - tile_data.g * edge_shadow_strength;
    final_color += tile_data.b * edge_highlight_strength;
    final_color = mix(final_color, detail.rgb, detail.a);

    vec4 tint = COLOR;
    COLOR = vec4(final_color, tile_data.a) * tint;
}
