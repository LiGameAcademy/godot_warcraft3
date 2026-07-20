import { BufferReader } from "../buffer-reader.js";

/**
 * @param {BufferReader} r
 */
function readItemSets(r) {
  const setCount = r.readInt32();
  const sets = [];
  for (let s = 0; s < setCount; s += 1) {
    const itemCount = r.readInt32();
    const items = [];
    for (let i = 0; i < itemCount; i += 1) {
      items.push({ id: r.readFourCC(), chance: r.readInt32() });
    }
    sets.push(items);
  }
  return sets;
}

/**
 * Classic TFT war3map.doo (doodads/trees), format version 8.
 * @param {Buffer} buffer
 */
export function parseDoodadsDoo(buffer) {
  const r = new BufferReader(buffer);
  const magic = r.readFourCC();
  if (magic !== "W3do") {
    throw new Error(`Invalid doodads magic: ${JSON.stringify(magic)}`);
  }

  const version = r.readInt32();
  const subversion = r.readInt32();
  const count = r.readInt32();
  const doodads = [];

  for (let i = 0; i < count; i += 1) {
    const id = r.readFourCC();
    const variation = r.readInt32();
    const x = r.readFloat();
    const y = r.readFloat();
    const z = r.readFloat();
    const angle = r.readFloat();
    const scaleX = r.readFloat();
    const scaleY = r.readFloat();
    const scaleZ = r.readFloat();
    const flags = r.readUInt8();
    const life = r.readUInt8();
    const itemTablePtr = r.readInt32();
    const droppedItemSets = readItemSets(r);
    const creationNumber = r.readInt32();

    doodads.push({
      id,
      variation,
      position: { x, y, z },
      angle,
      angleDegrees: (angle * 180) / Math.PI,
      scale: { x: scaleX, y: scaleY, z: scaleZ },
      flags,
      life,
      itemTablePtr,
      droppedItemSets,
      creationNumber,
    });
  }

  let specialDoodads = [];
  if (r.remaining >= 8) {
    const specialVersion = r.readInt32();
    const specialCount = r.readInt32();
    specialDoodads = [];
    for (let i = 0; i < specialCount; i += 1) {
      specialDoodads.push({
        id: r.readFourCC(),
        z: r.readInt32(),
        x: r.readInt32(),
        y: r.readInt32(),
        specialVersion,
      });
    }
  }

  // Tally by type id
  /** @type {Record<string, number>} */
  const byId = {};
  for (const d of doodads) {
    byId[d.id] = (byId[d.id] ?? 0) + 1;
  }

  return {
    formatVersion: version,
    subversion,
    count: doodads.length,
    byId,
    doodads,
    specialDoodads,
    _bytesRemaining: r.remaining,
  };
}
