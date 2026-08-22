#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { convertBlpBatch } from "./convert-blp.js";
import { convertMdxBatch } from "./convert-mdx.js";
import { cleanConvertedJunk } from "./clean-junk.js";
import { copyPassthroughBatch } from "./copy-passthrough.js";
import { resolveFromPackage } from "./paths.js";
import { reconcileM2gToolVersion } from "./m2g-tool-version.js";
import { bakeModelScenes } from "../scripts/bake-model-scenes.mjs";
import {
  LEGACY_CACHE_ROOT,
  resolveExtractRoot,
} from "../../pipeline-paths.mjs";
import { beginSession, getLog } from "../../pipeline-log.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(PACKAGE_ROOT, "../..");

const GDIGNORE_BODY = `## Godot: 忽略本目录，避免 auto-import .gltf/.png 生成 .import / baseColor 副产物。
## 运行时走 RuntimeAssets 磁盘路径；方案 B 外链贴图后仍建议保留本文件以免扫几千模型卡顿。
`;

function ensureGdignore(outDir) {
  const target = path.join(outDir, ".gdignore");
  if (!fs.existsSync(target)) {
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(target, GDIGNORE_BODY, "utf8");
    getLog().info(`[convert] 已补写 ${path.relative(REPO_ROOT, target)}`);
  }
}

function defaultInDir() {
  const r = resolveExtractRoot();
  // 相对 package 根，供 resolveFromPackage
  return path.relative(PACKAGE_ROOT, r.root).replace(/\\/g, "/") || r.root;
}

function printHelp() {
  console.log(`用法:
  npm run convert -- [选项]

顺序（默认）:
  1) 清理 asset-converted 残留（baseColor / .import / 旧 .glb / 旁路 PNG）
  2) BLP→PNG
  3) MDX→.gltf（外链 Textures/）
  4) passthrough 复制（Sound / Fonts / PathTextures / wav·mp3·tga… → asset-converted；UnitFunc/UI → slk-exported）
  5) 烘焙 .scn

选项:
  --in <path>           extract 根（默认: assets/.staging/wc3-assets，回退 .cache/wc3-assets）
  --out <path>          视觉输出（默认: ../../assets/asset-converted）
  --data-out <path>     数据输出（默认: ../../assets/slk-exported）
  --force               忽略增量，强制重转（含 .scn）
  --textures-only       只转贴图
  --models-only         只转模型
  --skip-scn            跳过 .scn 烘焙
  --scn-only            只烘焙 .scn
  --skip-clean          跳过残留清理
  --clean-only          只清理残留后退出
  --skip-passthrough    跳过 PathTextures/UnitFunc 等复制
  --include <glob>      仅包含逻辑路径（可重复）
  --exclude <glob>      排除逻辑路径（可重复）
  --godot <path>        Godot 可执行文件
  -h, --help            帮助

示例:
  npm run convert -- --include "Units/Human/Footman/**"
  npm run convert -- --clean-only
`);
}

function parseArgs(argv) {
  const opts = {
    inDir: "",
    outDir: "../../assets/asset-converted",
    dataOut: "../../assets/slk-exported",
    force: false,
    texturesOnly: false,
    modelsOnly: false,
    skipScn: false,
    scnOnly: false,
    skipClean: false,
    cleanOnly: false,
    skipPassthrough: false,
    include: [],
    exclude: [],
    godot: "",
    help: false,
  };

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
      case "--textures-only":
        opts.texturesOnly = true;
        break;
      case "--models-only":
        opts.modelsOnly = true;
        break;
      case "--skip-scn":
        opts.skipScn = true;
        break;
      case "--scn-only":
        opts.scnOnly = true;
        break;
      case "--skip-clean":
        opts.skipClean = true;
        break;
      case "--clean-only":
        opts.cleanOnly = true;
        break;
      case "--skip-passthrough":
        opts.skipPassthrough = true;
        break;
      case "--in":
        opts.inDir = argv[++i] ?? opts.inDir;
        break;
      case "--out":
        opts.outDir = argv[++i] ?? opts.outDir;
        break;
      case "--data-out":
        opts.dataOut = argv[++i] ?? opts.dataOut;
        break;
      case "--include":
        if (argv[i + 1]) opts.include.push(argv[++i]);
        break;
      case "--exclude":
        if (argv[i + 1]) opts.exclude.push(argv[++i]);
        break;
      case "--godot":
        if (argv[i + 1]) opts.godot = argv[++i];
        break;
      default:
        if (arg.startsWith("-")) throw new Error(`未知参数: ${arg}`);
        break;
    }
  }
  if (!opts.inDir) opts.inDir = defaultInDir();
  return opts;
}

