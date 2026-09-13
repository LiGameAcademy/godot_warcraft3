extends RefCounted
## PE2 filter enums differ from mesh Layer.FilterMode. Keep these mappings separate.
const SOURCE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_texture = false;
uniform bool billboard = true;
uniform bool velocity_aligned = false;
uniform vec2 grid = vec2(1.0);
uniform vec3 life_uv = vec3(0.0, 0.0, 1.0);
uniform vec3 decay_uv = vec3(0.0, 0.0, 1.0);
uniform float middle = 0.5;
uniform float rgb_multiplier = 1.0;
uniform float alpha_cutoff = 0.0;

float atlas_frame(vec3 interval, float t) {
    float count = abs(interval.y - interval.x) + 1.0;
    float cycles = max(interval.z, 1.0);
    float progress = t >= 1.0 ? 0.999999 : fract(max(t, 0.0) * cycles);
    return interval.x + sign(interval.y - interval.x) * min(floor(progress * count), count - 1.0);
}

void vertex() {
    if (billboard) {
        vec3 sizes = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
        vec3 right = INV_VIEW_MATRIX[0].xyz;
        vec3 up = INV_VIEW_MATRIX[1].xyz;
        vec3 facing = INV_VIEW_MATRIX[2].xyz;
        if (velocity_aligned) {
            vec3 axis = MODEL_MATRIX[1].xyz;
            axis -= facing * dot(axis, facing);
            if (length(axis) > 0.00001) {
                up = normalize(axis);
                right = normalize(cross(up, facing));
            }
        }
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * sizes.x, 0.0), vec4(up * sizes.y, 0.0), vec4(facing * sizes.z, 0.0), MODEL_MATRIX[3]);
        MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
    }
    float age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
    float frame;
    if (age < middle) {
        frame = atlas_frame(life_uv, age / max(middle, 0.000001));
    } else {
        frame = atlas_frame(decay_uv, (age - middle) / max(1.0 - middle, 0.000001));
    }
    frame = clamp(frame, 0.0, grid.x * grid.y - 1.0);
    UV = (UV + vec2(mod(frame, grid.x), floor(frame / grid.x))) / grid;
}

void fragment() {
    vec4 texel = has_texture ? texture(atlas, UV) : vec4(1.0);
    vec4 tint = texel * COLOR;
    if (tint.a < alpha_cutoff) { discard; }
    ALBEDO = tint.rgb * rgb_multiplier;
    ALPHA = tint.a;
}
"""


static func build(em: Dictionary, texture: Texture2D, tail: bool = false) -> ShaderMaterial:
	var mode := int(em.get("filter_mode", 0))
	# Match war3-model's PE2 renderer: AlphaKey uses alpha-tested additive blending.
	var blend := "blend_mix"
	if mode == 1 or mode == 4:
		blend = "blend_add"
	elif mode == 2 or mode == 3:
		blend = "blend_mul"
	var shader := Shader.new()
	shader.code = SOURCE % blend
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.resource_local_to_scene = true
	mat.set_shader_parameter("atlas", texture)
	mat.set_shader_parameter("has_texture", texture != null)
	mat.set_shader_parameter("billboard", (int(em.get("flags", 0)) & 0x100000) == 0)
	mat.set_shader_parameter("velocity_aligned", tail)
	mat.set_shader_parameter("grid", Vector2(maxi(1, int(em.get("columns", 1))), maxi(1, int(em.get("rows", 1)))))
	var life: Array = em.get("tail_uv" if tail else "life_span_uv", em.get("life_span_uv", [0, 0, 1]))
	var decay: Array = em.get("tail_decay_uv" if tail else "decay_uv", em.get("decay_uv", life))
	mat.set_shader_parameter("life_uv", _vec3(life))
	mat.set_shader_parameter("decay_uv", _vec3(decay))
	mat.set_shader_parameter("middle", clampf(float(em.get("time_middle", 0.5)), 0.0, 1.0))
	mat.set_shader_parameter("rgb_multiplier", (2.0 if mode == 3 else 1.0) * maxf(0.0, float(em.get("color_multiplier", 1.0))))
	mat.set_shader_parameter("alpha_cutoff", 0.83 if mode == 4 else (0.01 if mode == 2 or mode == 3 else 0.0))
	mat.render_priority = clampi(int(em.get("priority_plane", 0)), -128, 127)
	return mat


static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]) if a.size() > 0 else 0.0, float(a[1]) if a.size() > 1 else 0.0, float(a[2]) if a.size() > 2 else 1.0)
