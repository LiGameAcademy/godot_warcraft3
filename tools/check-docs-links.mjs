/**
 * 扫描 docs 全目录的 .md 中的内部链接，列出 docs 内解析失败的死链。
 *
 * 判定口径（与 docs/design/README.md "docs 拍平原则" 对齐）：
 *   - 只关心 [text](path) 形式；http(s) / mailto / data / file:// / 绝对 / 锚点-only 跳过。
 *   - "解析到 docs/ 内但文件不存在" 算死链（脚本退出 1）。
 *   - "解析到仓库根但不在 docs/ 下"（../../../tools/...、../../../editor/...、../../../.cursor/...
 *     等）视为外部参考，不算 docs/ 死链（仓库外孤儿路径仍报，但退出码 0）。
 *   - 链接到目录时，会尝试补上 README.md 再判存在性。
 *
 * 用法：
 *   node tools/check-docs-links.mjs                  # 默认扫描 docs/，有死链则 exit 1
 *   node tools/check-docs-links.mjs --quiet           # 只打印汇总行，CI 友好
 *   node tools/check-docs-links.mjs --docs <subdir>   # 改成扫描别的目录（如 docs/blog/）
 *
 * 与 docs/roadmap/TODO.md "死链清单" 段协同：
 *   拍平/合并文档后跑一遍，零输出即可认为 docs/ 内部链接健康。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// REPO_ROOT = __dirname/.. （tools/ 的上一级）。若以 ../tools/../docs 计算，得到仓库根。
const REPO_ROOT = path.resolve(__dirname, "..");

// ---- CLI 解析（保持轻量；不引第三方） ----
const args = process.argv.slice(2);
let docsRel = "docs";
let quiet = false;
let strict = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--quiet" || a === "-q") quiet = true;
  else if (a === "--strict") strict = true;
  else if (a === "--docs") {
    const v = args[++i];
    if (!v) throw new Error("--docs 需要参数");
    docsRel = v;
  } else if (a === "-h" || a === "--help") {
    process.stdout.write(
      [
        "check-docs-links — 扫描 docs/ markdown 内部死链",
        "",
        "用法:",
        "  node tools/check-docs-links.mjs",
        "  node tools/check-docs-links.mjs --quiet",
        "  node tools/check-docs-links.mjs --docs docs/blog",
        "  node tools/check-docs-links.mjs --strict          # 仓库外孤儿路径也算失败",
        "",
        "退出码:",
        "  0  无 docs/ 内部死链（--strict 时也无孤儿）",
        "  1  发现死链 / 孤儿（默认仅死链）",
        "  2  配置错误",
      ].join("\n") + "\n"
    );
    process.exit(0);
  } else {
    process.stderr.write(`未知参数: ${a}\n`);
    process.exit(2);
  }
}

const DOCS_ROOT = path.resolve(REPO_ROOT, docsRel);
if (!fs.existsSync(DOCS_ROOT) || !fs.statSync(DOCS_ROOT).isDirectory()) {
  process.stderr.write(`docs 根目录不存在或不是目录: ${DOCS_ROOT}\n`);
  process.exit(2);
}

// 匹配完整 markdown link "text" + "(path)"；注意要避开 inline code 里的"假链接"，
// 例如说明性段落中的 ``[text](path)``。判断法：linkText 含反引号（inline code 用）则跳过。
const LINK_RE = /\[([^\]]+)\]\(([^)\s#]+)(?:#[^)]*)?\)/g;
const SKIP_PREFIXES = ["http://", "https://", "mailto:", "data:", "file://"];

/** 递归收集所有 .md */
function collectMd(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...collectMd(p));
    else if (entry.isFile() && p.endsWith(".md")) out.push(p);
  }
  return out.sort();
}

function isExternal(raw) {
  return SKIP_PREFIXES.some((p) => raw.startsWith(p)) || raw.startsWith("/");
}

