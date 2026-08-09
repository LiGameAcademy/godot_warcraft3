#!/usr/bin/env node
/**
 * 新设备一键准备开发资源（解包 → 表/地图 → 转换 → Godot bake/PE2/visuals）。
 *
 * 用法（仓库根目录）:
 *   node tools/dev-setup.mjs --game-dir "D:/Warcraft III"
 *   .\tools\Dev-Setup.ps1 -GameDir "D:\Warcraft III"
 *
 * 环境变量:
 *   WC3_GAME_DIR / WAR3_GAME_DIR  经典客户端目录（含 War3.mpq）
 *   GODOT / GODOT_BIN             Godot 4.x console 可执行文件
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { findGodotExecutable } from "./lib/godot-cli.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const TOOL_PKGS = ["mpq-extract", "asset-convert", "slk-export", "map-parse"];

const MAP_CANDIDATES = {
  echoisles: [
    "Maps/FrozenThrone/(2)EchoIsles.w3x",
    "Maps/(2)EchoIsles.w3x",
    "Maps/FrozenThrone/(2)Echo Isles.w3x",
    "Maps/(2)Echo Isles.w3x",
  ],
  losttemple: [
    "Maps/FrozenThrone/(4)LostTemple.w3x",
    "Maps/(4)LostTemple.w3x",
    "Maps/FrozenThrone/(4)Lost Temple.w3x",
  ],
};

function printHelp() {
  console.log(`godot_warcraft3 开发资源一键准备

用法:
  node tools/dev-setup.mjs --game-dir "<经典WC3安装目录>" [选项]

必填（除非 --skip-extract 且缓存已存在）:
  --game-dir <path>     含 War3.mpq / War3x.mpq 的经典客户端目录
                        也可用环境变量 WC3_GAME_DIR

配置档:
  --profile game        默认。Echo Isles + 人族 Melee 子集（推荐新设备）
  --profile lost-temple Lost Temple 可视复原子集
  --profile full        全量 BLP/MDX 转换（很慢、体积大）
  --profile deps-only   只 npm install，不解包/转换

步骤开关（默认真线跑完）:
  --skip-install        跳过各 tools/*/npm install
  --skip-extract        跳过 MPQ 解包（需已有 .cache/wc3-assets）
  --skip-slk            跳过 SLK→JSON
  --skip-maps           跳过地图解析
  --skip-convert        跳过贴图/模型转换
  --skip-sync           跳过编辑器 UI 同步
  --skip-godot          跳过 Godot bake / PE2 / visuals
  --only <step>         只跑一步: install|extract|slk|maps|convert|sync|godot
                        （可重复）

其它:
  --maps echoisles,losttemple   要解析的地图（默认 echoisles）
  --force               强制重解/重转/重导
  --godot <path>        Godot 可执行文件
  --extract-include <g> 解包 include glob（可重复；默认全量）
  -h, --help

典型新电脑:
  node tools/dev-setup.mjs --game-dir "D:/Program Files (x86)/Warcraft3"
  # 设好 GODOT 后，同命令会自动 bake .scn + 导 TownHall PE2/visuals

完成后:
  Godot 打开本仓库 → 运行 game/scenes/game_main.tscn（F6）
