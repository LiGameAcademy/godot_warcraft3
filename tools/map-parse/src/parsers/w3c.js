import { BufferReader } from "../buffer-reader.js";

/**
 * war3map.w3c cameras.
 * @param {Buffer} buffer
 */
export function parseW3c(buffer) {
  const r = new BufferReader(buffer);
  const version = r.readInt32();
  const count = r.readInt32();
  const cameras = [];

  for (let i = 0; i < count; i += 1) {
    cameras.push({
      target: { x: r.readFloat(), y: r.readFloat() },
      zOffset: r.readFloat(),
      rotation: r.readFloat(),
      angleOfAttack: r.readFloat(),
      distance: r.readFloat(),
      roll: r.readFloat(),
      fieldOfView: r.readFloat(),
      farClipping: r.readFloat(),
      unknown: r.readFloat(),
      name: r.readString(),
    });
  }

  return { formatVersion: version, count: cameras.length, cameras, _bytesRemaining: r.remaining };
}
