import { BufferReader } from "../buffer-reader.js";

const TILESET_NAMES = {
  A: "Ashenvale",
  B: "Barrens",
  C: "Felwood",
  D: "Dungeon",
  F: "Lordaeron Fall",
  G: "Underground",
  L: "Lordaeron Summer",
  N: "Northrend",
  Q: "Village Fall",
  V: "Village",
  W: "Lordaeron Winter",
  X: "Dalaran",
  Y: "Cityscape",
  Z: "Sunken Ruins",
  I: "Icecrown",
  J: "Dalaran Ruins",
  O: "Outland",
  K: "Black Citadel",
};

/**
 * Classic war3map.w3e terrain (format version 11).
 * @param {Buffer} buffer
 * @param {{ includeTilepoints?: boolean }} [opts]
 */
export function parseW3e(buffer, opts = {}) {
  const includeTilepoints = opts.includeTilepoints !== false;
  const r = new BufferReader(buffer);

  const magic = r.readFourCC();
  if (magic !== "W3E!") {
    throw new Error(`Invalid w3e magic: ${JSON.stringify(magic)}`);
  }

  const version = r.readInt32();
  const mainTileset = String.fromCharCode(r.readUInt8());
  const customTilesets = r.readInt32() === 1;

  const groundCount = r.readInt32();
  const groundTilesets = Array.from({ length: groundCount }, () => r.readFourCC());

  const cliffCount = r.readInt32();
  const cliffTilesets = Array.from({ length: cliffCount }, () => r.readFourCC());

  const width = r.readInt32(); // Mx = mapWidth + 1
  const height = r.readInt32(); // My = mapHeight + 1
  const centerOffsetX = r.readFloat();
  const centerOffsetY = r.readFloat();

  const tilepointCount = width * height;
  /** @type {object[] | undefined} */
  let tilepoints;
  /** @type {number[]} */
  const heights = new Array(tilepointCount);
  /** @type {number[]} ground texture index 0-15 */
  const groundTextures = new Array(tilepointCount);
  /** bit0 water, bit1 blight, bit2 ramp, bit3 boundary(Nothing), bit4 map_edge */
  /** @type {number[]} */
  const flagsPacked = new Array(tilepointCount);
  /** @type {number[]} cliff tileset index 0-15 */
  const cliffTextures = new Array(tilepointCount);
  /** @type {number[]} layer height nibble 0-15 */
  const layerHeights = new Array(tilepointCount);
  /** @type {number[]} decoded water surface height (WC3 units) */
  const waterHeights = new Array(tilepointCount);
  /** @type {number[]} ground variation (low 5 bits of detail byte) */
  const groundVariations = new Array(tilepointCount);
  /** @type {number[]} cliff variation (high 3 bits of detail byte) */
  const cliffVariations = new Array(tilepointCount);

  let minHeight = Infinity;
  let maxHeight = -Infinity;
  let waterCount = 0;
  let blightCount = 0;
  let rampCount = 0;

  if (includeTilepoints) {
    tilepoints = new Array(tilepointCount);
  }

  for (let i = 0; i < tilepointCount; i += 1) {
    const groundHeightRaw = r.readUInt16();
    const waterAndBoundary = r.readUInt16();
    const flagsAndTexture = r.readUInt8();
    const detail = r.readUInt8();
    const cliffAndLayer = r.readUInt8();

    // Water short: low 14 bits = water level; bit 14 (0x4000) = map-edge boundary.
    const boundary1 = (waterAndBoundary & 0x4000) !== 0;
    const waterLevelRaw = waterAndBoundary & 0x3fff;
    // Next byte: low nibble = ground texture index; high bits = flags.
    const groundTexture = flagsAndTexture & 0x0f;
    const ramp = (flagsAndTexture & 0x10) !== 0;
    const blight = (flagsAndTexture & 0x20) !== 0;
    const water = (flagsAndTexture & 0x40) !== 0;
    const boundary2 = (flagsAndTexture & 0x80) !== 0;
    const groundVariation = detail & 0x1f;
    const cliffVariation = (detail >> 5) & 0x07;
    const cliffTexture = (cliffAndLayer >> 4) & 0x0f;
    const layerHeight = cliffAndLayer & 0x0f;

    const finalHeight =
      (groundHeightRaw - 0x2000 + (layerHeight - 2) * 0x0200) / 4;
    const waterHeight = (waterLevelRaw - 0x2000) / 4;

    heights[i] = finalHeight;
    groundTextures[i] = groundTexture;
    groundVariations[i] = groundVariation;
    cliffVariations[i] = cliffVariation;
    cliffTextures[i] = cliffTexture;
    layerHeights[i] = layerHeight;
    waterHeights[i] = waterHeight;
    flagsPacked[i] =
      (water ? 1 : 0) |
      (blight ? 2 : 0) |
      (ramp ? 4 : 0) |
      (boundary2 ? 8 : 0) |
      (boundary1 ? 16 : 0);

    if (finalHeight < minHeight) minHeight = finalHeight;
    if (finalHeight > maxHeight) maxHeight = finalHeight;
    if (water) waterCount += 1;
    if (blight) blightCount += 1;
    if (ramp) rampCount += 1;

    if (tilepoints) {
      tilepoints[i] = {
        groundHeightRaw,
        waterLevelRaw,
        finalHeight,
        groundTexture,
        groundVariation,
        cliffVariation,
        detail,
        cliffTexture,
        layerHeight,
        flags: { ramp, blight, water, boundary1, boundary2 },
      };
    }
  }

  const mapWidth = width - 1;
  const mapHeight = height - 1;

  return {
    formatVersion: version,
    mainTileset,
    mainTilesetName: TILESET_NAMES[mainTileset] ?? mainTileset,
    customTilesets,
    groundTilesets,
    cliffTilesets,
    tilepointWidth: width,
    tilepointHeight: height,
    mapWidth,
    mapHeight,
    centerOffset: { x: centerOffsetX, y: centerOffsetY },
    stats: {
      tilepointCount,
      minHeight: Number.isFinite(minHeight) ? minHeight : 0,
      maxHeight: Number.isFinite(maxHeight) ? maxHeight : 0,
      waterTilepoints: waterCount,
      blightTilepoints: blightCount,
      rampTilepoints: rampCount,
    },
    tilepoints: includeTilepoints ? tilepoints : undefined,
    /** Compact arrays for Godot / tooling (always present). */
    heightfield: {
      tileSize: 128,
      heights,
      groundTextures,
      groundVariations,
      cliffVariations,
      cliffTextures,
      layerHeights,
      waterHeights,
      flagsPacked,
    },
    _bytesRemaining: r.remaining,
  };
}
