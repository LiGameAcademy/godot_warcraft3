#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseMap } from "./parse-map.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(PACKAGE_ROOT, "../..");

const DEFAULT_MAP = String.raw`C:\war3\Maps\FrozenThrone\(4)LostTemple.w3x`;

function printHelp() {
  console.log(`用法:
  npm run parse -- [地图路径] [选项]

解析经典 Warcraft III .w3x / .w3m（MPQ）地图，写出 JSON。
默认测试地图：Lost Temple（冰封王座经典 4 人图）。

选项:
  --map <path>          地图路径（也可用位置参数）
  --out <path>          输出根目录（默认: ../../assets/map-parsed）
  --tilepoints          额外写出完整 terrain-tilepoints.json（体积大；默认只写紧凑 heightfield）
  --raw                 额外导出 MPQ 内原始 war3map.* 文件
  --force               覆盖已有解析结果
  -h, --help            帮助

示例:
  npm run parse --
  npm run parse -- --map "C:/war3/Maps/FrozenThrone/(4)LostTemple.w3x"
  # 注意：npm 会吞掉尾部的 --force，请把 --force 放在 -- 之后、路径之前
  npm run parse -- --force "C:/war3/Maps/FrozenThrone/(2)EchoIsles.w3x"
  node src/cli.js "C:/war3/Maps/FrozenThrone/(2)EchoIsles.w3x" --force
`);
}

function parseArgs(argv) {
  const opts = {
    map: null,
    outDir: path.join(REPO_ROOT, "assets", "map-parsed"),
    includeTilepoints: false,
    writeRaw: false,
    force: false,
    help: false,
  };

  /** @type {string[]} */
  const positionals = [];

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "-h":
      case "--help":
        opts.help = true;
        break;
      case "--force":
        opts.force = true;
        break;
      case "--raw":
        opts.writeRaw = true;
        break;
      case "--tilepoints":
        opts.includeTilepoints = true;
        break;
      case "--no-tilepoints":
        // 兼容旧参数：默认已是紧凑 heightfield
        opts.includeTilepoints = false;
        break;
      case "--map":
        opts.map = argv[++i] ?? opts.map;
        break;
      case "--out":
        opts.outDir = path.resolve(argv[++i] ?? opts.outDir);
        break;
      default:
        if (arg.startsWith("-")) throw new Error(`未知参数: ${arg}`);
        positionals.push(arg);
        break;
    }
  }

  if (!opts.map && positionals[0]) opts.map = positionals[0];
  if (!opts.map) opts.map = DEFAULT_MAP;
  return opts;
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(String(e));
    process.exitCode = 1;
    return;
  }

  if (opts.help) {
    printHelp();
    return;
  }

  console.log(`地图: ${opts.map}`);
  console.log(`输出: ${opts.outDir}`);

  try {
    const result = parseMap(opts.map, {
      outDir: opts.outDir,
      includeTilepoints: opts.includeTilepoints,
      writeRaw: opts.writeRaw,
      force: opts.force,
    });

    if (result.skipped) return;

    const s = result.summary;
    console.log("");
    console.log(`名称: ${s.map?.name ?? "(未知)"}`);
    console.log(`推荐人数: ${s.map?.recommendedPlayers ?? "-"}`);
    console.log(
      `可玩区域: ${s.map?.playableWidth ?? "?"} × ${s.map?.playableHeight ?? "?"}`,
    );
    console.log(
      `地形: ${s.terrain?.mainTilesetName ?? "?"} (${s.terrain?.mapWidth}×${s.terrain?.mapHeight} tiles)`,
    );
    console.log(`单位/物品: ${s.units?.count ?? 0}`);
    console.log(`装饰物: ${s.doodads?.count ?? 0}`);
    if (s.pathing) {
      console.log(
        `寻路面: ${s.pathing.width}×${s.pathing.height} (cell ${s.pathing.cellSize})`,
      );
    } else {
      console.log("寻路面: (无 war3map.wpm / 解析失败)");
    }
    console.log(`字符串: ${s.strings?.count ?? 0}`);
    if (result.warnings?.length) {
      console.log(`警告: 解析后仍有剩余字节 → ${result.warnings.join(", ")}`);
    }
    if (result.errors && Object.keys(result.errors).length) {
      console.error("部分文件解析失败:");
      for (const [k, v] of Object.entries(result.errors)) {
        console.error(`  ${k}: ${v}`);
      }
      process.exitCode = 1;
    }
    console.log(`\n完成 → ${result.outDir}`);
  } catch (e) {
    console.error(e instanceof Error ? e.stack ?? e.message : String(e));
    process.exitCode = 1;
  }
}

main();
