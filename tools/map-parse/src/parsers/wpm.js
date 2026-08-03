import { BufferReader } from "../buffer-reader.js";

/**
 * war3map.wpm — Path Map。
 * 分辨率 = mapWidth*4 × mapHeight*4；每字节为寻路格 flags。
 *
 * flags:
 *   0x02 no walk | 0x04 no fly | 0x08 no build
 *   0x20 blight  | 0x40 no water | 0x80 unknown
 *
 * @param {Buffer} buffer
 */
export function parseWpm(buffer) {
  const r = new BufferReader(buffer);
  const magic = r.readFourCC();
  if (magic !== "MP3W") {
    throw new Error(`war3map.wpm: bad magic ${JSON.stringify(magic)}`);
  }
  const formatVersion = r.readInt32();
  const width = r.readInt32();
  const height = r.readInt32();
  if (width <= 0 || height <= 0) {
    throw new Error(`war3map.wpm: invalid size ${width}x${height}`);
  }
  const expect = width * height;
  if (r.remaining < expect) {
    throw new Error(`war3map.wpm: need ${expect} bytes, have ${r.remaining}`);
  }
  const cells = Buffer.from(r.peekBytes(expect));
  r.skip(expect);

  return {
    formatVersion,
    width,
    height,
    cellSize: 32,
    cellsBase64: cells.toString("base64"),
    _bytesRemaining: r.remaining,
  };
}
