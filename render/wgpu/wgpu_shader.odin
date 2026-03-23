package renderer_wgpu

import hm "core:container/handle_map"
import "core:fmt"
import "core:strings"
import "vendor:wgpu"

import core "../../core"

@(private = "package")
renderer_load_shader :: proc(wgsl_source: string) -> core.Shader_Handle {
	r := &renderer
	entry: Shader_Entry

	// Parse WGSL to extract metadata
	parse := parse_wgsl(wgsl_source)
	defer destroy_parse_result(&parse)

	// Create shader module
	entry.module = wgpu.DeviceCreateShaderModule(
		r.device,
		&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = wgsl_source}},
	)

	// Store entry points
	entry.vertex_entry = strings.clone(
		len(parse.vertex_entry) > 0 ? parse.vertex_entry : "vs_main",
	)
	entry.fragment_entry = strings.clone(
		len(parse.fragment_entry) > 0 ? parse.fragment_entry : "fs_main",
	)

	// Find group 1 uniform binding and compute layout
	uniform_struct_name: string
	for &b in parse.bindings {
		if b.group == 1 && b.type == "uniform" {
			uniform_struct_name = b.type_name
			break
		}
	}

	// Build uniform metadata from the struct
	if len(uniform_struct_name) > 0 {
		s := find_struct(&parse.structs, uniform_struct_name)
		if s != nil {
			entry.uniform_size = s.size
			entry.uniforms = make(map[string]Shader_Uniform)

			for &field in s.fields {
				uniform_type: Shader_Uniform_Type
				#partial switch field.type {
				case .F32:
					uniform_type = .F32
				case .I32:
					uniform_type = .I32
				case .U32:
					uniform_type = .U32
				case .Vec2F32:
					uniform_type = .Vec2F32
				case .Vec3F32:
					uniform_type = .Vec3F32
				case .Vec4F32:
					uniform_type = .Vec4F32
				case .Mat4x4F32:
					uniform_type = .Mat4x4F32
				}
				entry.uniforms[strings.clone(field.name)] = Shader_Uniform {
					offset = field.offset,
					size   = field.size,
					type   = uniform_type,
				}
			}
		}
	}

	// Create bind group layout for group 1 (user uniforms)
	if entry.uniform_size > 0 {
		entry.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			r.device,
			&{
				entryCount = 1,
				entries = &wgpu.BindGroupLayoutEntry {
					binding = 0,
					visibility = {.Vertex, .Fragment},
					buffer = {type = .Uniform, minBindingSize = u64(entry.uniform_size)},
				},
			},
		)

		// Create uniform buffer
		// Round up to 16 bytes for WebGPU minimum buffer size
		buf_size := u64(align_up(entry.uniform_size, 16))
		entry.uniform_buffer = wgpu.DeviceCreateBuffer(
			r.device,
			&{
				label = "Custom Shader Uniform Buffer",
				usage = {.Uniform, .CopyDst},
				size = buf_size,
			},
		)

		// Create CPU staging buffer
		entry.uniform_data = make([]u8, entry.uniform_size)

		// Create bind group
		entry.bind_group = wgpu.DeviceCreateBindGroup(
			r.device,
			&{
				layout = entry.bind_group_layout,
				entryCount = 1,
				entries = &wgpu.BindGroupEntry {
					binding = 0,
					buffer = entry.uniform_buffer,
					size = u64(entry.uniform_size),
				},
			},
		)
	}

	// Create pipeline layout: [engine group 0, user group 1]
	if entry.bind_group_layout != nil {
		layouts := [2]wgpu.BindGroupLayout{r.bind_group_layout, entry.bind_group_layout}
		entry.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			r.device,
			&{bindGroupLayoutCount = 2, bindGroupLayouts = &layouts[0]},
		)
	} else {
		// No user uniforms — still need a pipeline with just group 0
		entry.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			r.device,
			&{bindGroupLayoutCount = 1, bindGroupLayouts = &r.bind_group_layout},
		)
	}

	// Create render pipeline (same vertex layout as default)
	entry.pipeline = create_render_pipeline(
		r.device,
		entry.pipeline_layout,
		entry.module,
		entry.vertex_entry,
		entry.fragment_entry,
	)

	// Store in handle map and return the handle.
	handle, _ := hm.add(&r.shaders, entry)
	return handle
}

@(private = "package")
renderer_set_shader_uniform :: proc(handle: core.Shader_Handle, name: string, value: any) {
	entry, ok := hm.get(&renderer.shaders, handle)
	if !ok {
		fmt.eprintf("[shader] invalid shader handle\n")
		return
	}

	uniform: Shader_Uniform
	uniform, ok = entry.uniforms[name]
	if !ok {
		fmt.eprintf("[shader] unknown uniform: %s\n", name)
		return
	}

	dst := entry.uniform_data[uniform.offset:][:uniform.size]

	// Copy the value bytes into the staging buffer
	src_ptr := value.data
	src_size := 0

	#partial switch uniform.type {
	case .F32:
		src_size = 4
	case .I32:
		src_size = 4
	case .U32:
		src_size = 4
	case .Vec2F32:
		src_size = 8
	case .Vec3F32:
		src_size = 12
	case .Vec4F32:
		src_size = 16
	case .Mat4x4F32:
		src_size = 64
	}

	if src_size > 0 && src_size <= uniform.size {
		src_bytes := ([^]u8)(src_ptr)[:src_size]
		copy(dst, src_bytes)
	}

	entry.uniform_dirty = true
}

@(private = "package")
renderer_set_shader :: proc(handle: core.Shader_Handle) {
	r := &renderer
	if r.active_shader != handle {
		renderer_flush()
		r.active_shader = handle
	}
}

@(private = "package")
renderer_reset_shader :: proc() {
	r := &renderer
	if hm.is_valid(&r.shaders, r.active_shader) {
		renderer_flush()
		r.active_shader = {}
	}
}

@(private = "package")
renderer_destroy_shader :: proc(handle: core.Shader_Handle) {
	entry, ok := hm.get(&renderer.shaders, handle)
	if !ok {return}

	if entry.bind_group != nil {wgpu.BindGroupRelease(entry.bind_group)}
	if entry.bind_group_layout != nil {wgpu.BindGroupLayoutRelease(entry.bind_group_layout)}
	if entry.uniform_buffer != nil {wgpu.BufferRelease(entry.uniform_buffer)}
	if entry.pipeline != nil {wgpu.RenderPipelineRelease(entry.pipeline)}
	if entry.pipeline_layout != nil {wgpu.PipelineLayoutRelease(entry.pipeline_layout)}
	if entry.module != nil {wgpu.ShaderModuleRelease(entry.module)}

	if entry.uniform_data != nil {
		delete(entry.uniform_data)
	}

	// Free uniform map keys
	for key in entry.uniforms {
		delete(key)
	}
	delete(entry.uniforms)

	delete(entry.vertex_entry)
	delete(entry.fragment_entry)

	hm.remove(&renderer.shaders, handle)
}
