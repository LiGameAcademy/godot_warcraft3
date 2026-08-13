import { BufferReader } from "../buffer-reader.js";
import { resolveTrigStr } from "./wts.js";

const PLAYER_TYPES = {
  1: "human",
  2: "computer",
  3: "neutral",
  4: "rescuable",
};

const RACES = {
  1: "human",
  2: "orc",
  3: "undead",
  4: "nightelf",
};

/**
 * Classic TFT war3map.w3i (format version 25).
 * @param {Buffer} buffer
 * @param {Record<number, string>} [strings]
 */
export function parseW3i(buffer, strings = {}) {
  const r = new BufferReader(buffer);
  const version = r.readInt32();
  if (version < 18 || version > 28) {
    // Still attempt parse for nearby classic versions; warn via field.
  }

  const resolve = (s) => resolveTrigStr(s, strings);

  const info = {
    formatVersion: version,
    saves: r.readInt32(),
    editorVersion: r.readInt32(),
    name: resolve(r.readString()),
    author: resolve(r.readString()),
    description: resolve(r.readString()),
    recommendedPlayers: resolve(r.readString()),
    cameraBounds: Array.from({ length: 8 }, () => r.readFloat()),
    cameraBoundsComplements: {
      left: r.readInt32(),
      right: r.readInt32(),
      bottom: r.readInt32(),
      top: r.readInt32(),
    },
    playableWidth: r.readInt32(),
    playableHeight: r.readInt32(),
    flags: decodeFlags(r.readUInt32()),
    mainGroundType: String.fromCharCode(r.readUInt8()),
    loadingScreen: {
      background: r.readInt32(),
      path: resolve(r.readString()),
      text: resolve(r.readString()),
      title: resolve(r.readString()),
      subtitle: resolve(r.readString()),
    },
    gameDataSet: r.readInt32(),
    prologue: {
      path: resolve(r.readString()),
      text: resolve(r.readString()),
      title: resolve(r.readString()),
      subtitle: resolve(r.readString()),
    },
    fog: {
      style: r.readInt32(),
      startZ: r.readFloat(),
      endZ: r.readFloat(),
      density: r.readFloat(),
      color: [r.readUInt8(), r.readUInt8(), r.readUInt8(), r.readUInt8()],
    },
    globalWeather: r.readFourCC(),
    customSoundEnvironment: r.readString(),
    // 单字节 tileset；0 表示未设。勿写成 "\u0000"（Godot JSON.parse 会 Unicode NUL ERROR）
    customLightTileset: (() => {
      const b = r.readUInt8();
      return b === 0 ? "" : String.fromCharCode(b);
    })(),
    waterTint: [r.readUInt8(), r.readUInt8(), r.readUInt8(), r.readUInt8()],
    players: [],
    forces: [],
    upgradeAvailability: [],
    techAvailability: [],
    randomUnitTables: [],
    randomItemTables: [],
  };

  // Zero FourCC weather → none
  if (info.globalWeather === "\0\0\0\0") info.globalWeather = null;

  const playerCount = r.readInt32();
  for (let i = 0; i < playerCount; i += 1) {
    const playerNum = r.readInt32();
    const type = r.readInt32();
    const race = r.readInt32();
    const fixedStart = r.readInt32() === 1;
    const name = resolve(r.readString());
    const startX = r.readFloat();
    const startY = r.readFloat();
    const allyLow = r.readUInt32();
    const allyHigh = r.readUInt32();
    info.players.push({
      playerNum,
      type,
      typeName: PLAYER_TYPES[type] ?? `unknown(${type})`,
      race,
      raceName: RACES[race] ?? `unknown(${race})`,
      fixedStart,
      name,
      startPosition: { x: startX, y: startY },
      allyLowPriorities: allyLow,
      allyHighPriorities: allyHigh,
    });
  }

  const forceCount = r.readInt32();
  for (let i = 0; i < forceCount; i += 1) {
    const forceFlags = r.readUInt32();
    const playerMask = r.readUInt32();
    const name = resolve(r.readString());
    info.forces.push({
      flags: forceFlags,
      allied: (forceFlags & 0x1) !== 0,
      alliedVictory: (forceFlags & 0x2) !== 0,
      shareVision: (forceFlags & 0x4) !== 0,
      shareUnitControl: (forceFlags & 0x10) !== 0,
      shareAdvancedControl: (forceFlags & 0x20) !== 0,
      playerMask,
      players: maskToPlayers(playerMask),
      name,
    });
  }

  const upgradeCount = r.readInt32();
  for (let i = 0; i < upgradeCount; i += 1) {
    info.upgradeAvailability.push({
      playerFlags: r.readUInt32(),
      upgradeId: r.readFourCC(),
      level: r.readInt32(),
      availability: r.readInt32(),
    });
  }

  const techCount = r.readInt32();
  for (let i = 0; i < techCount; i += 1) {
    info.techAvailability.push({
      playerFlags: r.readUInt32(),
      techId: r.readFourCC(),
    });
  }

  const unitTableCount = r.readInt32();
  for (let t = 0; t < unitTableCount; t += 1) {
    const groupNumber = r.readInt32();
    const groupName = resolve(r.readString());
    const positionCount = r.readInt32();
    const positionTypes = Array.from({ length: positionCount }, () => r.readInt32());
    const lineCount = r.readInt32();
    const lines = [];
    for (let line = 0; line < lineCount; line += 1) {
      const chance = r.readInt32();
      const ids = Array.from({ length: positionCount }, () => r.readFourCC());
      lines.push({ chance, ids });
    }
    info.randomUnitTables.push({
      groupNumber,
      groupName,
      positionTypes,
      lines,
    });
  }

  if (version >= 25 && r.remaining >= 4) {
    const itemTableCount = r.readInt32();
    for (let t = 0; t < itemTableCount; t += 1) {
      const tableNumber = r.readInt32();
      const tableName = resolve(r.readString());
      const setCount = r.readInt32();
      const sets = [];
      for (let s = 0; s < setCount; s += 1) {
        const itemCount = r.readInt32();
        const items = [];
        for (let i = 0; i < itemCount; i += 1) {
          items.push({ chance: r.readInt32(), id: r.readFourCC() });
        }
        sets.push(items);
      }
      info.randomItemTables.push({ tableNumber, tableName, sets });
    }
  }

  info._bytesRemaining = r.remaining;
  return info;
}

/** @param {number} flags */
function decodeFlags(flags) {
  return {
    raw: flags,
    hideMinimap: (flags & 0x0001) !== 0,
    modifyAllyPriorities: (flags & 0x0002) !== 0,
    melee: (flags & 0x0004) !== 0,
    largeNeverReduced: (flags & 0x0008) !== 0,
    maskedAreasPartiallyVisible: (flags & 0x0010) !== 0,
    fixedPlayerSettings: (flags & 0x0020) !== 0,
    customForces: (flags & 0x0040) !== 0,
    customTechtree: (flags & 0x0080) !== 0,
    customAbilities: (flags & 0x0100) !== 0,
    customUpgrades: (flags & 0x0200) !== 0,
    mapPropertiesOpened: (flags & 0x0400) !== 0,
    waterWavesCliff: (flags & 0x0800) !== 0,
    waterWavesRolling: (flags & 0x1000) !== 0,
  };
}

/** @param {number} mask */
function maskToPlayers(mask) {
  const players = [];
  for (let i = 0; i < 32; i += 1) {
    if (mask & (1 << i)) players.push(i);
  }
  return players;
}
