/**
 * war3map.mmp — 菜单/编辑器小地图图标叠加层。
 *
 * Header:
 *   int32 unknown (usually 0)
 *   int32 count
 * Record (16 bytes each):
 *   int32 iconType  0=gold 1=neutral building 2=start 3=creepS 4=creepL
 *   int32 x         0..255 canvas
 *   int32 y         0..255 canvas（图像 y 向下；左上≈0x10）
 *   byte[4] BGRA    玩家色（出生点用）
 *
 * @param {Buffer} buf
 */
export function parseMmp(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 8) {
    throw new Error(`war3map.mmp 过短: ${buf?.length ?? 0}`);
  }
  const unknown = buf.readInt32LE(0);
  const count = buf.readInt32LE(4);
  if (count < 0 || count > 4096) {
    throw new Error(`war3map.mmp 图标数异常: ${count}`);
  }
  const need = 8 + count * 16;
  if (buf.length < need) {
    throw new Error(`war3map.mmp 截断: need=${need} got=${buf.length}`);
  }

  /** @type {Array<{type:number,x:number,y:number,color:[number,number,number,number],typeName:string}>} */
  const icons = [];
  for (let i = 0; i < count; i += 1) {
    const o = 8 + i * 16;
    const type = buf.readInt32LE(o);
    const x = buf.readInt32LE(o + 4);
    const y = buf.readInt32LE(o + 8);
    const b = buf[o + 12];
    const g = buf[o + 13];
    const r = buf[o + 14];
    const a = buf[o + 15];
    icons.push({
      type,
      typeName: iconTypeName(type),
      x,
      y,
      // 存成 RGBA，方便 Godot Color
      color: [r / 255, g / 255, b / 255, a / 255],
    });
  }

  return {
    unknown,
    count: icons.length,
    canvasSize: 256,
    icons,
    _bytesRemaining: buf.length - need,
  };
}

/** @param {number} t */
function iconTypeName(t) {
  switch (t) {
    case 0:
      return "gold";
    case 1:
      return "neutral_building";
    case 2:
      return "start_loc";
    case 3:
      return "creep_small";
    case 4:
      return "creep_large";
    default:
      return `unknown_${t}`;
  }
}
