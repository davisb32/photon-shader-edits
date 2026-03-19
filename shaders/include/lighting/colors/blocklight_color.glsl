#if !defined INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
#define INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR

#include "/include/utility/color.glsl"

const vec3  blocklight_color = from_srgb(vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B)) * BLOCKLIGHT_I;

//CUSTOM EDIT brighten block lights

const float blocklight_scale = 25.0; // default 6.0 — increase for brighter area lighting

//--------------END------------------

const float emission_scale   = 40.0 * EMISSION_STRENGTH;

#endif // INCLUDE_LIGHTING_COLORS_BLOCKLIGHT_COLOR
