extends Node
#LogPruner: 限制 user://logs 下 Godot 自动 rotate 出的 *.log 文件数量。
#Godot 4 在 debug/file_logging 启用时, 每次启动会先把上次的 godot.log
#复制成 godot<时间戳>.log 再开新文件, 不会自动清理。
#我们保留最近 KEEP_FILES 份, 删除更老的, 让日志目录可控。

const KEEP_FILES: int = 7
const ACTIVE_LOG: String = "godot.log"

func _ready() -> void:
	var dir_path: String = "user://logs"
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	var entries: PackedStringArray = dir.get_files()
	var history: Array[String] = []
	for fname in entries:
		if fname.ends_with(".log") and fname != ACTIVE_LOG:
			history.append(fname)
	# Godot 把历史文件命名为 godot<ISO 时间戳>.log, 字典序就是时间序
	history.sort()
	while history.size() > KEEP_FILES:
		var victim: String = history.pop_front()
		dir.remove(victim)