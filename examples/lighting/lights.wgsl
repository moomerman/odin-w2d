// Point lights passed as uniform arrays. Exercises the WGSL uniform parser:
// array<T, N> fields (literal and const counts), vec3 array striding, and
// trailing / block comments on struct lines.

struct VertexInput {
    @location(0) position: vec2<f32>, // screen position
    @location(1) texcoord: vec2<f32>,
    @location(2) color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) world: vec2<f32>, // pixel position
    @location(1) color: vec4<f32>,
};

const MAX_LIGHTS = 16u;

/* The light count is a const so the array size can reference it. */
struct Lights {
    count: u32, // active lights
    pos: array<vec4f, MAX_LIGHTS>, // xy = position, z = radius
    col: array<vec3f, 16>, // rgb
};

@group(0) @binding(0) var<uniform> projection: mat4x4<f32>;
@group(0) @binding(1) var tex_sampler: sampler;
@group(0) @binding(2) var tex: texture_2d<f32>;
@group(1) @binding(0) var<uniform> lights: Lights;

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = projection * vec4<f32>(in.position, 0.0, 1.0);
    out.world = in.position;
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    var sum = vec3<f32>(0.0);
    for (var i = 0u; i < lights.count; i++) {
        let d = distance(in.world, lights.pos[i].xy);
        let f = clamp(1.0 - d / lights.pos[i].z, 0.0, 1.0);
        sum += lights.col[i] * f * f;
    }
    return vec4<f32>(sum, 1.0);
}
