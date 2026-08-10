#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { convertBlpBatch } from "./convert-blp.js";
import { convertMdxBatch } from "./convert-mdx.js";
import { resolveFromPackage } from "./paths.js";
import { reconcileM2gToolVersion } from "./m2g-tool-version.js";
import { bakeModelScenes } from "../scripts/bake-model-scenes.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(PACKAGE_ROOT, "../..");

function printHelp() {
  console.log(`用法:
  npm run convert -- [选项]

顺序说明:
  默认先转换贴图 (BLP→PNG)，再转换模型 (MDX→GLB)，再调用 Godot 将 GLB 烘焙为同目录 .scn（最终运行时优先格式）。
选项:
  --in <path>           解包资产根目录（默认: ../../.cache/wc3-assets）
  --out <path>          转换输出根目录（默认: ../../assets/asset-converted）
  --force               忽略增量，强制重转（含 .scn）
  --textures-only       只转贴图
  --models-only         只转模型（建议已跑过贴图）
  --skip-scn            跳过 Godot .scn 烘焙
  --scn-only            只烘焙 .scn（不转贴图/模型）
  --include <glob>      仅包含逻辑路径（可重复）
  --exclude <glob>      排除逻辑路径（可重复）
  --godot <path>        Godot 可执行文件（也可设环境变量 GODOT）
  -h, --help            帮助

示例:
  npm run convert -- --include "Units/Human/Footman/**" --include "Textures/Footman.blp"
  npm run convert:textures -- --include "Textures/**"
  npm run convert:models -- --include "Units/Human/Footman/**"
  npm run bake:scn -- --include Units/Human/
`);
}

function parseArgs(argv) {
  const opts = {
    inDir: "../../.cache/wc3-assets",
    outDir: "../../assets/asset-converted",
    force: false,
    texturesOnly: false,
    modelsOnly: false,
    skipScn: false,
    scnOnly: false,
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
      case "--in":
        opts.inDir = argv[++i] ?? opts.inDir;
        break;
      case "--out":
        opts.outDir = argv[++i] ?? opts.outDir;
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

  const inDir = resolveFromPackage(opts.inDir, PACKAGE_ROOT);
  const outDir = resolveFromPackage(opts.outDir, PACKAGE_ROOT);
  const doTextures = !opts.scnOnly && !opts.modelsOnly;
  const doModels = !opts.scnOnly && !opts.texturesOnly;
  const doScn = opts.scnOnly || (!opts.skipScn && !opts.texturesOnly);

  console.log("godot_warcraft3 资产转换工具");
  console.log(`  in:      ${inDir}`);
  console.log(`  out:     ${outDir}`);
  console.log(`  force:   ${opts.force}`);
  console.log(
    `  steps:   ${[doTextures && "textures", doModels && "models", doScn && "scn"]
      .filter(Boolean)
      .join(" → ")}`,
  );
  if (opts.include.length) console.log(`  include: ${opts.include.join(", ")}`);
  if (opts.exclude.length) console.log(`  exclude: ${opts.exclude.join(", ")}`);

  let errors = 0;

  // P3-9：m2g 工具代码变更自动 force 重烤
  // 修 m2g 工具一行业务逻辑后，老 PC 跑 bootstrap 不会漏改、产出过期 .glb
  const toolVer = reconcileM2gToolVersion(REPO_ROOT, {
    hashFile: path.join(REPO_ROOT, ".cache", "m2g-tool-hash"),
    force: opts.force,
  });
  if (toolVer.force && !opts.force) {
    console.log(`[tool] 工具变更 → 自动 force=true（${toolVer.reason}）`);
  } else if (toolVer.hash) {
    console.log(`[tool] ${toolVer.reason}`);
  }
  const modelForce = toolVer.force || opts.force;

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

  if (doScn) {
    console.log("\n—— 烘焙 .scn（与 GLB 同目录）——");
    // workers 从 env 读（bootstrap.mjs 透传 WORKERS=2 等）
    const workers = Number(process.env.WORKERS || process.env.BAKE_WORKERS) || 1;
    const code = await bakeModelScenes({
      include: includesForBake(opts.include),
      force: opts.force,
      workers,
      godot: opts.godot,
    });
    if (code !== 0) errors += 1;
  }

  console.log(
    "\n全部完成。输出示例: res://assets/asset-converted/Units/.../Foo.gltf（外链 Textures/*.png）+ Foo.scn（已 gitignore）",
  );
  process.exit(errors > 0 ? 2 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