/** 把相对路径解析到绝对路径；目录会尝试补 README.md */
function resolveTarget(mdFile, raw) {
  let rp = path.resolve(path.dirname(mdFile), raw);
  if (fs.existsSync(rp) && fs.statSync(rp).isDirectory()) {
    rp = path.join(rp, "README.md");
  }
  return rp;
}

function main() {
  const mdFiles = collectMd(DOCS_ROOT);
  let totalLinks = 0;
  /** @type {{ md: string, raw: string, target: string }[]} */
  const deadInDocs = [];
  /** @type {{ md: string, raw: string, target: string }[]} */
  const orphanExternal = []; // 解析到仓库根之外（理论不该出现）

  for (const md of mdFiles) {
    const text = fs.readFileSync(md, "utf8");
    // 收集 fenced code block 范围（``` ... ```），跳过其内的伪链接
    const fenced = [];
    const fenceRe = /^```[^\n]*\n[\s\S]*?\n```/gm;
    for (const f of text.matchAll(fenceRe)) {
      fenced.push([f.index, f.index + f[0].length]);
    }
    function inFence(offset) {
      for (const [a, b] of fenced) if (offset >= a && offset < b) return true;
      return false;
    }
    for (const m of text.matchAll(LINK_RE)) {
      const linkText = m[1];
      const raw = m[2];
      // 跳过 fenced code block 内的伪链接
      if (inFence(m.index)) continue;
      // 跳过 inline code 里形如 ``[text](path)`` 的说明性示例：
      // 紧邻 m.index 的前一个字符是 `` ` ``，且紧邻 m.index + m[0].length 的字符也是 `` ` ``。
      const before = text[m.index - 1];
      const after = text[m.index + m[0].length];
      if (before === "`" && after === "`") continue;
      if (isExternal(raw)) continue;
      totalLinks++;
      const rp = resolveTarget(md, raw);
      if (fs.existsSync(rp)) continue;
      // 文件不存在 → 看解析到哪儿
      // 注意：DOCS_ROOT 是 REPO_ROOT/docs，所以"在 docs/ 内"等价于 rp 以 DOCS_ROOT 为前缀
      // 用 path.relative(DOCS_ROOT, rp) 的"是否含 .."判别更稳（避免反斜杠/正斜杠混用）。
      const relToDocs = path.relative(DOCS_ROOT, rp);
      const isInsideDocs =
        relToDocs && !relToDocs.startsWith("..") && !path.isAbsolute(relToDocs);
      if (isInsideDocs) {
        deadInDocs.push({
          md: path.relative(REPO_ROOT, md).split(path.sep).join("/"),
          raw,
          target: relToDocs.split(path.sep).join("/"),
        });
      } else {
        // 解析到 docs/ 外：可能是仓库内、可能是仓库外孤儿
        const relToRepo = path.relative(REPO_ROOT, rp).split(path.sep).join("/");
        const isInsideRepo = !relToRepo.startsWith("..") && !path.isAbsolute(relToRepo);
        orphanExternal.push({
          md: path.relative(REPO_ROOT, md).split(path.sep).join("/"),
          raw,
          target: isInsideRepo ? relToRepo : rp, // 仓库外 → 给绝对路径
        });
      }
    }
  }

  if (!quiet) {
    for (const d of deadInDocs) {
      process.stdout.write(`DEAD  ${d.md}  ::  ${d.raw}  ->  ${d.target}\n`);
    }
    for (const d of orphanExternal) {
      process.stdout.write(`ORPHAN ${d.md}  ::  ${d.raw}  ->  ${d.target}\n`);
    }
  }
  process.stdout.write(
    `扫描 ${mdFiles.length} 个 markdown（${docsRel}/），内部链接 ${totalLinks} 个，` +
      `docs 内 dead = ${deadInDocs.length}，仓库外孤儿 = ${orphanExternal.length}\n`
  );
  const fail = deadInDocs.length > 0 || (strict && orphanExternal.length > 0);
  process.exit(fail ? 1 : 0);
}

main();