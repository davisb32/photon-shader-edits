/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/d4_deferred_shading:
  Shade terrain and entities, draw sky

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout (location = 0) out vec3 fragment_color;

#ifdef USE_SEPARATE_ENTITY_DRAWS
/* RENDERTARGETS: 0 */
#else
layout (location = 1) out vec4 colortex3_clear;

/* RENDERTARGETS: 0,3 */
#endif

in vec2 uv;

flat in vec3 ambient_color;
flat in vec3 light_color;

#if defined WORLD_OVERWORLD
flat in vec3 sun_color;
flat in vec3 moon_color;

#include "/include/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;

#if defined SH_SKYLIGHT
flat in vec3 sky_sh[9];
flat in vec3 skylight_up;
#endif

flat in float rainbow_amount;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex0; // skytextured output
uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex4; // sky map
uniform sampler2D colortex5; // previous frame color
uniform sampler2D colortex6; // ambient lighting data
uniform sampler2D colortex7; // previous frame fog scattering
uniform sampler2D colortex11; // clouds history
uniform sampler2D colortex12; // clouds data
uniform sampler2D colortex14; // ambient lighting history data

#ifndef USE_SEPARATE_ENTITY_DRAWS
uniform sampler2D colortex3; // OF damage overlay, armor glint
#endif

#if defined WORLD_OVERWORLD && defined GALAXY
uniform sampler2D colortex13;
#define galaxy_sampler colortex13
#endif

#ifdef CLOUD_SHADOWS
uniform sampler2D colortex8; // cloud shadow map
#endif

uniform sampler3D depthtex0; // atmosphere scattering LUT
uniform sampler2D depthtex1;

#ifdef COLORED_LIGHTS
uniform sampler3D light_sampler_a;
uniform sampler3D light_sampler_b;
#endif

#ifdef BLOCKY_CLOUDS
uniform sampler2D depthtex2; // minecraft cloud texture
#endif

#ifndef WORLD_NETHER
#ifdef SHADOW
uniform sampler2D shadowtex0;
uniform sampler2DShadow shadowtex1;

#ifdef SHADOW_COLOR
uniform sampler2D shadowcolor0;
#endif
#endif
#endif

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float eyeAltitude;
uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;
uniform float rainStrength;
uniform float wetness;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float biome_cave;
uniform float biome_may_rain;
uniform float biome_may_snow;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float world_age;
uniform float eye_skylight;

/*
const bool colortex5MipmapEnabled = true;
const bool colortex11MipmapEnabled = true;
*/

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define TEMPORAL_REPROJECTION

#include "/include/fog/simple_fog.glsl"
#include "/include/lighting/diffuse_lighting.glsl"
#include "/include/lighting/shadows/sampling.glsl"
#include "/include/lighting/specular_lighting.glsl"
#include "/include/misc/distant_horizons.glsl"
#include "/include/surface/edge_highlight.glsl"
#include "/include/surface/material.glsl"
#include "/include/misc/purkinje_shift.glsl"
#include "/include/surface/rain_puddles.glsl"
#include "/include/sky/sky.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/space_conversion.glsl"

#if defined WORLD_OVERWORLD
#include "/include/sky/clouds/sampling.glsl"
#include "/include/sky/rainbow.glsl"
#if defined BLOCKY_CLOUDS
#include "/include/sky/blocky_clouds.glsl"
#endif
#endif

#if defined CLOUD_SHADOWS
#include "/include/lighting/cloud_shadows.glsl"
#endif

//CUSTOM EDIT OKLAB perceptual blending
vec3 oklab_to_rgb(vec3 lab) {
	float lc = lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z;
	float mc = lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z;
	float sc = lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z;
	vec3 lms = vec3(lc, mc, sc);
	lms = lms * lms * lms;
	return vec3(
		4.0767416621*lms.x - 3.3077115913*lms.y + 0.2309699292*lms.z,
		-1.2684380046*lms.x + 2.6097574011*lms.y - 0.3413193965*lms.z,
		-0.0041960863*lms.x - 0.7034186147*lms.y + 1.7076147010*lms.z
	);
}

