package renderer_wgpu

import hm "core:container/handle_map"
import "core:fmt"
import "core:strings"
import "vendor:wgpu"

import core "../../core"

@(private = "package")
renderer_load_shader :: proc(wgsl_source: string) -> core.Shader_Handle {
	entry := shader_build_entry(wgsl_source)
	handle, _ := hm.add(&renderer.shaders, entry)
	return handle
}

// Compile WGSL source into a complete Shader_Entry (module, layouts,
// pipeline, uniform buffer + metadata). Shared by load and reload.
// Compilation errors are reported through wgpu's error mechanisms, not a
// return value — wrap the call in an error scope to detect them.
@(private = "file")
shader_build_entry :: proc(wgsl_source: string) -> Shader_Entry {
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

	// Collect all group 1 bindings: one optional uniform buffer plus any
	// number of texture_2d bindings. Samplers are not supported yet —
	// shaders wanting filtered sampling can reuse tex_sampler from group 0,
	// and exact texel reads (e.g. LUTs) use textureLoad with no sampler.
	uniform_struct_name: string
	for &b in parse.bindings {
		if b.group != 1 {continue}
		switch b.type {
		case "uniform":
			if len(uniform_struct_name) > 0 {
				fmt.eprintf(
					"[shader] only one group-1 uniform buffer is supported, ignoring: %s\n",
					b.name,
				)
				continue
			}
			uniform_struct_name = b.type_name
			entry.uniform_binding = u32(b.binding)
		case "texture_2d":
			if entry.textures == nil {
				entry.textures = make(map[string]Shader_Texture)
			}
			entry.textures[strings.clone(b.name)] = Shader_Texture {
				binding = u32(b.binding),
			}
		case "sampler":
			fmt.eprintf(
				"[shader] group-1 samplers are not supported yet (binding %q) — reuse tex_sampler from group 0\n",
				b.name,
			)
		case:
			fmt.eprintf(
				"[shader] unsupported group-1 binding type %q (binding %q)\n",
				b.type,
				b.name,
			)
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

	// Create uniform buffer and CPU staging buffer
	if entry.uniform_size > 0 {
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
		entry.uniform_data = make([]u8, entry.uniform_size)
	}

	// Create bind group layout for group 1 (user uniforms + textures)
	if entry.uniform_size > 0 || len(entry.textures) > 0 {
		layout_entries := make([dynamic]wgpu.BindGroupLayoutEntry, 0, 1 + len(entry.textures))
		defer delete(layout_entries)

		if entry.uniform_size > 0 {
			append(
				&layout_entries,
				wgpu.BindGroupLayoutEntry {
					binding = entry.uniform_binding,
					visibility = {.Vertex, .Fragment},
					buffer = {type = .Uniform, minBindingSize = u64(entry.uniform_size)},
				},
			)
		}
		for _, &tex in entry.textures {
			append(
				&layout_entries,
				wgpu.BindGroupLayoutEntry {
					binding = tex.binding,
					visibility = {.Vertex, .Fragment},
					texture = {sampleType = .Float, viewDimension = ._2D, multisampled = false},
				},
			)
		}

		entry.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			r.device,
			&{entryCount = uint(len(layout_entries)), entries = raw_data(layout_entries)},
		)

		// Create the initial bind group. Unset texture slots point at the
		// white texture so the shader is valid before assignment.
		entry.bind_group = shader_create_bind_group(&entry)
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

	return entry
}

// Release every GPU resource and allocation owned by a Shader_Entry.
// Shared by destroy and reload. Tolerates partially-built entries.
@(private = "file")
shader_release_entry :: proc(entry: ^Shader_Entry) {
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

	// Free texture binding map keys
	for key in entry.textures {
		delete(key)
	}
	delete(entry.textures)

	delete(entry.vertex_entry)
	delete(entry.fragment_entry)
}

// Recompile a custom shader from new WGSL source, swapping the program in
// place behind its existing handle. Returns false — leaving the previous
// program untouched — when compilation fails. Uniform values and texture
// bindings are carried over by name where they still match.
@(private = "package")
renderer_reload_shader :: proc(handle: core.Shader_Handle, wgsl_source: string) -> bool {
	r := &renderer

	old, ok := hm.get(&r.shaders, handle)
	if !ok {
		return false
	}

	// wgpu reports WGSL/pipeline errors through error scopes rather than
	// return values. Validation in wgpu-native is synchronous, but pump
	// InstanceProcessEvents once in case the callback is deferred.
	Error_Capture :: struct {
		fired:     bool,
		has_error: bool,
	}
	capture: Error_Capture

	wgpu.DevicePushErrorScope(r.device, .Validation)
	new_entry := shader_build_entry(wgsl_source)
	wgpu.DevicePopErrorScope(r.device, {
		mode = .AllowProcessEvents,
		callback = proc "c" (
			status: wgpu.PopErrorScopeStatus,
			type: wgpu.ErrorType,
			message: string,
			userdata1, userdata2: rawptr,
		) {
			capture := (^Error_Capture)(userdata1)
			capture.fired = true
			if status == .Success && type != .NoError {
				capture.has_error = true
				context = renderer.ctx
				fmt.eprintfln("[shader] reload failed: %s", message)
			}
		},
		userdata1 = &capture,
	})
	if !capture.fired {
		wgpu.InstanceProcessEvents(r.instance)
	}

	if capture.has_error {
		shader_release_entry(&new_entry)
		return false
	}

	// Carry over uniform values by name where the field is still compatible.
	for name, new_uniform in new_entry.uniforms {
		old_uniform, found := old.uniforms[name]
		if found && old_uniform.type == new_uniform.type && old_uniform.size == new_uniform.size {
			copy(
				new_entry.uniform_data[new_uniform.offset:][:new_uniform.size],
				old.uniform_data[old_uniform.offset:][:old_uniform.size],
			)
			new_entry.uniform_dirty = true
		}
	}

	// Carry over texture bindings by name. The bind group built during
	// shader_build_entry points at the white texture; marking it dirty makes
	// the next flush rebuild it with the carried-over handles.
	for name, &slot in new_entry.textures {
		if old_slot, found := old.textures[name]; found && old_slot.texture != {} {
			slot.texture = old_slot.texture
			new_entry.bind_group_dirty = true
		}
	}

	shader_release_entry(old)
	new_entry.handle = handle
	old^ = new_entry
	return true
}

// Build the group-1 bind group for a custom shader. Bind groups are immutable
// in wgpu, so texture changes require creating a new one. Texture slots that
// are unset — or whose texture has been destroyed — resolve to the white texture.
@(private = "package")
shader_create_bind_group :: proc(entry: ^Shader_Entry) -> wgpu.BindGroup {
	r := &renderer

	entries := make([dynamic]wgpu.BindGroupEntry, 0, 1 + len(entry.textures))
	defer delete(entries)

	if entry.uniform_buffer != nil {
		append(
			&entries,
			wgpu.BindGroupEntry {
				binding = entry.uniform_binding,
				buffer = entry.uniform_buffer,
				size = u64(entry.uniform_size),
			},
		)
	}
	for _, &tex in entry.textures {
		view := r.textures[r.white_texture].view
		if t, ok := &r.textures[tex.texture]; ok {
			view = t.view
		}
		append(&entries, wgpu.BindGroupEntry{binding = tex.binding, textureView = view})
	}

	if len(entries) == 0 {
		return nil
	}
	return wgpu.DeviceCreateBindGroup(
		r.device,
		&{
			layout = entry.bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries),
		},
	)
}

@(private = "package")
renderer_set_shader_texture :: proc(
	handle: core.Shader_Handle,
	name: string,
	texture: core.Texture_Handle,
) {
	r := &renderer

	entry, ok := hm.get(&r.shaders, handle)
	if !ok {
		fmt.eprintf("[shader] invalid shader handle\n")
		return
	}

	slot, slot_ok := &entry.textures[name]
	if !slot_ok {
		fmt.eprintf("[shader] unknown texture binding: %s\n", name)
		return
	}

	if _, tex_ok := r.textures[texture]; !tex_ok {
		fmt.eprintf("[shader] invalid texture handle for binding: %s\n", name)
		return
	}

	if slot.texture == texture {
		return
	}

	// Quads already batched were issued against the previous texture — draw
	// them before the bind group is rebuilt (same reason set_shader flushes).
	if r.batch.active_shader == handle {
		renderer_flush()
	}

	slot.texture = texture
	entry.bind_group_dirty = true
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
	if r.batch.active_shader != handle {
		renderer_flush()
		r.batch.active_shader = handle
	}
}

@(private = "package")
renderer_reset_shader :: proc() {
	r := &renderer
	if hm.is_valid(&r.shaders, r.batch.active_shader) {
		renderer_flush()
		r.batch.active_shader = {}
	}
}

@(private = "package")
renderer_destroy_shader :: proc(handle: core.Shader_Handle) {
	entry, ok := hm.get(&renderer.shaders, handle)
	if !ok {return}

	shader_release_entry(entry)
	hm.remove(&renderer.shaders, handle)
}
