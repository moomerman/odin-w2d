package renderer_wgpu

import "core:strings"

// Parse a simple non-negative integer from a string. Returns 0 on failure.
parse_int_simple :: proc(s: string) -> int {
	result := 0
	for c in s {
		if c < '0' || c > '9' {break}
		result = result * 10 + int(c - '0')
	}
	return result
}

// WGSL type information for uniform layout computation.
WGSL_Type :: enum {
	F32,
	I32,
	U32,
	Vec2F32,
	Vec3F32,
	Vec4F32,
	Mat4x4F32,
	Struct, // user-defined struct
}

// A single field within a WGSL struct.
WGSL_Field :: struct {
	name:        string,
	type:        WGSL_Type,
	struct_name: string, // non-empty when type == .Struct
	offset:      int, // byte offset within the struct (computed)
	size:        int, // byte size (computed)
	align:       int, // alignment requirement (computed)
}

// A parsed WGSL struct definition.
WGSL_Struct :: struct {
	name:   string,
	fields: [dynamic]WGSL_Field,
	size:   int, // total size including padding
	align:  int, // struct alignment (max field alignment)
}

// A parsed @group/@binding declaration.
WGSL_Binding :: struct {
	group:     int,
	binding:   int,
	name:      string,
	type:      string, // "uniform", "sampler", "texture_2d"
	type_name: string, // the struct/type name for uniforms
}

// Result of parsing a WGSL source string.
WGSL_Parse_Result :: struct {
	structs:        [dynamic]WGSL_Struct,
	bindings:       [dynamic]WGSL_Binding,
	vertex_entry:   string,
	fragment_entry: string,
}

// Returns (size, alignment) for a WGSL primitive type.
wgsl_type_layout :: proc(type: WGSL_Type) -> (size: int, align_: int) {
	switch type {
	case .F32:
		return 4, 4
	case .I32:
		return 4, 4
	case .U32:
		return 4, 4
	case .Vec2F32:
		return 8, 8
	case .Vec3F32:
		return 12, 16 // vec3 has alignment of 16 in WGSL
	case .Vec4F32:
		return 16, 16
	case .Mat4x4F32:
		return 64, 16
	case .Struct:
		return 0, 0 // looked up from parsed struct
	}
	return 0, 0
}

// Parse a WGSL type name string into a WGSL_Type enum.
parse_wgsl_type :: proc(type_str: string) -> (type: WGSL_Type, is_struct: bool) {
	s := strings.trim_space(type_str)
	switch s {
	case "f32":
		return .F32, false
	case "i32":
		return .I32, false
	case "u32":
		return .U32, false
	case "vec2<f32>":
		return .Vec2F32, false
	case "vec2f":
		return .Vec2F32, false
	case "vec3<f32>":
		return .Vec3F32, false
	case "vec3f":
		return .Vec3F32, false
	case "vec4<f32>":
		return .Vec4F32, false
	case "vec4f":
		return .Vec4F32, false
	case "mat4x4<f32>":
		return .Mat4x4F32, false
	case "mat4x4f":
		return .Mat4x4F32, false
	}
	return .Struct, true
}

// Round up `offset` to the next multiple of `align_`.
align_up :: proc(offset: int, align_: int) -> int {
	if align_ == 0 {return offset}
	return (offset + align_ - 1) & ~(align_ - 1)
}

// Find a parsed struct by name. Returns pointer or nil.
find_struct :: proc(structs: ^[dynamic]WGSL_Struct, name: string) -> ^WGSL_Struct {
	for &s in structs {
		if s.name == name {return &s}
	}
	return nil
}

