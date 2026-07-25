class_name WaterTypeDef
extends Resource

## Water.slk 一行定义（静态表数据；水面帧 PNG 解析在 Wc3WaterParams）。

const TABLE_NAME := "Water"
const SLK_REL_PATH := "TerrainArt/Water.json"
const PRIMARY_KEY := "waterID"

@export var water_id: String = "" 										## 水面ID	
@export var height: float = 0.0											## 高度
@export var impassable: bool = false									## 不可通行
@export var tex_file: String = "ReplaceableTextures/Water/Water"		## 纹理文件
@export var mm_alpha: int = 255											## 透明度
@export var mm_red: int = 255											## 红色
@export var mm_green: int = 255											## 绿色
@export var mm_blue: int = 255											## 蓝色
@export var num_tex: int = 0											## 纹理数量
@export var tex_rate: float = 15.0										## 纹理速率
@export var tex_offset: float = 0.0										## 纹理偏移
@export var alpha_mode: int = 0											## 透明度模式
@export var lighting: bool = true										## 光照
@export var cells: float = 2.0											## 单元格
@export var min_x: float = 0.0											## 最小X
@export var min_y: float = 0.0											## 最小Y
@export var min_z: float = 0.0											## 最小Z
@export var max_x: float = 0.0											## 最大X
@export var max_y: float = 0.0											## 最大Y
@export var max_z: float = 0.0											## 最大Z
@export var rate_x: float = 0.0											## 速率X
@export var rate_y: float = 0.0											## 速率Y
@export var rate_z: float = 0.0											## 速率Z
@export var rev_x: bool = false											## 反向X
@export var rev_y: bool = false											## 反向Y
@export var shore_in_fog: bool = false									## 海岸在雾中
@export var shore_dir: String = ""										## 海岸方向
@export var shore_s_file: String = ""									## 海岸S文件
@export var shore_s_var: int = 0										## 海岸S变量
@export var shore_oc_file: String = ""									## 海岸OC文件
@export var shore_oc_var: int = 0										## 海岸OC变量
@export var shore_ic_file: String = ""									## 海岸IC文件
@export var shore_ic_var: int = 0										## 海岸IC变量
@export var shallow_min: Color = Color(1, 1, 1, 1)						## 浅色最小值
@export var shallow_max: Color = Color(1, 1, 1, 1)						## 浅色最大值
@export var deep_min: Color = Color(1, 1, 1, 1)							## 深色最小值
@export var deep_max: Color = Color(1, 1, 1, 1)							## 深色最大值
@export var version: int = 0											## 版本
@export var in_beta: bool = false										## 是否在Beta版

## 地形集字母：waterID 首字符（LSha → L）。
func get_tileset_letter() -> String:
	if water_id.is_empty():
		return ""
	return water_id.substr(0, 1).to_upper()


## [static] 从SLK记录创建水面类型定义
## [param rec Dictionary] SLK记录
## [return WaterTypeDef] 水面类型定义
static func from_slk_record(rec: Dictionary) -> WaterTypeDef:
	var d := WaterTypeDef.new()
	d.water_id = str(rec.get("waterID", "")).strip_edges()
	d.height = float(rec.get("height", 0.0))
	d.impassable = int(rec.get("impassable", 0)) != 0
	d.tex_file = str(rec.get("texFile", "ReplaceableTextures\\Water\\Water")).replace("\\", "/").strip_edges()
	d.mm_alpha = int(rec.get("mmAlpha", 255))
	d.mm_red = int(rec.get("mmRed", 255))
	d.mm_green = int(rec.get("mmGreen", 255))
	d.mm_blue = int(rec.get("mmBlue", 255))
	d.num_tex = int(rec.get("numTex", 0))
	d.tex_rate = float(rec.get("texRate", 15))
	d.tex_offset = float(rec.get("texOffset", 0))
	d.alpha_mode = int(rec.get("alphaMode", 0))
	d.lighting = int(rec.get("lighting", 1)) != 0
	d.cells = float(rec.get("cells", 2))
	d.min_x = float(rec.get("minX", 0))
	d.min_y = float(rec.get("minY", 0))
	d.min_z = float(rec.get("minZ", 0))
	d.max_x = float(rec.get("maxX", 0))
	d.max_y = float(rec.get("maxY", 0))
	d.max_z = float(rec.get("maxZ", 0))
	d.rate_x = float(rec.get("rateX", 0))
	d.rate_y = float(rec.get("rateY", 0))
	d.rate_z = float(rec.get("rateZ", 0))
	d.rev_x = int(rec.get("revX", 0)) != 0
	d.rev_y = int(rec.get("revY", 0)) != 0
	d.shore_in_fog = int(rec.get("shoreInFog", 0)) != 0
	d.shore_dir = str(rec.get("shoreDir", "")).replace("\\", "/").strip_edges()
	d.shore_s_file = str(rec.get("shoreSFile", "")).strip_edges()
	d.shore_s_var = int(rec.get("shoreSVar", 0))
	d.shore_oc_file = str(rec.get("shoreOCFile", "")).strip_edges()
	d.shore_oc_var = int(rec.get("shoreOCVar", 0))
	d.shore_ic_file = str(rec.get("shoreICFile", "")).strip_edges()
	d.shore_ic_var = int(rec.get("shoreICVar", 0))
	d.shallow_min = _rgba(rec, "Smin")
	d.shallow_max = _rgba(rec, "Smax")
	d.deep_min = _rgba(rec, "Dmin")
	d.deep_max = _rgba(rec, "Dmax")
	d.version = int(rec.get("version", 0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d


## [static] 从SLK记录创建颜色
## [param rec Dictionary] SLK记录
## [param prefix String] 前缀
## [return Color] 颜色
static func _rgba(rec: Dictionary, prefix: String) -> Color:
	var r := float(rec.get(prefix + "_R", 255)) / 255.0
	var g := float(rec.get(prefix + "_G", 255)) / 255.0
	var b := float(rec.get(prefix + "_B", 255)) / 255.0
	var a := float(rec.get(prefix + "_A", 255)) / 255.0
	return Color(r, g, b, a)


## 向 DefStore 注册本表（由 Wc3DefStore._ready 调用）。
## [param store] DefStore
## [return void] 无返回值
static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("WaterTypeDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
