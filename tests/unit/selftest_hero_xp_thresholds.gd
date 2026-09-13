extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var failures := 0
	var expected := [0, 200, 500, 900, 1400, 2000, 2700, 3500, 4400, 5400]
	for level in range(1, 11):
		if HeroProgression.xp_threshold(level) != expected[level - 1]:
			failures += 1
			push_error("HERO XP: 累计门槛错误，等级 %d" % level)
	if HeroProgression.xp_for_next_level(2) != 500:
		failures += 1
	if HeroProgression.xp_for_next_level(10) != 5400:
		failures += 1
	var hero := Node3D.new()
	hero.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	HeroProgression.set_level(hero, 3, 650)
	var progress := HeroProgression.progress_for(hero)
	if progress.xp_in_level != 150 or progress.xp_need != 400:
		failures += 1
	HeroProgression.set_level(hero, 6)
	if HeroProgression.xp_of(hero) != 2000:
		failures += 1
	hero.free()
	print("selftest_hero_xp_thresholds: %s (14 checks)" % ["PASS" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)
