extends RefCounted

const Merger: GDScript = preload("definition_layer_merge.gd")
const POLICY_PATH: String = "res://packages/content/definitions/layer_policy.json"

## Shared default profile is selected before catalog construction; restart to change.
static func read_rows(logical: String) -> Dictionary:
	var policy: Dictionary = RuntimeAssets.read_json_dict(POLICY_PATH)
	var profiles: Variant = policy.get("profiles")
	var profile: String = str(policy.get("default_profile", ""))
	if not profiles is Dictionary or not profiles.has(profile):
		push_error("Invalid definition layer policy: " + POLICY_PATH)
		return {}
	var roots: Variant = profiles[profile]
	if not roots is Array:
		push_error("Invalid definition profile: " + profile)
		return {}
	var layers: Array[Dictionary] = []
	for root: Variant in roots:
		if not root is String:
			push_error("Invalid definition root")
			return {}
		var source: String = str(root) + logical
		var resolved: String = RuntimeAssets.resolve(source)
		if resolved.is_empty():
			continue
		layers.append({"source": source, "text": RuntimeAssets.read_utf8_text(resolved)})
	var merged: Dictionary = Merger.merge_layers(layers)
	return merged["rows"] as Dictionary
