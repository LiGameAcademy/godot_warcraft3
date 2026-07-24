extends SceneTree
## CliffTrans 目录 / 命名 / 四角查表自测。
## godot --headless -s res://tests/unit/selftest_cliff_trans_catalog.gd


const Catalog := preload("res://scripts/map/catalog/wc3_cliff_trans_catalog.gd")


func _init() -> void:
	var failed := 0
	failed += _test_parse()
	failed += _test_scan_cliff_trans()
	failed += _test_corners_lookup()
	failed += _test_city_subset()
	if failed == 0:
		print("selftest_cliff_trans_catalog: PASS")
		quit(0)
	else:
		push_error("selftest_cliff_trans_catalog: FAIL (%d)" % failed)
		quit(1)


func _test_parse() -> int:
	var p: Dictionary = Catalog.parse_basename("CliffTransAAHL0")
	if not bool(p.get("ok", false)):
		push_error("parse AAHL failed")
		return 1
	if str(p["family"]) != "CliffTrans" or str(p["tag"]) != "AAHL" or int(p["variation"]) != 0:
		push_error("parse AAHL mismatch %s" % str(p))
		return 1
	var p2: Dictionary = Catalog.parse_basename("CityCliffTransLHBA0")
	if str(p2.get("family", "")) != "CityCliffTrans" or str(p2.get("tag", "")) != "LHBA":
		push_error("parse City failed %s" % str(p2))
		return 1
	print("  parse OK")
	return 0


func _test_scan_cliff_trans() -> int:
	var cat = Catalog.load_cliff_trans()
	var n: int = cat.list_tags().size()
	if n < 30:
		push_error("CliffTrans tags too few: %d" % n)
		return 1
	if not cat.has_tag("AAHL"):
		push_error("missing AAHL")
		return 1
	var path: String = cat.resolve_path_for_tag("AAHL", 0)
	if path.is_empty() or not RuntimeAssets.file_exists(path):
		push_error("AAHL path missing: %s" % path)
		return 1
	var has_c := false
	var has_x := false
	for t in cat.list_tags():
		if str(t).contains("C"):
			has_c = true
		if str(t).contains("X"):
			has_x = true
	if not has_c or not has_x:
		push_error("expected C and X in catalog (C=%s X=%s)" % [has_c, has_x])
		return 1
	print("  scan CliffTrans OK tags=%d path=%s" % [n, path.get_file()])
	return 0


func _test_corners_lookup() -> int:
	var cat = Catalog.load_cliff_trans()
	var tag: String = Catalog.tag_from_corners("A", "A", "H", "L")
	if tag != "AAHL":
		push_error("tag_from_corners want AAHL got %s" % tag)
		return 1
	var path: String = cat.resolve_path_for_corners("A", "A", "H", "L")
	if path.is_empty():
		push_error("resolve AAHL empty")
		return 1
	var miss: String = cat.resolve_path_for_corners("A", "A", "A", "A")
	if not miss.is_empty():
		push_error("AAAA should miss, got %s" % miss)
		return 1
	print("  corners lookup OK")
	return 0


func _test_city_subset() -> int:
	var city = Catalog.load_city_cliff_trans()
	var cliff = Catalog.load_cliff_trans()
	if city.list_tags().is_empty():
		push_error("CityCliffTrans empty")
		return 1
	for t in city.list_tags():
		if not cliff.has_tag(str(t)):
			push_error("City tag %s not in CliffTrans" % str(t))
			return 1
	print("  city subset OK tags=%d" % city.list_tags().size())
	return 0
