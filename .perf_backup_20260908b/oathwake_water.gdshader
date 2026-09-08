shader_type canvas_item;
// Água do oceano e dos lagos de Oathwake.
//
// Gera tudo a partir da posição de MUNDO, então um único ColorRect cobre o mapa
// inteiro e o anel externo sem custo nenhum de tile. As cores são quantizadas
// numa rampa de 4 passos e as coordenadas são travadas na grade de pixel — sem
// isso o gradiente suave brigaria com o pixel art do terreno em volta.

uniform vec4 deep_color : source_color = vec4(0.129, 0.227, 0.322, 1.0);
uniform vec4 mid_color : source_color = vec4(0.180, 0.329, 0.424, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.271, 0.459, 0.522, 1.0);
uniform vec4 crest_color : source_color = vec4(0.486, 0.639, 0.639, 1.0);

uniform float pixel_size = 2.0;      // tamanho do "pixel" da água, em px de mundo
uniform float wave_scale = 0.018;    // frequência das ondas grandes
uniform float ripple_scale = 0.075;  // frequência da textura fina
uniform float flow_speed = 0.12;     // velocidade da correnteza
uniform float crest_threshold = 0.74;
uniform vec2 flow_direction = vec2(1.0, 0.35);
uniform float daylight : hint_range(0.0, 1.0) = 1.0;

// VERTEX só existe no vertex shader; a posição de mundo tem que atravessar
// como varying para o fragment.
varying vec2 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 frac = fract(p);
	frac = frac * frac * (3.0 - 2.0 * frac);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, frac.x), mix(c, d, frac.x), frac.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = floor(world_position / pixel_size) * pixel_size;
	vec2 drift = normalize(flow_direction) * TIME * flow_speed * 24.0;

	float swell = value_noise((p + drift) * wave_scale);
	swell += 0.5 * value_noise((p - drift * 0.6) * wave_scale * 2.1);
	swell /= 1.5;

	float ripple = value_noise((p + drift * 1.8) * ripple_scale);
	float height = swell * 0.72 + ripple * 0.28;

	vec4 water = deep_color;
	water = mix(water, mid_color, step(0.38, height));
	water = mix(water, shallow_color, step(0.58, height));
	water = mix(water, crest_color, step(crest_threshold, height));

	// Escurece junto com a noite, igual ao resto do terreno.
	water.rgb *= mix(0.34, 1.0, daylight);
	COLOR = water;
}
