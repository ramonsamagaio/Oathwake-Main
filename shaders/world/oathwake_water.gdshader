shader_type canvas_item;
// Água do oceano e dos lagos de Oathwake.
//
// Gera tudo a partir da posição de MUNDO, então um único ColorRect cobre o mapa
// inteiro e o anel externo sem custo nenhum de tile. As cores são quantizadas
// numa rampa de 4 passos e as coordenadas são travadas na grade de pixel — sem
// isso o gradiente suave brigaria com o pixel art do terreno em volta.
//
// A versão anterior somava duas oitavas de value noise na mesma orientação: a
// grade quadrada do lattice ficava visível e a água lia como blocos retangulares
// em vez de água. Duas coisas resolvem isso, e as duas estão aqui:
//   1. cada oitava do FBM amostra o domínio ROTACIONADO num ângulo diferente,
//      então nenhuma direção de grade se acumula;
//   2. por cima do FBM vem uma onda direcional (bandas de vagalhão ao longo da
//      correnteza) cuja fase é deslocada pelo próprio ruído. É a banda que dá a
//      leitura de "água correndo"; o ruído só quebra a regularidade dela.

uniform vec4 deep_color : source_color = vec4(0.129, 0.227, 0.322, 1.0);
uniform vec4 mid_color : source_color = vec4(0.180, 0.329, 0.424, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.271, 0.459, 0.522, 1.0);
uniform vec4 crest_color : source_color = vec4(0.486, 0.639, 0.639, 1.0);

uniform float pixel_size = 2.0;      // tamanho do "pixel" da água, em px de mundo
uniform float wave_scale = 0.030;    // frequência da primeira oitava do FBM
uniform float swell_stretch = 0.55;  // domínio esticado: onda longa, não bolha
uniform float band_frequency = 0.13; // espaçamento dos vagalhões
uniform float band_weight = 0.34;    // quanto do resultado é a onda direcional
uniform float band_warp = 60.0;      // o ruído torce a crista e quebra a listra
uniform float flow_speed = 0.12;
uniform vec2 flow_direction = vec2(1.0, 0.35);
uniform float crest_threshold = 0.775;
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

vec2 rotate2(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = floor(world_position / pixel_size) * pixel_size;
	vec2 flow = normalize(flow_direction);
	vec2 drift = flow * TIME * flow_speed * 24.0;

	// Quatro oitavas, cada uma num domínio girado. Os ângulos não são múltiplos
	// um do outro de propósito: ângulos harmônicos voltariam a alinhar a grade.
	float angles[4] = float[4](0.0, 0.9, 2.1, 3.4);
	float amplitude = 1.0;
	float frequency = wave_scale;
	float swell = 0.0;
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 sample_point = rotate2(p + drift * (1.0 + 0.35 * float(i)), angles[i]);
		swell += amplitude * value_noise(
			vec2(sample_point.x * frequency * swell_stretch,
			     sample_point.y * frequency * (2.1 - swell_stretch))
		);
		total += amplitude;
		amplitude *= 0.5;
		frequency *= 2.03;
	}
	swell /= total;

	// Distância perpendicular à correnteza: é ao longo dela que o vagalhão anda.
	float across = p.x * flow.y - p.y * flow.x;
	float warp = (swell - 0.5) * band_warp;
	float band = sin((across + warp) * band_frequency - TIME * 1.4) * 0.5 + 0.5;

	float height = swell * (1.0 - band_weight) + band * band_weight;

	vec4 water = deep_color;
	water = mix(water, mid_color, step(0.42, height));
	water = mix(water, shallow_color, step(0.60, height));
	water = mix(water, crest_color, step(crest_threshold, height));

	// Escurece junto com a noite, igual ao resto do terreno.
	water.rgb *= mix(0.34, 1.0, daylight);
	COLOR = water;
}
