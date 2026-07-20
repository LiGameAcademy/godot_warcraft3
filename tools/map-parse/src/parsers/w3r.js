import { BufferReader } from "../buffer-reader.js";

/**
 * war3map.w3r regions.
 * @param {Buffer} buffer
 */
export function parseW3r(buffer) {
  const r = new BufferReader(buffer);
  const version = r.readInt32();
  const count = r.readInt32();
  const regions = [];

  for (let i = 0; i < count; i += 1) {
    const left = r.readFloat();
    const right = r.readFloat();
    const bottom = r.readFloat();
    const top = r.readFloat();
    const name = r.readString();
    const index = r.readInt32();
    const weatherId = r.readFourCC();
    const ambientSound = r.readString();
    const colorB = r.readUInt8();
    const colorG = r.readUInt8();
    const colorR = r.readUInt8();
    r.readUInt8(); // end marker

    regions.push({
      name,
      index,
      bounds: { left, right, bottom, top },
      weatherId: weatherId === "\0\0\0\0" ? null : weatherId,
      ambientSound,
      color: [colorR, colorG, colorB],
    });
  }

  return { formatVersion: version, count: regions.length, regions, _bytesRemaining: r.remaining };
}
