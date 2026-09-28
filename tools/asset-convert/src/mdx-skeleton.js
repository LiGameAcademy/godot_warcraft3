import fs from "node:fs";
import path from "node:path";
import { parseMDL, parseMDX } from "war3-model";
import { mat4DecomposeTRS, mat4Identity, wc3ToGltfQuat, wc3ToGltfVec3 } from "./mat4.js";
import { mdxLogicalToBoneRest } from "./paths.js";
import { atomicWriteBytesSync } from "./atomic-write.js";

import { sanitizeMdxText } from "./mdx-values.js";

/**
 * 写 Stand 绑定姿态的 glTF TRS（平铺骨骼 rest）。马网格已是绑定外形 rest≈I；
 * 骑士是 T-pose 顶点，rest=Stand 世界阵才能坐上马。IBM 保持单位阵。
 * @param {Array<{ObjectId: number, Name?: string}>} skinAnimNodes
 * @param {Float32Array[]} bindWorlds
 * @param {Array<{getName(): string}>} jointList
 * @param {string} logicalPath
 * @param {string} outDir
 */
export function writeBoneRestSidecar(skinAnimNodes, bindWorlds, jointList, logicalPath, outDir) {
  const bones = [];
  for (let i = 0; i < jointList.length; i += 1) {
    const src = skinAnimNodes[i];
    const { t, r, s } = transformMat4Wc3ToGltf(bindWorlds[src.ObjectId] || mat4Identity());
    bones.push({
      name: jointList[i].getName(),
      translation: t,
      rotation: r,
      scale: s,
    });
  }
  const logical = mdxLogicalToBoneRest(logicalPath);
  const dest = path.join(outDir, ...logical.split("/"));
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  atomicWriteBytesSync(dest, `${JSON.stringify({ version: 2, bones }, null, 2)}\n`);
  if (globalThis.__WC3_DEBUG_JOINT) console.log("[bone_rest] wrote", dest, "bones=", bones.length);
  return dest;
}

/**
 * Helpers 里真正的骨架骨（Bone_Root / Bone_Foot_L 等）不在 model.Bones。
 * 追加进 Skin 时必须排在 Bones 之后，以免改 JOINTS_0 下标。
 * @param {object} model
 * @param {Array<{ ObjectId?: number }>} boneNodes
 */
export function extraHelperNodes(model, boneNodes) {
  const seen = new Set((boneNodes ?? []).map((b) => b.ObjectId));
  const extras = [];
  for (const h of model.Helpers ?? []) {
    if (!h || h.ObjectId == null || seen.has(h.ObjectId)) continue;
    seen.add(h.ObjectId);
    extras.push(h);
  }
  return extras;
}

export function uniqueJointName(src, used) {
  const base =
    sanitizeMdxText(src?.Name || `Bone_${src?.ObjectId}`) || `Bone_${src?.ObjectId}`;
  if (!used.has(base)) {
    used.add(base);
    return base;
  }
  const alt = `${base}_${src.ObjectId}`;
  used.add(alt);
  return alt;
}

/**
 * @param {ArrayBuffer | Buffer} data
 * @param {string} logicalPath
 */
export function parseModel(data, logicalPath) {
  const buf =
    data instanceof ArrayBuffer
      ? data
      : data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  if (logicalPath.toLowerCase().endsWith(".mdl")) {
    return parseMDL(Buffer.from(buf).toString("utf8"));
  }
  return parseMDX(buf);
}

export function transformMat4Wc3ToGltf(m) {
  // Apply basis change B * M * B^-1 for column-major M, B:(x,y,z)->(x,z,-y)
  // Faster: transform translation and rebuild from decomposed TRS.
  const { t, r, s } = mat4DecomposeTRS(m);
  const tg = wc3ToGltfVec3(t[0], t[1], t[2]);
  const rg = wc3ToGltfQuat(r[0], r[1], r[2], r[3]);
  // Scale axes permute with basis: (sx,sy,sz)_wc3 -> (sx,sz,sy)
  const sg = [s[0], s[2], s[1]];
  return { t: tg, r: rg, s: sg };
}

export function quatNearlyEqual(a, b) {
  const dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
  return Math.abs(Math.abs(dot) - 1) < 2e-3;
}

/** 循环段拉长后，静止骨骼不必每 33ms 写一帧。 */
export function collapseConstantTrsTrack(track) {
  const n = track.times.length;
  if (n <= 2) return track;
  const t0 = [track.t[0], track.t[1], track.t[2]];
  const r0 = [track.r[0], track.r[1], track.r[2], track.r[3]];
  const s0 = [track.s[0], track.s[1], track.s[2]];
  for (let i = 1; i < n; i += 1) {
    const ri = [track.r[i * 4], track.r[i * 4 + 1], track.r[i * 4 + 2], track.r[i * 4 + 3]];
    if (
      Math.abs(track.t[i * 3] - t0[0]) > 0.05 ||
      Math.abs(track.t[i * 3 + 1] - t0[1]) > 0.05 ||
      Math.abs(track.t[i * 3 + 2] - t0[2]) > 0.05 ||
      !quatNearlyEqual(r0, ri) ||
      Math.abs(track.s[i * 3] - s0[0]) > 1e-3 ||
      Math.abs(track.s[i * 3 + 1] - s0[1]) > 1e-3 ||
      Math.abs(track.s[i * 3 + 2] - s0[2]) > 1e-3
    ) {
      return track;
    }
  }
  const last = n - 1;
  return {
    times: [track.times[0], track.times[last]],
    t: [t0[0], t0[1], t0[2], track.t[last * 3], track.t[last * 3 + 1], track.t[last * 3 + 2]],
    r: [...r0, track.r[last * 4], track.r[last * 4 + 1], track.r[last * 4 + 2], track.r[last * 4 + 3]],
    s: [s0[0], s0[1], s0[2], track.s[last * 3], track.s[last * 3 + 1], track.s[last * 3 + 2]],
  };
}

export function collapseConstantScaleTrack(track) {
  const n = track.times.length;
  if (n <= 2) return track;
  const s0 = track.s[0];
  for (let i = 1; i < n; i += 1) {
    if (Math.abs(track.s[i * 3] - s0) > 1e-6) return track;
  }
  const last = n - 1;
  return {
    times: [track.times[0], track.times[last]],
    s: [
      track.s[0],
      track.s[1],
      track.s[2],
      track.s[last * 3],
      track.s[last * 3 + 1],
      track.s[last * 3 + 2],
    ],
  };
}
