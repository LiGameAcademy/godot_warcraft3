extends RefCounted

## Pure field merge: missing inherits; explicit empty clears; object IDs retain case.
static func merge_layers(layers: Array[Dictionary]) -> Dictionary:
	var rows: Dictionary = {}
	var origins: Dictionary = {}
	var changes: Array[Dictionary] = []
	for layer: Dictionary in layers:
		var source: String = str(layer["source"])
		var text: String = str(layer["text"]).trim_prefix("\ufeff")
		var id: String = ""
		for raw: String in text.split("\n"):
			var line: String = raw.strip_edges()
			if line.is_empty() or line.begins_with("//") or line.begins_with(";"):
				continue
			if line.begins_with("[") and line.ends_with("]"):
				id = line.substr(1, line.length() - 2).strip_edges()
				if not id.is_empty() and not rows.has(id):
					rows[id] = {}
					origins[id] = {}
				continue
			var eq: int = line.find("=")
			if id.is_empty() or eq <= 0:
				continue
			var field: String = line.substr(0, eq).strip_edges().to_lower()
			var value: String = line.substr(eq + 1).strip_edges()
			if not value.contains('\",\"') and value.length() >= 2 and value.begins_with('"') and value.ends_with('"'):
				value = value.substr(1, value.length() - 2)
			var row: Dictionary = rows[id]
			var origin: Dictionary = origins[id]
			if row.has(field) and row[field] != value:
				changes.append({"object_id": id, "field": field,
					"previous": {"source": origin[field], "value": row[field]},
					"candidate": {"source": source, "value": value}})
			row[field] = value
			origin[field] = source
	return {"rows": rows, "origins": origins, "changes": changes}
