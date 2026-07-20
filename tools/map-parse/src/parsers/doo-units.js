import { BufferReader } from "../buffer-reader.js";

/**
 * @param {BufferReader} r
 */
function readDroppedItemSets(r) {
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
 * Classic TFT war3mapUnits.doo, format version 8.
 * @param {Buffer} buffer
 */
export function parseUnitsDoo(buffer) {
  const r = new BufferReader(buffer);
  const magic = r.readFourCC();
  if (magic !== "W3do") {
    throw new Error(`Invalid units magic: ${JSON.stringify(magic)}`);
  }

  const version = r.readInt32();
  const subversion = r.readInt32();
  const count = r.readInt32();
  const units = [];

  for (let i = 0; i < count; i += 1) {
    const typeId = r.readFourCC();
    const variation = r.readInt32();
    const x = r.readFloat();
    const y = r.readFloat();
    const z = r.readFloat();
    const angle = r.readFloat();
    const scaleX = r.readFloat();
    const scaleY = r.readFloat();
    const scaleZ = r.readFloat();
    const flags = r.readUInt8();
    const owner = r.readInt32();
    const unknown1 = r.readUInt8();
    const unknown2 = r.readUInt8();
    const hitPoints = r.readInt32();
    const manaPoints = r.readInt32();
    const itemTablePtr = r.readInt32();
    const droppedItemSets = readDroppedItemSets(r);
    const goldAmount = r.readInt32();
    const targetAcquisition = r.readFloat();
    const heroLevel = r.readInt32();

    // TFT: hero attributes present when subversion >= 11
    let strength = 0;
    let agility = 0;
    let intelligence = 0;
    if (subversion >= 11) {
      strength = r.readInt32();
      agility = r.readInt32();
      intelligence = r.readInt32();
    }

    const inventoryCount = r.readInt32();
    const inventory = [];
    for (let n = 0; n < inventoryCount; n += 1) {
      inventory.push({ slot: r.readInt32(), id: r.readFourCC() });
    }

    const abilityCount = r.readInt32();
    const abilities = [];
    for (let n = 0; n < abilityCount; n += 1) {
      abilities.push({
        id: r.readFourCC(),
        active: r.readInt32(),
        level: r.readInt32(),
      });
    }

    // Classic TFT: non-random units use flag -1 with no payload.
    // Flag 0 still carries a 4-byte level/class payload (random any).
    const randomFlag = r.readInt32();
    /** @type {object} */
    let random = { flag: randomFlag };
    if (randomFlag === 0) {
      const levelBytes = r.readBytes(3);
      const itemClass = r.readUInt8();
      let level = levelBytes[0] | (levelBytes[1] << 8) | (levelBytes[2] << 16);
      if (level & 0x800000) level -= 0x1000000;
      random = { flag: 0, level, itemClass };
    } else if (randomFlag === 1) {
      random = {
        flag: 1,
        groupNumber: r.readInt32(),
        columnNumber: r.readInt32(),
      };
    } else if (randomFlag === 2) {
      const n = r.readInt32();
      const choices = [];
      for (let c = 0; c < n; c += 1) {
        choices.push({ id: r.readFourCC(), chance: r.readInt32() });
      }
      random = { flag: 2, choices };
    } else if (randomFlag === -1) {
      random = { flag: -1, kind: "none" };
    } else {
      throw new Error(
        `Unsupported random unit flag ${randomFlag} at offset ${r.offset}`,
      );
    }

    const customColor = r.readInt32();
    const waygate = r.readInt32();
    const creationNumber = r.readInt32();

    units.push({
      typeId,
      variation,
      position: { x, y, z },
      angle,
      angleDegrees: (angle * 180) / Math.PI,
      scale: { x: scaleX, y: scaleY, z: scaleZ },
      flags,
      owner,
      unknown: [unknown1, unknown2],
      hitPoints,
      manaPoints,
      itemTablePtr,
      droppedItemSets,
      goldAmount,
      targetAcquisition,
      heroLevel,
      strength,
      agility,
      intelligence,
      inventory,
      abilities,
      random,
      customColor,
      waygate,
      creationNumber,
    });
  }

  /** @type {Record<string, number>} */
  const byTypeId = {};
  /** @type {Record<number, number>} */
  const byOwner = {};
  for (const u of units) {
    byTypeId[u.typeId] = (byTypeId[u.typeId] ?? 0) + 1;
    byOwner[u.owner] = (byOwner[u.owner] ?? 0) + 1;
  }

  return {
    formatVersion: version,
    subversion,
    count: units.length,
    byTypeId,
    byOwner,
    units,
    _bytesRemaining: r.remaining,
  };
}
