// Physically-inspired planetary atmosphere shader for Godot 4
// Raymarched in WORLD SPACE to prevent matrix inversion bugs.

shader_type spatial;
render_mode blend_mix, depth_test_disabled, unshaded, cull_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// -----------------------------------------------------------------------
// Planet / atmosphere shape
// -----------------------------------------------------------------------
uniform float planet_radius = 100.0;
uniform float atmosphere_radius = 120.0;

// -----------------------------------------------------------------------
// Scattering coefficients
// -----------------------------------------------------------------------
uniform vec3 rayleigh_coefficients = vec3(0.0058, 0.0135, 0.0331); 
uniform float rayleigh_scale_height = 8.0; 

uniform float mie_coefficient = 0.021;
uniform float mie_scale_height = 1.2;
uniform float mie_g = 0.76; 

uniform float sun_intensity = 10.0;

uniform float multi_scatter_strength : hint_range(0.0, 1.0) = 0.4;
uniform int multi_scatter_octaves : hint_range(1, 6) = 4;
uniform float multi_scatter_falloff : hint_range(0.0, 1.0) = 0.5; 

// -----------------------------------------------------------------------
// Raymarch quality
// -----------------------------------------------------------------------
uniform int view_steps : hint_range(4, 64) = 16;
uniform int light_steps : hint_range(2, 32) = 8;

varying vec3 planet_center_world;
varying vec3 light_dir_world;

// Standard sphere intersection
vec2 ray_sphere_intersect(vec3 start, vec3 dir, float max_dist, float radius) {
	float a = dot(dir, dir);
	float b = 2.0 * dot(dir, start);
	float c = dot(start, start) - (radius * radius);
	float d = (b * b) - 4.0 * a * c;

	if (d < 0.0) {
		return vec2(-1.0);
	}

	float t1 = (-b - sqrt(d)) / (2.0 * a);
	float t2 = (-b + sqrt(d)) / (2.0 * a);

	if (t2 < 0.0) {
		return vec2(-1.0);
	}

	vec2 t = vec2(
		max(t1, 0.0),
		min(t2, max_dist)
	);
	return t;
}

vec2 sample_density(vec3 pos) {
	float height = max(length(pos) - planet_radius, 0.0);
	float rayleigh_density = exp(-height / rayleigh_scale_height);
	float mie_density = exp(-height / mie_scale_height);
	return vec2(rayleigh_density, mie_density);
}

vec2 light_optical_depth(vec3 origin) {
	vec2 hit = ray_sphere_intersect(origin, light_dir_world, 1e9, atmosphere_radius);
	float ray_len = hit.y;
	float step_size = ray_len / float(light_steps);

	vec2 optical_depth = vec2(0.0);
	vec3 pos = origin;
	for (int i = 0; i < light_steps; i++) {
		pos += light_dir_world * step_size;
		optical_depth += sample_density(pos) * step_size;
	}
	return optical_depth;
}

float phase_rayleigh(float cos_theta) {
	return (3.0 / (16.0 * PI)) * (1.0 + cos_theta * cos_theta);
}

float phase_mie(float cos_theta, float g) {
	float g2 = g * g;
	float denom = 1.0 + g2 - 2.0 * g * cos_theta;
	return (1.0 - g2) / (4.0 * PI * pow(max(denom, 0.0001), 1.5));
}

void vertex() {
	// Get the world position of the mesh this shader is attached to
	planet_center_world = NODE_POSITION_WORLD;
	
	// Convert the object's local -Z axis (original sun logic) into a World Space direction
	light_dir_world = normalize((MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
}

void fragment() {
	// 1. Reconstruct World Space position of the current pixel from the depth buffer
	float depth = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec4 clip_pos = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * clip_pos;
	view_pos.xyz /= -view_pos.w;
	vec4 world_pos = INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0);
	vec3 frag_world = world_pos.xyz;

	// 2. Calculate ray origin and direction in World Space
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(frag_world - ro);

	// 3. Shift the origin so the planet center is at (0,0,0) for the intersection math
	ro += planet_center_world;
	float scene_depth = length(frag_world - CAMERA_POSITION_WORLD);

	// 4. Ray-Sphere Intersections
	vec2 atmo_hit = ray_sphere_intersect(ro, rd, scene_depth, atmosphere_radius);
	if (atmo_hit.x < 0.0 || atmo_hit.y < 0.0) {
		discard;
	}

	vec2 ground_hit = ray_sphere_intersect(ro, rd, scene_depth, planet_radius);
	float far_limit = (ground_hit.x >= 0.0) ? ground_hit.x : atmo_hit.y;
	far_limit = min(far_limit, scene_depth);

	float march_start = atmo_hit.x;
	float march_len = max(far_limit - march_start, 0.0);

	if (march_len <= 0.0) {
		discard;
	}

	float step_size = march_len / float(view_steps);

	// Start march
	vec3 pos = ro + rd * march_start;
	vec2 view_optical_depth = vec2(0.0);
	vec3 rayleigh_accum = vec3(0.0);
	vec3 mie_accum = vec3(0.0);

	float cos_theta = dot(rd, light_dir_world);
	float phase_r = phase_rayleigh(cos_theta);
	float phase_m = phase_mie(cos_theta, mie_g);

	for (int i = 0; i < view_steps; i++) {
		pos += rd * step_size;

		vec2 local_density = sample_density(pos);
		view_optical_depth += local_density * step_size;

		vec2 light_depth = light_optical_depth(pos);
		vec2 total_depth = view_optical_depth + light_depth;

		vec3 transmittance = exp(
			-(rayleigh_coefficients * total_depth.x) - (mie_coefficient * 1.1 * total_depth.y)
		);

		rayleigh_accum += local_density.x * transmittance * step_size;
		mie_accum += local_density.y * transmittance * step_size;
	}

	vec3 single_scatter =
		(rayleigh_coefficients * phase_r * rayleigh_accum +
		 mie_coefficient * phase_m * mie_accum) * sun_intensity;

	vec3 multi_scatter = vec3(0.0);
	{
		vec3 isotropic_r = rayleigh_coefficients * rayleigh_accum;
		vec3 isotropic_m = vec3(mie_coefficient) * mie_accum;
		vec3 base = (isotropic_r + isotropic_m) * sun_intensity * (1.0 / (4.0 * PI));

		float weight = multi_scatter_strength;
		for (int o = 0; o < multi_scatter_octaves; o++) {
			multi_scatter += base * weight;
			weight *= multi_scatter_falloff;
		}
	}

	vec3 total_light = single_scatter + multi_scatter;

	ALBEDO = total_light;
	ALPHA = clamp(max(max(total_light.r, total_light.g), total_light.b), 0.0, 1.0);
}