`);
}

function parseArgs(argv) {
  const opts = {
    gameDir: process.env.WC3_GAME_DIR || process.env.WAR3_GAME_DIR || "",
    profile: "game",
    maps: ["echoisles"],
    force: false,
    godot: "",
    extractIncludes: [],
    skip: {
      install: false,
      extract: false,
      slk: false,
      maps: false,
      convert: false,
      sync: false,
      godot: false,
    },
    only: [],
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const need = () => {
      if (!argv[i + 1]) throw new Error(`${a} 需要参数`);
      return argv[++i];
    };
    switch (a) {
      case "-h":
      case "--help":
        opts.help = true;
        break;
      case "--game-dir":
        opts.gameDir = need();
        break;
      case "--profile":
        opts.profile = need();
        break;
      case "--maps":
        opts.maps = need()
          .split(",")
          .map((s) => s.trim().toLowerCase())
          .filter(Boolean);
        break;
      case "--force":
        opts.force = true;
        break;
      case "--godot":
        opts.godot = need();
        break;
      case "--extract-include":
        opts.extractIncludes.push(need());
        break;
      case "--skip-install":
        opts.skip.install = true;
        break;
      case "--skip-extract":
        opts.skip.extract = true;
        break;
      case "--skip-slk":
        opts.skip.slk = true;
        break;
      case "--skip-maps":
        opts.skip.maps = true;
        break;
      case "--skip-convert":
        opts.skip.convert = true;
        break;
      case "--skip-sync":
        opts.skip.sync = true;
        break;
      case "--skip-godot":
        opts.skip.godot = true;
        break;
      case "--only":
        opts.only.push(need().toLowerCase());
        break;
      default:
        if (a.startsWith("-")) throw new Error(`未知参数: ${a}`);
        break;
    }
  }
  if (opts.profile === "deps-only") {
    opts.skip.extract = true;
    opts.skip.slk = true;
    opts.skip.maps = true;
    opts.skip.convert = true;
    opts.skip.sync = true;
    opts.skip.godot = true;
  }
  if (opts.only.length) {
    const all = Object.keys(opts.skip);
    for (const k of all) opts.skip[k] = !opts.only.includes(k);
  }
  return opts;
}

function logStep(title) {
  console.log(`\n${"=".repeat(60)}\n>>> ${title}\n${"=".repeat(60)}`);
}

function run(cmd, args, cwd = ROOT, envExtra = {}) {
	const printable = args.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
	console.log(`$ ${cmd} ${printable}`);
	const r = spawnSync(cmd, args, {
		cwd,
		stdio: "inherit",
		shell: false,
		env: { ...process.env, ...envExtra },
	});
	if (r.error) {
		console.error(r.error.message);
		return 1;
	}
	return r.status ?? 1;
}

function runNpm(args, cwd, envExtra = {}) {
	// Windows 上 npm.cmd 需要 shell；参数仍按数组传入，避免路径被二次拆分
	const npmCmd = process.platform === "win32" ? "npm.cmd" : "npm";
	const printable = args.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
	console.log(`$ ${npmCmd} ${printable}`);
	const r = spawnSync(npmCmd, args, {
		cwd,
		stdio: "inherit",
		shell: true,
		env: { ...process.env, ...envExtra },
		windowsVerbatimArguments: false,
	});
	if (r.error) {
		console.error(r.error.message);
		return 1;
	}
	return r.status ?? 1;
}

function runNode(scriptRel, args = [], cwd = ROOT) {
  return run(process.execPath, [path.join(ROOT, scriptRel), ...args], cwd);
}

function npmInstall(pkg) {
  const dir = path.join(ROOT, "tools", pkg);
  if (!fs.existsSync(path.join(dir, "package.json"))) {
    console.warn(`跳过 npm install: 无 package.json (${pkg})`);
    return 0;
  }
  return runNpm(["install"], dir);
}

function cacheReady() {
  const p = path.join(ROOT, ".cache", "wc3-assets");
  return fs.existsSync(p) && fs.readdirSync(p).length > 0;
}

function resolveGameDir(gameDir) {
  if (!gameDir) return "";
  const abs = path.resolve(gameDir);
  const mpq = path.join(abs, "War3.mpq");
  const mpq2 = path.join(abs, "war3.mpq");
  if (!fs.existsSync(mpq) && !fs.existsSync(mpq2)) {
    console.error(`目录内未找到 War3.mpq: ${abs}`);
    console.error("需要经典 MPQ 客户端，不是仅含 Data/ 的现代 CASC 客户端。见 docs/data/LEGAL.md");
    return "";
  }
  return abs;
}

function findMapFile(gameDir, slug) {
  const cands = MAP_CANDIDATES[slug] || [];
  for (const rel of cands) {
    const p = path.join(gameDir, ...rel.split("/"));
    if (fs.existsSync(p)) return p;
  }
  // 宽松搜索文件名
  const mapsRoot = path.join(gameDir, "Maps");
  if (!fs.existsSync(mapsRoot)) return "";
  const needle = slug === "echoisles" ? "echoisles" : "losttemple";
  const stack = [mapsRoot];
  while (stack.length) {
    const d = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) stack.push(full);
      else if (e.name.toLowerCase().endsWith(".w3x") && e.name.toLowerCase().replace(/[^a-z0-9]/g, "").includes(needle)) {
        return full;
      }
    }
  }
  return "";
}

function stepInstall() {
  logStep("1. npm install（tools）");
  for (const pkg of TOOL_PKGS) {
    const code = npmInstall(pkg);
    if (code !== 0) return code;
  }
  return 0;
}

function stepExtract(opts, gameDir) {
	logStep("2. MPQ 解包 → .cache/wc3-assets");
	const args = ["src/cli.js", "--game-dir", gameDir];
	if (opts.force) args.push("--force");
	for (const g of opts.extractIncludes) {
		args.push("--include", g);
	}
	return run(process.execPath, args, path.join(ROOT, "tools", "mpq-extract"));
}

function stepSlk(opts) {
  logStep("3. SLK → assets/slk-exported");
  const args = ["src/cli.js"];
  if (opts.force) args.push("--overwrite");
  return run(process.execPath, args, path.join(ROOT, "tools", "slk-export"));
}

function stepMaps(opts, gameDir) {
	logStep("4. 地图解析 → assets/map-parsed");
	for (const slug of opts.maps) {
		const mapPath = findMapFile(gameDir, slug);
		if (!mapPath) {
			console.error(`找不到地图 ${slug}。请确认客户端 Maps/ 下有对应 .w3x，或手动:`);
			console.error(`  cd tools/map-parse && node src/cli.js --map "<path>.w3x" --force`);
			return 1;
		}
		console.log(`解析 ${slug}: ${mapPath}`);
		// 直接调 node，避免 npm 在 Windows 上把带空格路径拆碎
		const args = ["src/cli.js", "--map", mapPath];
		if (opts.force) args.push("--force");
		const code = run(process.execPath, args, path.join(ROOT, "tools", "map-parse"));
		if (code !== 0) return code;
	}
	return 0;
}

function stepConvert(opts) {
	logStep("5. 资产转换 BLP/MDX → assets/asset-converted");
	const ac = path.join(ROOT, "tools", "asset-convert");
	const env = opts.godot ? { GODOT: opts.godot } : {};
	if (opts.profile === "full") {
		const args = ["src/cli.js"];
		if (opts.force) args.push("--force");
		if (opts.godot) args.push("--godot", opts.godot);
		return run(process.execPath, args, ac, env);
	}
	if (opts.profile === "lost-temple") {
		const script = path.join(ac, "scripts", "convert-lost-temple.mjs");
		const args = [script];
		if (opts.force) args.push("--force");
		return run(process.execPath, args, ac, env);
	}
	// game（默认）= echo isles 子集
	const script = path.join(ac, "scripts", "convert-echo-isles.mjs");
	const args = [script];
	if (opts.force) args.push("--force");
	if (opts.godot) args.push("--godot", opts.godot);
	return run(process.execPath, args, ac, env);
}

function stepSync(opts) {
  logStep("6. sync-data-assets → slk-exported + PathTextures");
  const args = ["tools/sync-data-assets.mjs"];
  if (opts.force) args.push("--force");
  return run(process.execPath, args, ROOT);
}

function stepGodot(opts) {
  logStep("7. Godot：bake .scn + PE2 粒子预制 + visuals");
  const godot = findGodotExecutable(opts.godot);
  if (!godot) {
    console.warn(
      "未找到 Godot，跳过本步。设置 GODOT 后可单独重跑:\n" +
        "  node tools/export-godot-assets.mjs --include Buildings/Human/ --force",
    );
    return 0;
  }
  const args = ["tools/export-godot-assets.mjs", "--include", "Buildings/Human/", "--godot", godot];
  // convert 已可能 bake 过；这里 force 仅当用户要求
  if (opts.force) args.push("--force");
  // 对 game 档再补导常用中立建筑粒子
  args.push("--include", "Buildings/Other/");
  return run(process.execPath, args, ROOT);
}

function printSummary(opts, gameDir) {
  console.log(`\n${"=".repeat(60)}`);
  console.log("准备完成。验收清单:");
  console.log(`  [ ] .cache/wc3-assets/ 非空`);
  console.log(`  [ ] assets/slk-exported/Units/UnitBalance.json`);
  console.log(`  [ ] assets/map-parsed/echoisles/（或你指定的地图）`);
  console.log(`  [ ] assets/asset-converted/ 含 PNG/GLB`);
  console.log(`  [ ] （可选）assets/pe2-prefabs/ / assets/visuals/`);
  console.log("");
  console.log("打开 Godot 4.6 → 导入本仓库 → 运行:");
  console.log("  game/scenes/game_main.tscn     # Echo Isles 对战壳（推荐）");
  console.log("  editor/scenes/editor_main.tscn # 地图编辑器");
  console.log("");
  console.log("热键: S=Stop 选中单位 | F9=路径调试");
  if (gameDir) console.log(`经典客户端: ${gameDir}`);
  console.log(`配置档: ${opts.profile}`);
  console.log(`${"=".repeat(60)}\n`);
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(e.message ?? e);
    printHelp();
    process.exit(1);
  }
  if (opts.help) {
    printHelp();
    process.exit(0);
  }

  console.log("godot_warcraft3 · dev-setup");
  console.log(`仓库: ${ROOT}`);

  if (!opts.skip.extract || !opts.skip.maps) {
    const gd = resolveGameDir(opts.gameDir);
    if (!gd) {
      if (!opts.skip.extract && !cacheReady()) {
        console.error("\n请提供 --game-dir，或设置 WC3_GAME_DIR。");
        printHelp();
        process.exit(1);
      }
      if (!opts.skip.maps && !opts.gameDir) {
        console.error("解析地图需要 --game-dir（用于在 Maps/ 下找 .w3x）。");
        process.exit(1);
      }
    }
    opts._gameDir = gd || path.resolve(opts.gameDir || "");
  } else {
    opts._gameDir = opts.gameDir ? path.resolve(opts.gameDir) : "";
  }

  const godotHint = findGodotExecutable(opts.godot);
  console.log(`Godot: ${godotHint || "(未找到 — convert 仍可出 GLB，bake/PE2 将跳过)"}`);

  /** @type {Array<[string, () => number]>} */
  const pipeline = [];
  if (!opts.skip.install) pipeline.push(["install", () => stepInstall()]);
  if (!opts.skip.extract) {
    pipeline.push(["extract", () => stepExtract(opts, opts._gameDir)]);
  } else if (!cacheReady()) {
    console.warn("警告: --skip-extract 但 .cache/wc3-assets 为空，后续转换可能失败。");
  }
  if (!opts.skip.slk) pipeline.push(["slk", () => stepSlk(opts)]);
  if (!opts.skip.maps) pipeline.push(["maps", () => stepMaps(opts, opts._gameDir)]);
  if (!opts.skip.convert) pipeline.push(["convert", () => stepConvert(opts)]);
  if (!opts.skip.sync) pipeline.push(["sync", () => stepSync(opts)]);
  if (!opts.skip.godot) pipeline.push(["godot", () => stepGodot(opts)]);

  for (const [name, fn] of pipeline) {
    const code = fn();
    if (code !== 0) {
      console.error(`\ndev-setup 失败于步骤: ${name} (exit ${code})`);
      process.exit(code);
    }
  }

  printSummary(opts, opts._gameDir);
  process.exit(0);
}

main();