/** include glob → bake 用的路径子串（Godot 脚本是 findn，非 glob） */
function includesForBake(includeGlobs) {
  return includeGlobs
    .map((g) =>
      String(g)
        .replace(/\\/g, "/")
        .replace(/\*\*/g, "")
        .replace(/\*/g, "")
        .replace(/\/+/g, "/")
        .replace(/^\/+|\/+$/g, ""),
    )
    .filter(Boolean);
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message ?? err);
    printHelp();
    process.exit(1);
  }

  if (opts.help) {
    printHelp();
    process.exit(0);
  }

  if (opts.texturesOnly && opts.modelsOnly) {
    console.error("不能同时指定 --textures-only 与 --models-only");
    process.exit(1);
  }
  if (opts.scnOnly && (opts.texturesOnly || opts.modelsOnly)) {
    console.error("--scn-only 不能与 --textures-only / --models-only 同用");
    process.exit(1);
  }

  const log = beginSession("asset-convert");

  const inDir = resolveFromPackage(opts.inDir, PACKAGE_ROOT);
  const extractMeta = resolveExtractRoot();
  if (
    extractMeta.kind === "legacy-cache" &&
    path.resolve(inDir) === path.resolve(extractMeta.root)
  ) {
    log.warn(
      `[convert] staging 不存在，回退遗留 ${path.relative(REPO_ROOT, LEGACY_CACHE_ROOT)}（请改跑 bootstrap 写 assets/.staging）`,
    );
  }
  const outDir = resolveFromPackage(opts.outDir, PACKAGE_ROOT);
  const dataOut = resolveFromPackage(opts.dataOut, PACKAGE_ROOT);
  const doTextures = !opts.scnOnly && !opts.modelsOnly && !opts.cleanOnly;
  const doModels = !opts.scnOnly && !opts.texturesOnly && !opts.cleanOnly;
  const doScn =
    !opts.cleanOnly && (opts.scnOnly || (!opts.skipScn && !opts.texturesOnly));
  const doPassthrough =
    !opts.cleanOnly &&
    !opts.skipPassthrough &&
    !opts.scnOnly &&
    !opts.texturesOnly &&
    !opts.modelsOnly;
  const doClean = !opts.skipClean;

  const steps = [
    doClean && "clean",
    doTextures && "textures",
    doModels && "models",
    doPassthrough && "passthrough",
    doScn && "scn",
  ]
    .filter(Boolean)
    .join(" → ");

  log.info("godot_warcraft3 资产转换工具");
  log.info(`  in:      ${inDir}`);
  log.info(`  out:     ${outDir}`);
  log.info(`  data:    ${dataOut}`);
  log.info(`  force:   ${opts.force}`);
  log.info(`  steps:   ${steps}`);
  if (opts.include.length) log.info(`  include: ${opts.include.join(", ")}`);
  if (opts.exclude.length) log.info(`  exclude: ${opts.exclude.join(", ")}`);

  ensureGdignore(outDir);

  let errors = 0;

  if (doClean) {
    log.info("\n[clean] 清理 GLB/import 残留…");
    const c = cleanConvertedJunk(outDir, {
      dryRun: false,
      include: opts.include,
    });
    log.info(
      `[clean] import=${c.import} baseColor=${c.baseColor} glb=${c.glbLeftover} orphanPng=${c.orphanPng}`,
    );
  }

  if (opts.cleanOnly) {
    log.info("\n全部完成（--clean-only）。");
    log.endSession({ mode: "clean-only" });
    process.exit(0);
  }

  // 工具代码变更 → 自动 force 重烤模型
  const toolVer = reconcileM2gToolVersion(REPO_ROOT, {
    hashFile: path.join(REPO_ROOT, "assets", ".staging", "m2g-tool-hash"),
    force: opts.force,
  });
  if (toolVer.force && !opts.force) {
    log.info(`[tool] 工具变更 → 自动 force=true（${toolVer.reason}）`);
  } else if (toolVer.hash) {
    log.info(`[tool] ${toolVer.reason}`);
  }
  const modelForce = toolVer.force || opts.force;

  if (doTextures || doModels || doPassthrough) {
    if (!fs.existsSync(inDir)) {
      log.fatal(
        `[convert] extract 根不存在: ${inDir}`,
        "请先跑 bootstrap / mpq-extract（输出 assets/.staging/wc3-assets）",
      );
      log.endSession({ exit: 2 });
      process.exit(2);
    }
  }

  if (doTextures) {
    const r = convertBlpBatch({
      inDir,
      outDir,
      force: opts.force,
      include: opts.include,
      exclude: opts.exclude,
    });
    errors += r.errors;
  }

  if (doModels) {
    const r = await convertMdxBatch({
      inDir,
      outDir,
      force: modelForce,
      include: opts.include,
      exclude: opts.exclude,
    });
    errors += r.errors;
  }

  if (doPassthrough) {
    log.info("\n[passthrough] Sound / Fonts / PathTextures / 媒体 → asset-converted；UnitFunc/UI → slk-exported…");
    const p = copyPassthroughBatch({
      inDir,
      convertedOut: outDir,
      dataOut,
      force: opts.force,
    });
    log.info(
      `[passthrough] copied=${p.copied} skipped=${p.skipped} missing=${p.missing}`,
    );
    if (p.missing > 0) {
      log.warnOnce(
        "passthrough-missing",
        `passthrough 缺源 ${p.missing} 项`,
        `missing=${p.missing}（详见上方 copied/skipped）`,
      );
    }
  }

  if (doScn) {
    log.info("\n—— 烘焙 .scn ——");
    const workers = Number(process.env.WORKERS || process.env.BAKE_WORKERS) || 1;
    const code = await bakeModelScenes({
      include: includesForBake(opts.include),
      force: opts.force,
      workers,
      godot: opts.godot,
    });
    if (code !== 0) {
      log.error(`scn bake 退出码 ${code}`);
      errors += 1;
    }
  }

  // 转换后再清一次：Godot bake 偶发写 .import 时清掉
  if (doClean && !opts.skipClean) {
    const c2 = cleanConvertedJunk(outDir, { include: opts.include });
    if (c2.import + c2.baseColor + c2.orphanPng + c2.glbLeftover > 0) {
      log.info(
        `[clean:post] import=${c2.import} baseColor=${c2.baseColor} glb=${c2.glbLeftover} orphanPng=${c2.orphanPng}`,
      );
    }
  }

  log.info("\n全部完成。输出: asset-converted/*.gltf（外链 Textures）+ .scn；数据车道 slk-exported/。");
  if (!opts.force) {
    log.info(
      "提示: 未加 --force 时按源/产物 mtime 增量跳过；工具变更也不会自动全量。需要全量请 --force，子集请 --include。",
    );
  }
  log.endSession({ errors, exit: errors > 0 ? 2 : 0 });
  process.exit(errors > 0 ? 2 : 0);
}

main().catch((err) => {
  const log = getLog();
  log.fatal(err?.message ?? String(err), err);
  log.endSession({ exit: 1 });
  process.exit(1);
});