vec3 rgb_to_oklab(vec3 c) {
	float l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
	float m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
	float s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
	vec3 lms = pow(vec3(l, m, s), vec3(1.0/3.0));
	return vec3(
		0.2104542553*lms.x + 0.7936177850*lms.y - 0.0040720468*lms.z,
		1.9779984951*lms.x - 2.4285922050*lms.y + 0.4505937099*lms.z,
		0.0259040371*lms.x + 0.7827717662*lms.y - 0.8086757660*lms.z
	);
}

vec3 oklab_mix(vec3 a, vec3 b, float t) {
	return oklab_to_rgb(mix(rgb_to_oklab(a), rgb_to_oklab(b), t));
}

//--------------END------------------

void main() {
#if !defined USE_SEPARATE_ENTITY_DRAWS
	colortex3_clear = vec4(0.0);
#endif

	ivec2 texel = ivec2(gl_FragCoord.xy);

	// Sample textures

	float depth         = texelFetch(combined_depth_buffer, texel, 0).x;
	vec4 gbuffer_data_0 = texelFetch(colortex1, texel, 0);
#if defined NORMAL_MAPPING || defined SPECULAR_MAPPING
	vec4 gbuffer_data_1 = texelFetch(colortex2, texel, 0);
#endif
#if !defined USE_SEPARATE_ENTITY_DRAWS
	vec4 overlays       = texelFetch(colortex3, texel, 0);
#endif

    // Check for Distant Horizons terrain

#ifdef DISTANT_HORIZONS
    float depth_mc = texelFetch(depthtex1, texel, 0).x;
    float depth_dh = texelFetch(dhDepthTex, texel, 0).x;
	bool is_dh_terrain = is_distant_horizons_terrain(depth_mc, depth_dh);
#else
    const bool is_dh_terrain = false;
	#define depth_mc depth
#endif

	// Space conversions

	bool is_hand;
	fix_hand_depth(depth_mc, is_hand);

	vec3 position_view = screen_to_view_space(combined_projection_matrix_inverse, vec3(uv, depth), true);
	vec3 position_scene = view_to_scene_space(position_view);
	vec3 position_world = position_scene + cameraPosition;
	vec3 direction_world = normalize(position_scene - gbufferModelViewInverse[3].xyz);

#if defined WORLD_OVERWORLD
	// Atmosphere

	vec3 atmosphere = atmosphere_scattering(
		direction_world, 
		sun_color, 
		sun_dir, 
		moon_color, 
		moon_dir, 
		/* use_klein_nishina_phase */ depth == 1.0 
			&& !(sunAngle > 0.5 && any(equal(ivec3(moonPhase), ivec3(3, 4, 5)))) 
	);

	//CUSTOM EDIT fully art-directed sky and fog system
	// Colors: RGB 0-255. Times: Minecraft ticks (0 = 6 AM, 6000 = noon, 12000 = 6 PM, 18000 = midnight)

	#define RGB(r,g,b) (srgb_eotf_inv(vec3(float(r), float(g), float(b)) / 255.0) * rec709_to_working_color)

	// ---- TIME PARAMETERS (edit these) ----
	const float SUNSET_TIME    = 12000.0;  // tick of peak sunset center
	const float SUNRISE_TIME   =     0.0;  // tick of peak sunrise center (0 = 6 AM)
	const float COLOR_HOLD     =  1000.0;  // ticks sunset/sunrise held at full strength
	const float TRANS_DURATION =  1000.0;  // ticks each crossfade takes

	// ---- SKY & FOG COLORS (edit these) ----

	// ---- NOON ----
	vec3 sky_ovr_noon  = RGB(255,0,0);
	vec3 sky_hor_noon  = RGB(0,255,0);
	vec3 fog_dist_noon = RGB(0,255,255);
	vec3 fog_mist_noon = RGB(255,255,0);

	// ---- SUNSET ----
	vec3 sky_ovr_sunset    = RGB( 15,  20,  80);  // deep indigo
	vec3 sky_hor_sunset    = RGB(255,  95,  30);  // vivid orange
	vec3 fog_dist_sunset   = sky_ovr_sunset;
	vec3 fog_mist_sunset   = sky_hor_sunset;

	// ---- MIDNIGHT ----
	vec3 sky_ovr_midnight  = RGB(10,20,77);
	vec3 sky_hor_midnight  = RGB(11,83,144);
	vec3 fog_dist_midnight = RGB(1,27,69);
	vec3 fog_mist_midnight = RGB(0,40,106);

	// ---- SUNRISE ----
	vec3 sky_ovr_sunrise  = RGB(68,133,175);
	vec3 sky_hor_sunrise  = RGB(255,147,70);
	vec3 fog_dist_sunrise = RGB(61,92,123);
	vec3 fog_mist_sunrise = RGB(169,103,105);

	// ---- TIME BLEND SETUP ----
	// Shift working time by 3000 ticks (= 9 AM) so no transition straddles the 0/24000 wrap boundary.
	// All 4 transitions land cleanly inside [0, 24000] in shifted space.
	float mc_time = mod(float(worldTime), 24000.0);
	float t       = mod(mc_time - 3000.0 + 24000.0, 24000.0);

	float t_sunset   = mod(SUNSET_TIME  - 3000.0 + 24000.0, 24000.0);
	float t_midnight = mod(18000.0      - 3000.0 + 24000.0, 24000.0);
	float t_sunrise  = mod(SUNRISE_TIME - 3000.0 + 24000.0, 24000.0);

	float hh = COLOR_HOLD * 0.5;

	// Sequential blend factors — each one a one-way ramp
	// Chain order: noon -> sunset -> midnight -> sunrise -> noon
	// Noon and midnight dominate naturally; they hold for all ticks outside the transition windows
	float f_ns = linear_step(t_sunset  - hh - TRANS_DURATION, t_sunset  - hh,                  t);
	float f_sm = linear_step(t_sunset  + hh,                  t_sunset  + hh + TRANS_DURATION, t);
	float f_mr = linear_step(t_sunrise - hh - TRANS_DURATION, t_sunrise - hh,                  t);
	float f_rn = linear_step(t_sunrise + hh,                  t_sunrise + hh + TRANS_DURATION, t);

	// ---- COLOR BLENDS ----
	vec3 sky_horizon = sky_hor_noon;
	sky_horizon = oklab_mix(sky_horizon, sky_hor_sunset,   f_ns);
	sky_horizon = oklab_mix(sky_horizon, sky_hor_midnight, f_sm);
	sky_horizon = oklab_mix(sky_horizon, sky_hor_sunrise,  f_mr);
	sky_horizon = oklab_mix(sky_horizon, sky_hor_noon,     f_rn);

	vec3 sky_overhead = sky_ovr_noon;
	sky_overhead = oklab_mix(sky_overhead, sky_ovr_sunset,   f_ns);
	sky_overhead = oklab_mix(sky_overhead, sky_ovr_midnight, f_sm);
	sky_overhead = oklab_mix(sky_overhead, sky_ovr_sunrise,  f_mr);
	sky_overhead = oklab_mix(sky_overhead, sky_ovr_noon,     f_rn);

	vec3 fog_distant = fog_dist_noon;
	fog_distant = oklab_mix(fog_distant, fog_dist_sunset,   f_ns);
	fog_distant = oklab_mix(fog_distant, fog_dist_midnight, f_sm);
	fog_distant = oklab_mix(fog_distant, fog_dist_sunrise,  f_mr);
	fog_distant = oklab_mix(fog_distant, fog_dist_noon,     f_rn);

	vec3 fog_mist = fog_mist_noon;
	fog_mist = oklab_mix(fog_mist, fog_mist_sunset,   f_ns);
	fog_mist = oklab_mix(fog_mist, fog_mist_midnight, f_sm);
	fog_mist = oklab_mix(fog_mist, fog_mist_sunrise,  f_mr);
	fog_mist = oklab_mix(fog_mist, fog_mist_noon,     f_rn);

	// ---- SKY OUTPUT ----
	// Fully replaces Photon atmosphere LUT. direction_world.y = 0 at horizon, 1 overhead.
	float horizon_weight = exp(-4.0 * direction_world.y);
	atmosphere = oklab_mix(sky_overhead, sky_horizon, horizon_weight);

	//--------------END------------------

	// Read clouds/aurora/crepuscular rays

	float clouds_apparent_distance;
	vec4 clouds_and_aurora = read_clouds_and_aurora(uv, clouds_apparent_distance);

	// Blocky clouds

#ifdef BLOCKY_CLOUDS
	vec3 world_start_pos = gbufferModelViewInverse[3].xyz + cameraPosition;
	vec3 world_end_pos   = position_world;

	float dither = texelFetch(noisetex, texel & 511, 0).b;
	      dither = r1(frameCounter, dither);

	vec4 blocky_clouds = raymarch_blocky_clouds(
		world_start_pos,
		world_end_pos,
		depth == 1.0,
		blocky_clouds_altitude_l0,
		dither
	);

#ifdef BLOCKY_CLOUDS_LAYER_2
	float visibility = pow4(blocky_clouds.a);
	vec4 blocky_clouds_l2 = raymarch_blocky_clouds(
		world_start_pos,
		world_end_pos,
		depth == 1.0,
		blocky_clouds_altitude_l1,
		dither
	);
	blocky_clouds.rgb += blocky_clouds_l2.xyz * visibility;
	blocky_clouds.a   *= mix(1.0, blocky_clouds_l2.a, visibility);
#endif

	float new_alpha = sqr(sqr(blocky_clouds.a));
	blocky_clouds.rgb += atmosphere * (1.0 - new_alpha) * (blocky_clouds.a - new_alpha);
	blocky_clouds.a = new_alpha;
#endif
#endif

	if (depth == 1.0) { // Sky
#if defined WORLD_OVERWORLD
		fragment_color = draw_sky(direction_world, atmosphere, clouds_and_aurora, clouds_apparent_distance);
#else
		fragment_color = draw_sky(direction_world);
#endif

		// Apply blocky clouds 
#if defined WORLD_OVERWORLD && defined BLOCKY_CLOUDS 
		fragment_color = fragment_color * blocky_clouds.w + blocky_clouds.xyz;
#endif

		// Apply common fog
		vec4 fog = common_fog(far, true);
		fragment_color = mix(fog.rgb, fragment_color.rgb, fog.a);

		// Apply purkinje shift
		fragment_color = purkinje_shift(fragment_color, vec2(0.0, 1.0));
		
	} else { // Terrain
		// Sample ambient occlusion a while before using it (latency hiding)

		vec2 half_res_pos = gl_FragCoord.xy * (0.5 / taau_render_scale) - 0.5;

		ivec2 i = ivec2(half_res_pos);
		vec2  f = fract(half_res_pos);

		ivec2 p10 = i + ivec2(1, 0);
		ivec2 p01 = i + ivec2(0, 1);
		ivec2 p11 = i + ivec2(1, 1);

		vec4 ambient_00 = texelFetch(colortex6, i, 0);
		vec4 ambient_10 = texelFetch(colortex6, p10, 0);
		vec4 ambient_01 = texelFetch(colortex6, p01, 0);
		vec4 ambient_11 = texelFetch(colortex6, p11, 0);
		float ambient_depth_00 = texelFetch(colortex14, i, 0).x;
		float ambient_depth_10 = texelFetch(colortex14, p10, 0).x;
		float ambient_depth_01 = texelFetch(colortex14, p01, 0).x;
		float ambient_depth_11 = texelFetch(colortex14, p11, 0).x;

		// Unpack gbuffer data

		mat4x2 data = mat4x2(
			unpack_unorm_2x8(gbuffer_data_0.x),
			unpack_unorm_2x8(gbuffer_data_0.y),
			unpack_unorm_2x8(gbuffer_data_0.z),
			unpack_unorm_2x8(gbuffer_data_0.w)
		);

		vec3 albedo        = vec3(data[0], data[1].x);
		uint material_mask = uint(255.0 * data[1].y);
		vec3 flat_normal   = decode_unit_vector(data[2]);
		vec2 light_levels  = data[3];

		//CUSTOM EDIT fullbright

		light_levels.y = 1.0;

		//--------------END------------------

#if !defined USE_SEPARATE_ENTITY_DRAWS
		uint overlay_id = uint(255.0 * overlays.a);
		albedo = overlay_id == 0u ? albedo + overlays.rgb : albedo; // enchantment glint
		albedo = overlay_id == 1u ? 2.0 * albedo * overlays.rgb : albedo; // damage overlay
#endif

		// Get material and normal

		Material material = material_from(albedo, material_mask, position_world, flat_normal, light_levels);

		vec3 normal = flat_normal;
        bool parallax_shadow = false;

#ifdef DISTANT_HORIZONS
		if (!is_dh_terrain) {
#endif

	#ifdef NORMAL_MAPPING
		normal = decode_unit_vector(gbuffer_data_1.xy);
	#endif

	#ifdef SPECULAR_MAPPING
		vec4 specular_map = vec4(unpack_unorm_2x8(gbuffer_data_1.z), unpack_unorm_2x8(gbuffer_data_1.w));
		decode_specular_map(specular_map, material, parallax_shadow);
	#elif defined NORMAL_MAPPING
		parallax_shadow = gbuffer_data_1.z >= 0.5;
	#endif

#ifdef DISTANT_HORIZONS
		}
#endif

		// Rain puddles

#if defined WORLD_OVERWORLD && defined RAIN_PUDDLES
		if (wetness > eps && biome_may_rain > eps) {
			bool puddle = get_rain_puddles(
				position_world,
				flat_normal,
				light_levels,
				material.porosity,
				material_mask,
				normal,
				material.albedo,
				material.f0,
				material.roughness,
				material.ssr_multiplier
			);
		}
#endif

		// Upscale ambient occlusion

		float lin_z = screen_to_view_space_depth(combined_projection_matrix_inverse, depth);

		#define depth_weight(reversed_depth) exp2(-10.0 * abs(screen_to_view_space_depth(combined_projection_matrix_inverse, 1.0 - reversed_depth) - lin_z))
		float w00 = depth_weight(ambient_depth_00) * (1.0 - f.x) * (1.0 - f.y);
		float w10 = depth_weight(ambient_depth_10) * (f.x - f.x * f.y);
		float w01 = depth_weight(ambient_depth_01) * (f.y - f.x * f.y);
		float w11 = depth_weight(ambient_depth_11) * (f.x * f.y);
		#undef depth_weight

		vec4 ambient_upscaled;
		float weight_sum = w00 + w10 + w01 + w11;

		if (weight_sum != 0.0) {
			ambient_upscaled 
				= ambient_00 * w00 
				+ ambient_10 * w10 
				+ ambient_01 * w01 
				+ ambient_11 * w11;

			ambient_upscaled *= rcp(weight_sum);
		} else {
			ambient_upscaled = ambient_00;
		}

		float ao = ambient_upscaled.x;
		float ambient_sss = ambient_upscaled.y;

		vec3 bent_normal;
		bent_normal.xy = ambient_upscaled.zw * 2.0 - 1.0;
		bent_normal.z = sqrt(clamp01(1.0 - dot(bent_normal.xy, bent_normal.xy)));
		bent_normal = mat3(gbufferModelViewInverse) * bent_normal;

		// Sense check bent normal
		if (dot(bent_normal, normal) < eps) bent_normal = normal;

		// No AO/bent normal on hand
		if (is_hand) {
			ao = 1.0;
			bent_normal = normal;
		}

		// Shadows

		//CUSTOM EDIT vanilla-style hardcoded face shading

		//float NoL = dot(normal, light_dir);

		float peak  = 0.66;
		float floor = 0.15;

		if (material_mask == MATERIAL_LEAVES) {
			peak  = 1.0;
			floor = 0.15;
		}

		float top         = peak;
		float north_south = mix(floor, peak, 0.666);
		float east_west   = mix(floor, peak, 0.333);
		float bottom      = floor;

		float NoL;
		if (material_mask == MATERIAL_SMALL_PLANTS
		|| material_mask == MATERIAL_TALL_PLANTS_LOWER
		|| material_mask == MATERIAL_TALL_PLANTS_UPPER) {
			NoL = top; // billboard vegetation matches grass block top face
		} else if (abs(flat_normal.y) > 0.9) {
			NoL = flat_normal.y > 0.0 ? top : bottom;
		} else if (abs(flat_normal.z) > 0.5) {
			NoL = north_south;
		} else {
			NoL = east_west;
		}

		//--------------END------------------
		
		float NoV = clamp01(dot(normal, -direction_world));
		float LoV = dot(light_dir, -direction_world);
		float halfway_norm = inversesqrt(2.0 * LoV + 2.0);
		float NoH = (NoL + NoV) * halfway_norm;
		float LoH = LoV * halfway_norm + halfway_norm;

#if defined WORLD_OVERWORLD && defined CLOUD_SHADOWS
		float cloud_shadows = get_cloud_shadows(colortex8, position_scene);
#else
		const float cloud_shadows = 1.0;
#endif

#if defined SHADOW && (defined WORLD_OVERWORLD || defined WORLD_END)
		float sss_depth;
		float shadow_distance_fade;
		vec3 shadows;

        shadows = calculate_shadows(position_scene, flat_normal, light_levels.y, cloud_shadows, material.sss_amount, shadow_distance_fade, sss_depth);
		
		//CUSTOM EDIT disable cast shadows

		shadows = vec3(1.0); 

		//--------------END------------------

	#ifdef DISTANT_HORIZONS
		if (is_dh_terrain) {
			shadow_distance_fade = 1.0;
		}
	#endif
#else
		vec3 shadows = vec3(sqrt(ao) * pow8(light_levels.y));
		#define sss_depth 0.0
		#define shadow_distance_fade 0.0
#endif

#if defined POM && defined POM_SHADOW && (defined SPECULAR_MAPPING || defined NORMAL_MAPPING)
		shadows *= float(!parallax_shadow);
#endif

		// Diffuse lighting

		fragment_color = get_diffuse_lighting(
			material,
			position_scene,
			normal,
			flat_normal,
			bent_normal,
			shadows,
			light_levels,
			ao,
			ambient_sss,
			sss_depth,
#ifdef CLOUD_SHADOWS
			cloud_shadows,
#endif
			shadow_distance_fade,
			NoL,
			NoV,
			NoH,
			LoV
		);

		// Specular highlight

#if defined WORLD_OVERWORLD || defined WORLD_END
		
		//CUSTOM EDIT remove specular highlights

		//fragment_color += get_specular_highlight(material, NoL, NoV, NoH, LoV, LoH) * light_color * shadows * cloud_shadows * ao;

		//--------------END------------------
#endif

		// Specular reflections

#if defined ENVIRONMENT_REFLECTIONS || defined SKY_REFLECTIONS
		if (material.ssr_multiplier > eps) {
			mat3 tbn = get_tbn_matrix(normal);

			fragment_color += get_specular_reflections(
				material,
				tbn,
				vec3(uv, depth),
				position_view,
				position_world,
				normal,
				flat_normal,
				direction_world,
				direction_world * tbn,
				light_levels.y,
				false
			);
		}
#endif
		// Edge highlight

#ifdef EDGE_HIGHLIGHT
		//fragment_color *= 1.0 + 0.5 * get_edge_highlight(position_scene, flat_normal, depth, material_mask);

		//CUSTOM EDIT edge highlight on blocks with brightness and saturation control

		float edge = get_edge_highlight(position_scene, flat_normal, depth, material_mask);

		float edge_brightness = 0.75; // Increase to make edges brighter, decrease toward 0.0 to disable
		float edge_saturation = 1.2; // Increase for more vivid edges, only affects edge pixels

		float luma = dot(fragment_color, vec3(0.299, 0.587, 0.114));

		// 1.0 + (edge_saturation - 1.0) * edge means:
		// when edge=0 -> mix factor is 1.0 -> fragment_color unchanged
		// when edge=1 -> mix factor is edge_saturation -> full saturation boost
		fragment_color = mix(vec3(luma), fragment_color, 1.0 + (edge_saturation - 1.0) * edge);
		fragment_color *= 1.0 + edge_brightness * edge;

		//--------------END------------------

#endif

		// Apply fog

		float view_distance = length(position_view);

#ifdef BORDER_FOG
	#if defined WORLD_OVERWORLD
		vec3 horizon_dir = normalize(vec3(direction_world.xz, min(direction_world.y, -0.1)).xzy);
		vec3 horizon_color = texture(colortex4, project_sky(horizon_dir)).rgb;

		float horizon_factor = linear_step(0.1, 1.0, exp(-75.0 * sqr(sun_dir.y + 0.0496)));
			  horizon_factor = clamp01(horizon_factor + step(0.01, rainStrength));
			  horizon_factor = max(horizon_factor, dampen(linear_step(0.15, 0.05, direction_world.y)));

		vec3 border_fog_color = mix(atmosphere, horizon_color, sqr(horizon_factor)) * (1.0 - biome_cave);
	#else
		vec3 border_fog_color = texture(colortex4, project_sky(direction_world)).rgb;
	#endif

		float border_fog = border_fog(position_scene, direction_world);
		fragment_color = mix(border_fog_color, fragment_color, border_fog);
#endif

		vec4 fog = common_fog(view_distance, false);
		fragment_color = fragment_color * fog.a + fog.rgb;

#if defined WORLD_OVERWORLD 
		// Apply clouds in front of terrain

	#ifdef BLOCKY_CLOUDS
		fragment_color = fragment_color * blocky_clouds.w + blocky_clouds.xyz;
	#else
		if (sqr(clouds_apparent_distance) < length_squared(position_view)) {
			fragment_color = fragment_color * clouds_and_aurora.w + clouds_and_aurora.xyz;
		}
	#endif

		// Apply rainbows in front of terrain

	#ifdef RAINBOWS
		fragment_color = draw_rainbows(
			fragment_color, 
			direction_world, 
			min(view_distance, mix(clouds_apparent_distance, 1e6, linear_step(1.0, 0.95, clouds_and_aurora.w)))
		);
	#endif
#endif

		//CUSTOM EDIT two-pass stylized fog — colors driven by art-directed system above

		bool enable_custom_fog = true;

		if (enable_custom_fog) {

			// ---- USER PARAMETERS (edit these) ----
			float fog_start              = 5.0;
			float fog_end                = 20.0;
			float fog_opacity            = 1;

			float mist_fog_start         = fog_start;
			float mist_fog_end           = fog_end;
			float mist_fog_opacity       = 1;
			float mist_fog_height_start  = 0.0;
			float mist_fog_height_end    = 1.0;

			// ---- DERIVED (do not edit) ----
			float fog_start_blocks       = fog_start      * 16.0;
			float fog_end_blocks         = fog_end        * 16.0;
			float mist_fog_start_blocks  = mist_fog_start * 16.0;
			float mist_fog_end_blocks    = mist_fog_end   * 16.0;

			// Pass 1 — distance fog
			float fog_factor             = linear_step(fog_start_blocks, fog_end_blocks, view_distance) * fog_opacity;
			fragment_color               = mix(fragment_color, fog_distant, fog_factor);

			// Pass 2 — low altitude mist
			float mist_fog_dist_factor   = linear_step(mist_fog_start_blocks, mist_fog_end_blocks, view_distance);
			float mist_fog_height_factor = clamp01(1.0 - (position_world.y - mist_fog_height_start) / (mist_fog_height_end - mist_fog_height_start));
			float mist_fog_factor        = mist_fog_dist_factor * mist_fog_height_factor * mist_fog_opacity;
			fragment_color               = mix(fragment_color, fog_mist, mist_fog_factor);

		}

		//--------------END------------------

		// Apply purkinje shift

		fragment_color = purkinje_shift(fragment_color, light_levels);
		
	}
}
