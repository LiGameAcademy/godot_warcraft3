import fs from "node:fs";
import path from "node:path";

/**
 * 原子写盘：先写 `<dest>.tmp`，再 fs.renameSync 到目标。
 * rename 在同一文件系统下是原子的（POSIX；Windows NTFS 同样保证）。
 *
 * 目的：m2g 中途崩溃 / Node 进程被 kill / 磁盘满 → 不会留下半成品 .glb / .pe2.json。
 * 之前的隐患：NodeIO().write(PE2) 成功后再写 GLB，半路挂 → 下次 cache 看到 dest 存在就 skip，
 * 但 .pe2.json / .geosetvis.json 缺失，runtime 走 JSON fallback 但 model 也缺。
 *
 * 失败语义：写 .tmp 失败 / rename 失败 → 删 .tmp，throw；不会留 dest。
 *
 * @template T
 * @param {string} dest 最终目标路径
 * @param {(tmp: string) => T} writer 实际写入函数（传入 .tmp 路径，返回任意值透传）
 * @returns {T}
 */
export function atomicWriteSync(dest, writer) {
  const tmp = dest + ".tmp";
  /** @type {T | undefined} */
  let result;
  try {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    result = writer(tmp);
    fs.renameSync(tmp, dest);
    return result;
  } catch (err) {
    try { fs.unlinkSync(tmp); } catch { /* tmp 不存在或不可删，忽略 */ }
    throw err;
  }
}

/**
 * 写字节缓冲到目标的 atomic 版本。给 PNG / .pe2.json / .geosetvis.json 这种
 * 已知 contents 的场景用。
 *
 * @param {string} dest
 * @param {Buffer | string} data
 */
export function atomicWriteBytesSync(dest, data) {
  return atomicWriteSync(dest, (tmp) => {
    fs.writeFileSync(tmp, data);
    return data;
  });
}