// Compute layout (offsets, sizes, alignments) for all fields in a struct.
compute_struct_layout :: proc(s: ^WGSL_Struct, all_structs: ^[dynamic]WGSL_Struct) {
	offset := 0
	max_align := 4 // minimum struct alignment

	for &field in s.fields {
		if field.type == .Struct {
			// Look up the referenced struct
			ref := find_struct(all_structs, field.struct_name)
			if ref != nil {
				field.size = ref.size
				field.align = ref.align
			}
		} else {
			field.size, field.align = wgsl_type_layout(field.type)
		}

		// Align field offset
		offset = align_up(offset, field.align)
		field.offset = offset
		offset += field.size

		if field.align > max_align {
			max_align = field.align
		}
	}

	// Struct size must be rounded up to struct alignment
	s.align = max_align
	s.size = align_up(offset, max_align)
}

// Parse a WGSL source string, extracting struct definitions, bindings, and entry points.
parse_wgsl :: proc(source: string) -> WGSL_Parse_Result {
	result: WGSL_Parse_Result

	lines := strings.split_lines(source)
	defer delete(lines)

	i := 0
	for i < len(lines) {
		line := strings.trim_space(lines[i])

		// Skip empty lines and comments
		if len(line) == 0 || strings.has_prefix(line, "//") {
			i += 1
			continue
		}

		// Parse struct definitions
		if strings.has_prefix(line, "struct ") {
			struct_name := strings.trim_space(line[len("struct "):])
			// Remove trailing { if on same line
			if strings.has_suffix(struct_name, "{") {
				struct_name = strings.trim_space(struct_name[:len(struct_name) - 1])
			}

			s := WGSL_Struct {
				name = strings.clone(struct_name),
			}

			i += 1
			// Parse fields until closing brace
			for i < len(lines) {
				field_line := strings.trim_space(lines[i])
				if field_line == "}" || field_line == "};" {
					break
				}
				i += 1

				// Skip empty lines, comments, and lines with only attributes
				if len(field_line) == 0 || strings.has_prefix(field_line, "//") {
					continue
				}

				// Strip attributes like @location(0), @builtin(position)
				clean := field_line
				for strings.has_prefix(clean, "@") {
					// Skip past the attribute
					paren_depth := 0
					j := 0
					for j < len(clean) {
						if clean[j] == '(' {paren_depth += 1}
						if clean[j] == ')' {
							paren_depth -= 1
							if paren_depth == 0 {
								j += 1
								break
							}
						}
						j += 1
					}
					clean = strings.trim_space(clean[j:])
				}

				// Parse "name: type" or "name: type,"
				colon_idx := strings.index(clean, ":")
				if colon_idx < 0 {continue}

				field_name := strings.trim_space(clean[:colon_idx])
				field_type_str := strings.trim_space(clean[colon_idx + 1:])

				// Remove trailing comma or semicolon
				field_type_str = strings.trim_right(field_type_str, ",;")
				field_type_str = strings.trim_space(field_type_str)

				field_type, is_struct := parse_wgsl_type(field_type_str)

				field := WGSL_Field {
					name = strings.clone(field_name),
					type = field_type,
				}
				if is_struct {
					field.struct_name = strings.clone(field_type_str)
				}

				append(&s.fields, field)
			}

			compute_struct_layout(&s, &result.structs)
			append(&result.structs, s)
			i += 1
			continue
		}

		// Parse binding declarations: @group(N) @binding(N) var...
		if strings.has_prefix(line, "@group(") || strings.has_prefix(line, "@group (") {
			group, binding_num := -1, -1
			rest := line

			// Parse @group(N)
			if idx := strings.index(rest, "@group("); idx >= 0 {
				start := idx + len("@group(")
				end := strings.index(rest[start:], ")")
				if end >= 0 {
					group = parse_int_simple(rest[start:][:end])
					rest = strings.trim_space(rest[start + end + 1:])
				}
			} else if idx2 := strings.index(rest, "@group ("); idx2 >= 0 {
				start := idx2 + len("@group (")
				end := strings.index(rest[start:], ")")
				if end >= 0 {
					group = parse_int_simple(rest[start:][:end])
					rest = strings.trim_space(rest[start + end + 1:])
				}
			}

			// Parse @binding(N)
			if idx := strings.index(rest, "@binding("); idx >= 0 {
				start := idx + len("@binding(")
				end := strings.index(rest[start:], ")")
				if end >= 0 {
					binding_num = parse_int_simple(rest[start:][:end])
					rest = strings.trim_space(rest[start + end + 1:])
				}
			} else if idx2 := strings.index(rest, "@binding ("); idx2 >= 0 {
				start := idx2 + len("@binding (")
				end := strings.index(rest[start:], ")")
				if end >= 0 {
					binding_num = parse_int_simple(rest[start:][:end])
					rest = strings.trim_space(rest[start + end + 1:])
				}
			}

			if group >= 0 && binding_num >= 0 {
				b := WGSL_Binding {
					group   = group,
					binding = binding_num,
				}

				// Parse var<uniform>, var (sampler), var (texture)
				if strings.has_prefix(rest, "var<uniform>") {
					after_var := strings.trim_space(rest[len("var<uniform>"):])
					colon := strings.index(after_var, ":")
					if colon >= 0 {
						b.name = strings.clone(strings.trim_space(after_var[:colon]))
						type_str := strings.trim_space(after_var[colon + 1:])
						type_str = strings.trim_right(type_str, ";")
						type_str = strings.trim_space(type_str)
						b.type = "uniform"
						b.type_name = strings.clone(type_str)
					}
				} else if strings.has_prefix(rest, "var") {
					after_var := strings.trim_space(rest[len("var"):])
					colon := strings.index(after_var, ":")
					if colon >= 0 {
						b.name = strings.clone(strings.trim_space(after_var[:colon]))
						type_str := strings.trim_space(after_var[colon + 1:])
						type_str = strings.trim_right(type_str, ";")
						type_str = strings.trim_space(type_str)
						if strings.has_prefix(type_str, "sampler") {
							b.type = "sampler"
						} else if strings.has_prefix(type_str, "texture_2d") {
							b.type = "texture_2d"
						} else {
							b.type = type_str
						}
						b.type_name = strings.clone(type_str)
					}
				}

				append(&result.bindings, b)
			}

			i += 1
			continue
		}

		// Parse entry points: @vertex fn name(...) or @fragment fn name(...)
		if strings.has_prefix(line, "@vertex") {
			// The fn might be on this line or the next
			fn_line := line
			if !strings.contains(fn_line, "fn ") {
				i += 1
				if i < len(lines) {
					fn_line = strings.trim_space(lines[i])
				}
			}
			if fn_idx := strings.index(fn_line, "fn "); fn_idx >= 0 {
				after_fn := fn_line[fn_idx + 3:]
				paren := strings.index(after_fn, "(")
				if paren >= 0 {
					result.vertex_entry = strings.clone(strings.trim_space(after_fn[:paren]))
				}
			}
		} else if strings.has_prefix(line, "@fragment") {
			fn_line := line
			if !strings.contains(fn_line, "fn ") {
				i += 1
				if i < len(lines) {
					fn_line = strings.trim_space(lines[i])
				}
			}
			if fn_idx := strings.index(fn_line, "fn "); fn_idx >= 0 {
				after_fn := fn_line[fn_idx + 3:]
				paren := strings.index(after_fn, "(")
				if paren >= 0 {
					result.fragment_entry = strings.clone(strings.trim_space(after_fn[:paren]))
				}
			}
		}

		i += 1
	}

	return result
}

// Free all memory allocated by a parse result.
destroy_parse_result :: proc(result: ^WGSL_Parse_Result) {
	for &s in result.structs {
		delete(s.name)
		for &f in s.fields {
			delete(f.name)
			if len(f.struct_name) > 0 {
				delete(f.struct_name)
			}
		}
		delete(s.fields)
	}
	delete(result.structs)

	for &b in result.bindings {
		delete(b.name)
		delete(b.type_name)
	}
	delete(result.bindings)

	if len(result.vertex_entry) > 0 {delete(result.vertex_entry)}
	if len(result.fragment_entry) > 0 {delete(result.fragment_entry)}
}
