class_name MatchHotpathMetrics
extends RefCounted
## Opt-in, bounded per-window samples; disabled in ordinary matches.
const CAPACITY := 2048
static var enabled := false
static var _windows: Dictionary = {}

static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0

static func finish(label: StringName, started: int) -> void:
	if not enabled:
		return
	var elapsed := Time.get_ticks_usec() - started
	if not _windows.has(label):
		_windows[label] = {"count": 0, "total_us": 0, "samples": []}
	var w: Dictionary = _windows[label]
	var count: int = w.count
	var samples: Array = w.samples
	if samples.size() < CAPACITY:
		samples.append(elapsed)
	else:
		samples[count % CAPACITY] = elapsed
	w.samples = samples
	w.count = count + 1
	w.total_us += elapsed

static func drain() -> Dictionary:
	var out := {}
	for label in _windows:
		var w: Dictionary = _windows[label]
		var samples: Array = w.samples
		samples.sort()
		out[label] = {"calls": w.count, "total_ms": w.total_us / 1000.0,
			"mean_ms": w.total_us / (1000.0 * w.count),
			"recent_p95_ms": samples[mini(int(samples.size() * 0.95), samples.size() - 1)] / 1000.0}
	_windows.clear()
	return out
