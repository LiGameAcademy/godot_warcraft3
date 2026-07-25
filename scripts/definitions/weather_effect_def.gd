class_name WeatherEffectDef
extends Resource

## Weather.slk 一行定义（静态表数据；粒子贴图路径解析另做）。

const TABLE_NAME := "Weather"
const SLK_REL_PATH := "TerrainArt/Weather.json"
const PRIMARY_KEY := "effectID"

@export var effect_id: String = ""
@export var name_key: String = ""
@export var tex_dir: String = ""
@export var tex_file: String = ""
@export var alpha_mode: int = 0
@export var use_fog: bool = false
@export var height: float = 0.0
@export var ang_x: float = 0.0
@export var ang_y: float = 0.0
@export var em_rate: float = 0.0
@export var lifespan: float = 0.0
@export var particles: int = 0
@export var veloc: float = 0.0
@export var accel: float = 0.0
@export var variance: float = 0.0
@export var tex_r: int = 1
@export var tex_c: int = 1
@export var head: bool = false
@export var tail: bool = false
@export var tail_len: float = 0.0
@export var latitude: float = 0.0
@export var longitude: float = 0.0
@export var mid_time: float = 0.5
@export var red_start: int = 255
@export var green_start: int = 255
@export var blue_start: int = 255
@export var red_mid: int = 255
@export var green_mid: int = 255
@export var blue_mid: int = 255
@export var red_end: int = 255
@export var green_end: int = 255
@export var blue_end: int = 255
@export var alpha_start: int = 255
@export var alpha_mid: int = 255
@export var alpha_end: int = 255
@export var scale_start: float = 1.0
@export var scale_mid: float = 1.0
@export var scale_end: float = 1.0
@export var h_uv_start: float = 0.0
@export var h_uv_mid: float = 0.0
@export var h_uv_end: float = 0.0
@export var t_uv_start: float = 0.0
@export var t_uv_mid: float = 0.0
@export var t_uv_end: float = 0.0
@export var ambient_sound: String = ""
@export var version: int = 0


static func from_slk_record(rec: Dictionary) -> WeatherEffectDef:
	var d := WeatherEffectDef.new()
	d.effect_id = str(rec.get("effectID", "")).strip_edges()
	d.name_key = str(rec.get("name", "")).strip_edges()
	d.tex_dir = str(rec.get("texDir", "")).replace("\\", "/").strip_edges()
	d.tex_file = str(rec.get("texFile", "")).strip_edges()
	d.alpha_mode = int(rec.get("alphaMode", 0))
	d.use_fog = int(rec.get("useFog", 0)) != 0
	d.height = float(rec.get("height", 0))
	d.ang_x = float(rec.get("angx", 0))
	d.ang_y = float(rec.get("angy", 0))
	d.em_rate = float(rec.get("emrate", 0))
	d.lifespan = float(rec.get("lifespan", 0))
	d.particles = int(rec.get("particles", 0))
	d.veloc = float(rec.get("veloc", 0))
	d.accel = float(rec.get("accel", 0))
	d.variance = float(rec.get("var", 0))
	d.tex_r = int(rec.get("texr", 1))
	d.tex_c = int(rec.get("texc", 1))
	d.head = int(rec.get("head", 0)) != 0
	d.tail = int(rec.get("tail", 0)) != 0
	d.tail_len = float(rec.get("taillen", 0))
	d.latitude = float(rec.get("lati", 0))
	d.longitude = float(rec.get("long", 0))
	d.mid_time = float(rec.get("midTime", 0.5))
	d.red_start = int(rec.get("redStart", 255))
	d.green_start = int(rec.get("greenStart", 255))
	d.blue_start = int(rec.get("blueStart", 255))
	d.red_mid = int(rec.get("redMid", 255))
	d.green_mid = int(rec.get("greenMid", 255))
	d.blue_mid = int(rec.get("blueMid", 255))
	d.red_end = int(rec.get("redEnd", 255))
	d.green_end = int(rec.get("greenEnd", 255))
	d.blue_end = int(rec.get("blueEnd", 255))
	d.alpha_start = int(rec.get("alphaStart", 255))
	d.alpha_mid = int(rec.get("alphaMid", 255))
	d.alpha_end = int(rec.get("alphaEnd", 255))
	d.scale_start = float(rec.get("scaleStart", 1))
	d.scale_mid = float(rec.get("scaleMid", 1))
	d.scale_end = float(rec.get("scaleEnd", 1))
	d.h_uv_start = float(rec.get("hUVStart", 0))
	d.h_uv_mid = float(rec.get("hUVMid", 0))
	d.h_uv_end = float(rec.get("hUVEnd", 0))
	d.t_uv_start = float(rec.get("tUVStart", 0))
	d.t_uv_mid = float(rec.get("tUVMid", 0))
	d.t_uv_end = float(rec.get("tUVEnd", 0))
	d.ambient_sound = str(rec.get("AmbientSound", "")).strip_edges()
	d.version = int(rec.get("version", 0))
	return d


static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("WeatherEffectDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
