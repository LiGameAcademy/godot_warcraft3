import fs from "node:fs";
import path from "node:path";
import {
  openArchive,
  closeArchive,
  listFiles,
  extractToBuffer,
} from "../../mpq-extract/src/stormlib.js";
import { parseWts } from "./parsers/wts.js";
import { parseW3i } from "./parsers/w3i.js";
import { parseW3e } from "./parsers/w3e.js";
import { parseDoodadsDoo } from "./parsers/doo-doodads.js";
import { parseUnitsDoo } from "./parsers/doo-units.js";
import { parseW3r } from "./parsers/w3r.js";
import { parseW3c } from "./parsers/w3c.js";
import { parseMmp } from "./parsers/mmp.js";
import { parseWpm } from "./parsers/wpm.js";
import { blpBufferToPng } from "../../asset-convert/src/convert-blp.js";

/**
 * @param {string} name
 * @param {string[]} archiveNames
 */
function findArchiveName(name, archiveNames) {
  const want = name.replace(/\//g, "\\").toLowerCase();
  return (
    archiveNames.find((n) => n.replace(/\//g, "\\").toLowerCase() === want) ??
    null
  );
}

/**
 * @param {{ handle: object }} archive
 * @param {string} name
 * @param {string[]} archiveNames
 */
function readFile(archive, name, archiveNames) {
  const hit = findArchiveName(name, archiveNames);
  if (!hit) throw new Error(`地图内缺少文件: ${name}`);
  return extractToBuffer(archive, hit);
}

/**
 * @param {string} mapPath
 */
export function mapSlugFromPath(mapPath) {
  const base = path.basename(mapPath, path.extname(mapPath));
  return base
    .replace(/^\(\d+\)/, "")
    .replace(/[^\w\-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toLowerCase() || "map";
}

/**
 * @param {string} mapPath
 * @param {{
 *   outDir: string,
 *   includeTilepoints?: boolean,
 *   writeRaw?: boolean,
 *   force?: boolean,
 * }} opts
 */
export function parseMap(mapPath, opts) {
  const absMap = path.resolve(mapPath);
  if (!fs.existsSync(absMap)) {
    throw new Error(`地图不存在: ${absMap}`);
  }

  const slug = mapSlugFromPath(absMap);
  const outDir = path.resolve(opts.outDir, slug);
  if (fs.existsSync(outDir) && !opts.force) {
    const marker = path.join(outDir, "summary.json");
    if (fs.existsSync(marker)) {
      console.log(`已存在解析结果，跳过（使用 --force 重跑）: ${outDir}`);
      return { outDir, skipped: true };
    }
  }

  fs.mkdirSync(outDir, { recursive: true });

  const archive = openArchive(absMap);
  /** @type {string[]} */
  let archiveNames = [];
  /** @type {Record<string, unknown>} */
  const errors = {};

  try {
    archiveNames = listFiles(archive);
    const fileList = archiveNames.map((n) => n.replace(/\\/g, "/"));

    if (opts.writeRaw) {
      const rawDir = path.join(outDir, "raw");
      fs.mkdirSync(rawDir, { recursive: true });
      for (const name of archiveNames) {
        const buf = extractToBuffer(archive, name);
        const safe = name.replace(/[\\/]/g, "_");
        fs.writeFileSync(path.join(rawDir, safe), buf);
      }
    }

    /** @type {Record<number, string>} */
    let strings = {};
    try {
      const wtsBuf = readFile(archive, "war3map.wts", archiveNames);
      strings = parseWts(wtsBuf);
      writeJson(path.join(outDir, "strings.json"), {
        count: Object.keys(strings).length,
        strings,
      });
    } catch (e) {
      errors.strings = String(e);
    }

    let info = null;
    try {
      const w3i = readFile(archive, "war3map.w3i", archiveNames);
      info = parseW3i(w3i, strings);
      writeJson(path.join(outDir, "info.json"), info);
    } catch (e) {
      errors.info = String(e);
    }

    let terrain = null;
    try {
      const w3e = readFile(archive, "war3map.w3e", archiveNames);
      terrain = parseW3e(w3e, { includeTilepoints: opts.includeTilepoints === true });
      // Full tilepoints can be large — write separately; keep header in terrain.json
      const { tilepoints, heightfield, ...terrainMeta } = terrain;
      writeJson(path.join(outDir, "terrain.json"), terrainMeta);
      if (heightfield) {
        writeJson(path.join(outDir, "terrain-heightfield.json"), {
          tilepointWidth: terrain.tilepointWidth,
          tilepointHeight: terrain.tilepointHeight,
          mapWidth: terrain.mapWidth,
          mapHeight: terrain.mapHeight,
          centerOffset: terrain.centerOffset,
          mainTileset: terrain.mainTileset,
          mainTilesetName: terrain.mainTilesetName,
          groundTilesets: terrain.groundTilesets,
          cliffTilesets: terrain.cliffTilesets,
          tileSize: heightfield.tileSize,
          heights: heightfield.heights,
          groundTextures: heightfield.groundTextures,
          groundVariations: heightfield.groundVariations,
          cliffVariations: heightfield.cliffVariations,
          cliffTextures: heightfield.cliffTextures,
          layerHeights: heightfield.layerHeights,
          waterHeights: heightfield.waterHeights,
          flagsPacked: heightfield.flagsPacked,
        });
      }
      if (tilepoints) {
        writeJson(path.join(outDir, "terrain-tilepoints.json"), {
          tilepointWidth: terrain.tilepointWidth,
          tilepointHeight: terrain.tilepointHeight,
          tilepoints,
        });
      }
    } catch (e) {
      errors.terrain = String(e);
    }

    let units = null;
    try {
      const unitsBuf = readFile(archive, "war3mapUnits.doo", archiveNames);
      units = parseUnitsDoo(unitsBuf);
      writeJson(path.join(outDir, "units.json"), units);
    } catch (e) {
      errors.units = String(e);
    }

    let doodads = null;
    try {
      const dooBuf = readFile(archive, "war3map.doo", archiveNames);
      doodads = parseDoodadsDoo(dooBuf);
      writeJson(path.join(outDir, "doodads.json"), doodads);
    } catch (e) {
      errors.doodads = String(e);
    }

    let regions = null;
    try {
      if (findArchiveName("war3map.w3r", archiveNames)) {
        regions = parseW3r(readFile(archive, "war3map.w3r", archiveNames));
        writeJson(path.join(outDir, "regions.json"), regions);
      }
    } catch (e) {
      errors.regions = String(e);
    }

    let cameras = null;
    try {
      if (findArchiveName("war3map.w3c", archiveNames)) {
        cameras = parseW3c(readFile(archive, "war3map.w3c", archiveNames));
        writeJson(path.join(outDir, "cameras.json"), cameras);
      }
    } catch (e) {
      errors.cameras = String(e);
    }

    /** @type {{count:number}|null} */
    let minimap = null;
    try {
      if (findArchiveName("war3map.mmp", archiveNames)) {
        minimap = parseMmp(readFile(archive, "war3map.mmp", archiveNames));
        writeJson(path.join(outDir, "minimap.json"), minimap);
      }
    } catch (e) {
      errors.minimap = String(e);
    }

    let pathing = null;
    try {
      if (findArchiveName("war3map.wpm", archiveNames)) {
        pathing = parseWpm(readFile(archive, "war3map.wpm", archiveNames));
        // origin 与 W3E centerOffset 对齐（寻路格左下 = 地形左下 tilepoint）
        if (terrain?.centerOffset) {
          pathing.origin = {
            x: terrain.centerOffset.x,
            y: terrain.centerOffset.y,
          };
        }
        const { _bytesRemaining, ...pathingOut } = pathing;
        writeJson(path.join(outDir, "pathing.json"), pathingOut);
        pathing._bytesRemaining = _bytesRemaining;
      }
    } catch (e) {
      errors.pathing = String(e);
    }

    try {
      // 官方预烘焙小地图：优先 BLP，其次 TGA
      const mapBlp = findArchiveName("war3mapMap.blp", archiveNames);
      const mapTga = findArchiveName("war3mapMap.tga", archiveNames);
      if (mapBlp) {
        const png = blpBufferToPng(extractToBuffer(archive, mapBlp));
        fs.writeFileSync(path.join(outDir, "war3mapMap.png"), png);
      } else if (mapTga) {
        fs.writeFileSync(
          path.join(outDir, "war3mapMap.tga"),
          extractToBuffer(archive, mapTga),
        );
      }
    } catch (e) {
      errors.war3mapMap = String(e);
    }

    const summary = {
      version: 1,
      parsedAt: new Date().toISOString(),
      sourceMap: absMap,
      slug,
      archiveFiles: fileList,
      map: info
        ? {
            name: info.name,
            author: info.author,
            description: info.description,
            recommendedPlayers: info.recommendedPlayers,
            playableWidth: info.playableWidth,
            playableHeight: info.playableHeight,
            melee: info.flags?.melee ?? false,
            mainGroundType: info.mainGroundType,
            players: info.players?.map((p) => ({
              playerNum: p.playerNum,
              name: p.name,
              type: p.typeName,
              race: p.raceName,
              startPosition: p.startPosition,
            })),
            forces: info.forces?.map((f) => ({
              name: f.name,
              players: f.players,
            })),
          }
        : null,
      terrain: terrain
        ? {
            mainTileset: terrain.mainTileset,
            mainTilesetName: terrain.mainTilesetName,
            mapWidth: terrain.mapWidth,
            mapHeight: terrain.mapHeight,
            groundTilesets: terrain.groundTilesets,
            stats: terrain.stats,
            bytesRemaining: terrain._bytesRemaining,
          }
        : null,
      units: units
        ? {
            count: units.count,
            byTypeId: units.byTypeId,
            byOwner: units.byOwner,
            bytesRemaining: units._bytesRemaining,
            sample: units.units.slice(0, 8).map((u) => ({
              typeId: u.typeId,
              owner: u.owner,
              position: u.position,
              goldAmount: u.goldAmount,
            })),
          }
        : null,
      doodads: doodads
        ? {
            count: doodads.count,
            byId: doodads.byId,
            specialCount: doodads.specialDoodads?.length ?? 0,
            bytesRemaining: doodads._bytesRemaining,
          }
        : null,
      regions: regions ? { count: regions.count } : null,
      cameras: cameras ? { count: cameras.count } : null,
      pathing: pathing
        ? { width: pathing.width, height: pathing.height, cellSize: pathing.cellSize }
        : null,
      minimap: minimap ? { count: minimap.count } : null,
      war3mapMap: fs.existsSync(path.join(outDir, "war3mapMap.png"))
        ? "war3mapMap.png"
        : fs.existsSync(path.join(outDir, "war3mapMap.tga"))
          ? "war3mapMap.tga"
          : null,
      strings: { count: Object.keys(strings).length },
      errors: Object.keys(errors).length ? errors : undefined,
    };

    writeJson(path.join(outDir, "summary.json"), summary);

    const warnRemain = [];
    for (const [k, v] of [
      ["info", info],
      ["terrain", terrain],
      ["units", units],
      ["doodads", doodads],
    ]) {
      if (v && typeof v._bytesRemaining === "number" && v._bytesRemaining > 0) {
        warnRemain.push(`${k}:${v._bytesRemaining}B`);
      }
    }

    return {
      outDir,
      skipped: false,
      summary,
      warnings: warnRemain,
      errors,
    };
  } finally {
    closeArchive(archive);
  }
}

/** @param {string} file @param {unknown} data */
function writeJson(file, data) {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}
