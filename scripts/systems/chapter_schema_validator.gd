## Hand-rolled JSON Schema validation for the chapter content layer.
##
## Mirrors DialogueSchemaValidator exactly: interprets the same subset of
## JSON Schema (draft 2020-12) that content/chapters/chapter.schema.json
## actually uses - type, required, properties/additionalProperties, items,
## minItems/maxItems, minLength, const, enum, and $ref into $defs. Not a
## general-purpose schema engine, just enough to check the one shape this
## project defines.
##
## JSON.parse_string() has no integer type: every JSON number decodes as
## TYPE_FLOAT, so "type": "integer" accepts a float with no fractional part
## rather than requiring TYPE_INT.
class_name ChapterSchemaValidator
extends RefCounted

const SCHEMA_PATH := "res://content/chapters/chapter.schema.json"


## Loads and parses the project's chapter schema. Returns an empty
## Dictionary (falsy-ish via .is_empty()) on failure.
static func load_schema() -> Dictionary:
	var file := FileAccess.open(SCHEMA_PATH, FileAccess.READ)
	if file == null:
		push_error("ChapterSchemaValidator: could not open schema at %s (error %d)" % [SCHEMA_PATH, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("ChapterSchemaValidator: schema at %s did not parse to a JSON object" % SCHEMA_PATH)
		return {}
	return parsed


## Parses raw JSON text and validates it against `schema`. Returns
## {"ok": bool, "errors": Array[String], "data": Variant}; `data` is the
## parsed content (or null if it failed to parse as JSON at all).
static func validate_text(json_text: String, schema: Dictionary, source_label: String) -> Dictionary:
	var errors: Array[String] = []
	var parse_result := JSON.new()
	var err := parse_result.parse(json_text)
	if err != OK:
		errors.append("%s: invalid JSON at line %d: %s" % [source_label, parse_result.get_error_line(), parse_result.get_error_message()])
		return {"ok": false, "errors": errors, "data": null}
	var data: Variant = parse_result.get_data()
	_validate_node(data, schema, schema, source_label, errors)
	return {"ok": errors.is_empty(), "errors": errors, "data": data}


## Convenience wrapper: reads `path`, then validates it. Returns the same
## shape as validate_text().
static func validate_file(path: String, schema: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["%s: could not open file (error %d)" % [path, FileAccess.get_open_error()]], "data": null}
	var text := file.get_as_text()
	file.close()
	return validate_text(text, schema, path)


static func _resolve_ref(ref: String, root: Dictionary) -> Dictionary:
	if not ref.begins_with("#/"):
		push_error("ChapterSchemaValidator: unsupported $ref '%s' (only local '#/...' refs are handled)" % ref)
		return {}
	var node: Variant = root
	for part in ref.substr(2).split("/"):
		if not (node is Dictionary) or not node.has(part):
			push_error("ChapterSchemaValidator: $ref '%s' does not resolve against the schema" % ref)
			return {}
		node = node[part]
	if not (node is Dictionary):
		push_error("ChapterSchemaValidator: $ref '%s' does not resolve to an object" % ref)
		return {}
	return node


static func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return "object"
		TYPE_ARRAY:
			return "array"
		TYPE_STRING:
			return "string"
		TYPE_BOOL:
			return "boolean"
		TYPE_FLOAT, TYPE_INT:
			return "number"
		TYPE_NIL:
			return "null"
		_:
			return "unknown"


## Validates `value` against `schema_node`, appending human-readable,
## path-anchored errors (offending path first) to `errors`. `root` is the
## whole schema document, needed to resolve $ref.
static func _validate_node(value: Variant, schema_node: Dictionary, root: Dictionary, path: String, errors: Array[String]) -> void:
	if schema_node.has("$ref"):
		schema_node = _resolve_ref(schema_node["$ref"], root)
		if schema_node.is_empty():
			errors.append("%s: schema $ref could not be resolved" % path)
			return

	if schema_node.has("type"):
		var expected: String = schema_node["type"]
		var actual := _type_name(value)
		var matches := actual == expected
		if expected == "integer":
			matches = actual == "number" and float(value) == round(float(value))
		if not matches:
			errors.append("%s: expected type '%s', found '%s'" % [path, expected, actual])
			return

	if schema_node.has("const") and value != schema_node["const"]:
		errors.append("%s: expected constant value %s, found %s" % [path, schema_node["const"], value])

	match typeof(value):
		TYPE_STRING:
			_validate_string(value, schema_node, path, errors)
		TYPE_ARRAY:
			_validate_array(value, schema_node, root, path, errors)
		TYPE_DICTIONARY:
			_validate_object(value, schema_node, root, path, errors)


static func _validate_string(value: String, schema_node: Dictionary, path: String, errors: Array[String]) -> void:
	if schema_node.has("minLength") and value.length() < int(schema_node["minLength"]):
		errors.append("%s: string is empty or shorter than the required minimum length %d" % [path, int(schema_node["minLength"])])
	if schema_node.has("enum") and not (schema_node["enum"] as Array).has(value):
		errors.append("%s: value '%s' is not one of the allowed enum values %s" % [path, value, schema_node["enum"]])


static func _validate_array(value: Array, schema_node: Dictionary, root: Dictionary, path: String, errors: Array[String]) -> void:
	if schema_node.has("minItems") and value.size() < int(schema_node["minItems"]):
		errors.append("%s: array has %d item(s), expected at least %d" % [path, value.size(), int(schema_node["minItems"])])
	if schema_node.has("maxItems") and value.size() > int(schema_node["maxItems"]):
		errors.append("%s: array has %d item(s), expected at most %d" % [path, value.size(), int(schema_node["maxItems"])])
	if schema_node.has("items"):
		var item_schema: Dictionary = schema_node["items"]
		for i in value.size():
			_validate_node(value[i], item_schema, root, "%s[%d]" % [path, i], errors)


static func _validate_object(value: Dictionary, schema_node: Dictionary, root: Dictionary, path: String, errors: Array[String]) -> void:
	if schema_node.has("minProperties") and value.size() < int(schema_node["minProperties"]):
		errors.append("%s: object has %d propert(y/ies), expected at least %d" % [path, value.size(), int(schema_node["minProperties"])])

	if schema_node.has("required"):
		for key in (schema_node["required"] as Array):
			if not value.has(key):
				errors.append("%s: missing required key '%s'" % [path, key])

	var properties: Dictionary = schema_node.get("properties", {})
	for key in value.keys():
		if properties.has(key):
			_validate_node(value[key], properties[key], root, "%s.%s" % [path, key], errors)
		elif schema_node.get("additionalProperties", true) == false:
			errors.append("%s: unexpected key '%s' not allowed by the schema" % [path, key])
