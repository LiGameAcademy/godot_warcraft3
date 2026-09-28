import path from "node:path";
import { parseMDX } from "war3-model";
import { collectSampleFrames, normalizeGeosetAlpha, sampleGeosetAlphaInSequence, wc3SequenceToAnimName } from "./anim.js";
import { mdxLogicalToAnimKeys, mdxLogicalToGeosetVis, normalizeLogicalPath } from "./paths.js";
import { atomicWriteBytesSync } from "./atomic-write.js";

import { numArray, dumpAnimVector, countKeysInInterval } from "./mdx-values.js";

/**
 * Sidecar for Godot: GLTFDocument drops scale tracks on skinned Geoset / empty
 * GeosetVis parents. Bake injects `:visible` onto Skeleton3D/Geoset_* meshes.
 *
 * @param {ReturnType<typeof parseMDX>} model
 * @param {string} logicalPath
 * @param {string} outDir
 * @param {Iterable<number>} geosetIds
 */
export function writeGeosetVisSidecar(model, logicalPath, outDir, geosetIds) {
  const ids = [...geosetIds];
  const sequencesOut = [];
  for (const seq of model.Sequences ?? []) {
    const start = Number(seq.Interval?.[0]) || 0;
    const end = Number(seq.Interval?.[1]) || 0;
    if (end <= start) continue;
    const animName = wc3SequenceToAnimName(seq.Name || "Anim");
    const frames = collectSampleFrames(
      model.Nodes || [],
      start,
      end,
      33,
      model.GeosetAnims || [],
    );
    /** @type {Record<string, Array<{ t: number, alpha: number, v: number }>>} */
    const geosets = {};
    for (const gi of ids) {
      /** @type {Array<{ t: number, alpha: number, v: number }>} */
      const keys = [];
      let lastAlpha = /** @type {number | null} */ (null);
      for (const frame of frames) {
        const timeSec = (frame - start) / 1000;
        const alphaRaw = sampleGeosetAlphaInSequence(
          model.GeosetAnims,
          gi,
          frame,
          start,
          end,
        );
        const alpha = normalizeGeosetAlpha(alphaRaw);
        const v = alpha >= 0.5 ? 1 : 0;
        if (lastAlpha === null || Math.abs(lastAlpha - alpha) > 0.0005) {
          keys.push({
            t: Math.round(timeSec * 1000) / 1000,
            alpha,
            v,
          });
          lastAlpha = alpha;
        }
      }
      geosets[String(gi)] = keys;
    }
    sequencesOut.push({
      name: animName,
      duration: Math.round(((end - start) / 1000) * 1000) / 1000,
      geosets,
    });
  }

  const visLogical = mdxLogicalToGeosetVis(logicalPath);
  const dest = path.join(outDir, ...visLogical.split("/"));
  const payload = {
    version: 2,
    source: normalizeLogicalPath(logicalPath),
    sequences: sequencesOut,
  };
  // P3-10：原子写盘
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}

/**
 * 旁路：尽量导出 MDX 原始动画关键帧（毫秒全局时间轴，非 glTF 重采样）。
 * glTF 仍按 Sequence 烤世界矩阵；本文件供对照 Hermite/Bezier 与 Interval。
 *
 * @param {ReturnType<typeof parseMDX>} model
 * @param {string} logicalPath
 * @param {string} outDir
 */
export function writeAnimKeysSidecar(model, logicalPath, outDir) {
  const sequences = [];
  for (const seq of model.Sequences ?? []) {
    const start = Number(seq.Interval?.[0]) || 0;
    const end = Number(seq.Interval?.[1]) || 0;
    if (end <= start) continue;
    const mdxName = String(seq.Name || "");
    let tKeys = 0;
    let rKeys = 0;
    let sKeys = 0;
    for (const node of model.Nodes ?? []) {
      if (!node) continue;
      tKeys += countKeysInInterval(node.Translation, start, end);
      rKeys += countKeysInInterval(node.Rotation, start, end);
      sKeys += countKeysInInterval(node.Scaling, start, end);
    }
    let alphaKeys = 0;
    for (const ga of model.GeosetAnims ?? []) {
      if (ga?.Alpha && typeof ga.Alpha !== "number") {
        alphaKeys += countKeysInInterval(ga.Alpha, start, end);
      }
    }
    sequences.push({
      name: wc3SequenceToAnimName(mdxName || "Anim"),
      mdx_name: mdxName,
      interval: [start, end],
      duration_ms: end - start,
      duration_sec: Math.round(((end - start) / 1000) * 1000) / 1000,
      looping: !seq.NonLooping,
      move_speed: Number(seq.MoveSpeed) || 0,
      rarity: Number(seq.Rarity) || 0,
      key_count: {
        translation: tKeys,
        rotation: rKeys,
        scaling: sKeys,
        geoset_alpha: alphaKeys,
      },
    });
  }

  const nodes = [];
  for (const node of model.Nodes ?? []) {
    if (!node) continue;
    const translation = dumpAnimVector(node.Translation);
    const rotation = dumpAnimVector(node.Rotation);
    const scaling = dumpAnimVector(node.Scaling);
    if (!translation && !rotation && !scaling) continue;
    nodes.push({
      name: String(node.Name || ""),
      object_id: node.ObjectId,
      parent: node.Parent ?? null,
      flags: Number(node.Flags) || 0,
      billboarded: ((Number(node.Flags) || 0) & 0x8) !== 0,
      translation,
      rotation,
      scaling,
    });
  }

  const geosetAnims = [];
  for (const ga of model.GeosetAnims ?? []) {
    if (!ga) continue;
    const alpha = dumpAnimVector(ga.Alpha);
    const color = dumpAnimVector(ga.Color);
    geosetAnims.push({
      geoset_id: ga.GeosetId,
      flags: ga.Flags ?? 0,
      alpha,
      color,
    });
  }

  const textureAnims = [];
  for (const ta of model.TextureAnims ?? []) {
    if (!ta) continue;
    const translation = dumpAnimVector(ta.Translation);
    const rotation = dumpAnimVector(ta.Rotation);
    const scaling = dumpAnimVector(ta.Scaling);
    if (!translation && !rotation && !scaling) continue;
    textureAnims.push({ translation, rotation, scaling });
  }

  const events = [];
  for (const ev of model.EventObjects ?? []) {
    if (!ev) continue;
    const frames = numArray(ev.EventTrack);
    if (!frames.length) continue;
    events.push({
      name: String(ev.Name || ""),
      object_id: ev.ObjectId,
      parent: ev.Parent ?? null,
      frames,
    });
  }

  const dest = path.join(outDir, ...mdxLogicalToAnimKeys(logicalPath).split("/"));
  const payload = {
    version: 1,
    source: normalizeLogicalPath(logicalPath),
    time_unit: "ms",
    note: "MDX 全局毫秒时间轴；Sequences.interval 为片段范围。GlobalSeqId≥0 的轨按 GlobalSequences 时钟循环，不跟 Sequence 区间走。glTF 动画已按 Sequence 归零并重采样（循环段会拉长到最长 Global Sequence）。原始 Keys 在此。",
    global_sequences: (model.GlobalSequences ?? []).map((d) => Number(d) || 0),
    sequences,
    nodes,
    geoset_anims: geosetAnims,
    texture_anims: textureAnims,
    events,
  };
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}
