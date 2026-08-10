import fs from "node:fs";
import path from "node:path";
import { Document, NodeIO } from "@gltf-transform/core";
import { parseMDL, parseMDX } from "war3-model";
import {
  collectSampleFrames,
  evaluateNodeWorldMatrices,
  sampleGeosetAlphaInSequence,
} from "./anim.js";
import { blpBufferToPng, writePlaceholderPng } from "./convert-blp.js";
import {
  mat4DecomposeTRS,
  mat4Identity,
  wc3ToGltfQuat,
  wc3ToGltfVec3,
} from "./mat4.js";
import {
  blpLogicalToPng,
  mdxLogicalToGeosetVis,
  mdxLogicalToGltf,
  mdxLogicalToPe2,
  normalizeLogicalPath,
  uriFromModelToPng,
} from "./paths.js";
import { walkFiles } from "./walk.js";
import { atomicWriteSync, atomicWriteBytesSync } from "./atomic-write.js";

const MODEL_SCALE = 0.01;

/** 合法 .gltf：JSON 且含 asset.version（方案 B 外链贴图）。 */
function isValidGltfOnDisk(absPath) {
  let fd;
  try {
    fd = fs.openSync(absPath, "r");
  } catch {
    return false;
  }
  try {
    const stat = fs.fstatSync(fd);
    if (stat.size < 32) return false;
    const n = Math.min(stat.size, 256);
    const buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, 0);
    const head = buf.toString("utf8").trimStart();
    if (!head.startsWith("{")) return false;
    return /"asset"\s*:/.test(head);
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      /* ignore */
    }
  }
}

function unlinkQuiet(p) {
  try {
    fs.unlinkSync(p);
  } catch {
    /* ignore */
  }
}

/** @param {unknown} v */
function asVec3(v) {
  if (v == null) return [0, 0, 0];
  if (Array.isArray(v) || ArrayBuffer.isView(v)) {
    return [Number(v[0]) || 0, Number(v[1]) || 0, Number(v[2]) || 0];
  }
  const o = /** @type {Record<string, number>} */ (v);
  return [Number(o[0] ?? o["0"]) || 0, Number(o[1] ?? o["1"]) || 0, Number(o[2] ?? o["2"]) || 0];
}

/**
 * Animated track → [{frame,value}]；静态 number → null。
 * @param {unknown} track
 * @returns {Array<{ frame: number, value: number }> | null}
 */
function animTrackKeys(track) {
  if (track == null || typeof track === "number") return null;
  const keys = /** @type {{ Keys?: Array<{ Frame: number, Vector: ArrayLike<number> }> }} */ (
    track
  ).Keys;
  if (!keys?.length) return null;
  return keys.map((k) => ({
    frame: Number(k.Frame) || 0,
    value: Number(k.Vector?.[0]) || 0,
  }));
}

/**
 * @param {Array<{ frame: number, value: number }> | null} keys
 * @param {number} frame
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {number} defaultValue 区间内无 key 时的默认（Visibility=1，EmissionRate=0）
 */
function sampleTrackInSequence(keys, frame, seqStart, seqEnd, defaultValue) {
  if (!keys?.length) return defaultValue;
  const sk = keys.filter((k) => k.frame >= seqStart && k.frame <= seqEnd);
  if (!sk.length) return defaultValue;
  if (frame < sk[0].frame) return defaultValue;
  let value = sk[0].value;
  for (const k of sk) {
    if (k.frame <= frame) value = k.value;
    else break;
  }
  return value;
}

/** @param {unknown} track */
function emissionRateForAmount(track) {
  if (typeof track === "number") return track;
  const keys = animTrackKeys(track);
  if (!keys?.length) return 0;
  return Math.max(0, ...keys.map((k) => k.value));
}

/**
 * 该发射器在哪些 Sequence 中应发光（vis≥0.5 且 rate>0）。
 * 返回 null = 全程开启（装饰物火盆等：无 Visibility 轨 + 静态 rate>0）。
 * 死亡爆发等脉冲 rate：只要区间内任一关键帧 rate>0 且当时可见即计入（勿只采中点）。
 * @param {object} pe
 * @param {Array<{ Name?: string, Interval: ArrayLike<number> }>} sequences
 * @returns {string[] | null}
 */
function activeSequencesForEmitter(pe, sequences) {
  const visKeys = animTrackKeys(pe.Visibility);
  const rateKeys = animTrackKeys(pe.EmissionRate);
  const staticRate = typeof pe.EmissionRate === "number" ? pe.EmissionRate : null;
  if (visKeys == null && staticRate != null && staticRate > 0) {
    return null;
  }
  const out = [];
  for (const s of sequences || []) {
    const start = Number(s.Interval?.[0]) || 0;
    const end = Number(s.Interval?.[1]) || start;
    if (_emitterActiveInSequence(visKeys, rateKeys, staticRate, start, end)) {
      out.push(String(s.Name || "").trim());
    }
  }
  return out;
}

/**
 * @param {Array<{ frame: number, value: number }> | null} visKeys
 * @param {Array<{ frame: number, value: number }> | null} rateKeys
 * @param {number | null} staticRate
 * @param {number} start
 * @param {number} end
 */
function _emitterActiveInSequence(visKeys, rateKeys, staticRate, start, end) {
  const mid = Math.floor((start + end) / 2);
  if (staticRate != null) {
    const vis = sampleTrackInSequence(visKeys, mid, start, end, 1);
    return vis >= 0.5 && staticRate > 0.01;
  }
  // 动画 rate：检查区间内每个 rate>0 的关键帧（含脉冲爆发）
  const sampleFrames = new Set([mid, start, end]);
  for (const k of rateKeys || []) {
    if (k.frame >= start && k.frame <= end) sampleFrames.add(k.frame);
  }
  for (const k of visKeys || []) {
    if (k.frame >= start && k.frame <= end) sampleFrames.add(k.frame);
  }
  for (const frame of sampleFrames) {
    const vis = sampleTrackInSequence(visKeys, frame, start, end, 1);
    const rate = sampleTrackInSequence(rateKeys, frame, start, end, 0);
    if (vis >= 0.5 && rate > 0.01) return true;
  }
  return false;
}

/**
 * Serialize ParticleEmitters2 (+ ensure textures on disk) next to the GLB.
 * @param {object} model
 * @param {string} logicalPath
 * @param {string} inDir
 * @param {string} outDir
 */
function writePe2Sidecar(model, logicalPath, inDir, outDir) {
  const emittersIn = model.ParticleEmitters2 ?? [];
  const textures = model.Textures ?? [];
  const sequences = model.Sequences ?? [];
  const emitters = [];

  for (const pe of emittersIn) {
    const tid = typeof pe.TextureID === "number" ? pe.TextureID : 0;
    const texInfo = textures[tid];
    const resolved = resolveTexturePng(texInfo?.Image ?? "", inDir, outDir, {
      isReplaceable: Boolean(texInfo?.ReplaceableId),
      replaceableId: texInfo?.ReplaceableId || 0,
    });
    const pivotWc3 = asVec3(pe.PivotPoint);
    const pivot = wc3ToGltfVec3(pivotWc3[0], pivotWc3[1], pivotWc3[2]);
    const seg = Array.isArray(pe.SegmentColor) ? pe.SegmentColor : [];
    const visKeys = animTrackKeys(pe.Visibility);
    const rateKeys = animTrackKeys(pe.EmissionRate);
    const active = activeSequencesForEmitter(pe, sequences);
    const entry = {
      name: String(pe.Name || `PE2_${pe.ObjectId ?? emitters.length}`),
      object_id: pe.ObjectId ?? -1,
      parent: pe.Parent ?? null,
      flags: pe.Flags ?? 0,
      speed: typeof pe.Speed === "number" ? pe.Speed : Number(pe.Speed) || 0,
      variation: typeof pe.Variation === "number" ? pe.Variation : Number(pe.Variation) || 0,
      latitude: typeof pe.Latitude === "number" ? pe.Latitude : Number(pe.Latitude) || 0,
      gravity: typeof pe.Gravity === "number" ? pe.Gravity : Number(pe.Gravity) || 0,
      life_span: typeof pe.LifeSpan === "number" ? pe.LifeSpan : Number(pe.LifeSpan) || 0.1,
      emission_rate: emissionRateForAmount(pe.EmissionRate),
      width: typeof pe.Width === "number" ? pe.Width : Number(pe.Width) || 0,
      length: typeof pe.Length === "number" ? pe.Length : Number(pe.Length) || 0,
      filter_mode: Number(pe.FilterMode) || 0,
      rows: Math.max(1, Number(pe.Rows) || 1),
      columns: Math.max(1, Number(pe.Columns) || 1),
      frame_flags: Number(pe.FrameFlags) || 0,
      time_middle: Number(pe.Time) || 0.5,
      segment_color: [asVec3(seg[0]), asVec3(seg[1]), asVec3(seg[2])],
      alpha: asVec3(pe.Alpha),
      particle_scaling: asVec3(pe.ParticleScaling),
      life_span_uv: asVec3(pe.LifeSpanUVAnim),
      decay_uv: asVec3(pe.DecayUVAnim),
      texture: resolved.pngLogical,
      priority_plane: Number(pe.PriorityPlane) || 0,
      pivot,
      // null = 全程发射（火盆等）；数组 = 仅这些 Sequence 名下发射
      active_sequences: active,
    };
    if (visKeys) entry.visibility_keys = visKeys;
    if (rateKeys) entry.emission_rate_keys = rateKeys;
    emitters.push(entry);
  }

  const pe2Logical = mdxLogicalToPe2(logicalPath);
  const dest = path.join(outDir, ...pe2Logical.split("/"));
  const payload = {
    version: 2,
    source: normalizeLogicalPath(logicalPath),
    sequences: sequences.map((s) => ({
      name: String(s.Name || ""),
      interval: [Number(s.Interval?.[0]) || 0, Number(s.Interval?.[1]) || 0],
    })),
    emitters,
  };
  // P3-10：原子写盘（.tmp → rename）—— 中途崩溃不留半成品 .pe2.json
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}

/**
 * Sidecar for Godot: GLTFDocument drops scale tracks on skinned Geoset / empty
 * GeosetVis parents. Bake injects `:visible` onto Skeleton3D/Geoset_* meshes.
 *
 * @param {ReturnType<typeof parseMDX>} model
 * @param {string} logicalPath
 * @param {string} outDir
 * @param {Iterable<number>} geosetIds
 */
function writeGeosetVisSidecar(model, logicalPath, outDir, geosetIds) {
  const ids = [...geosetIds];
  const sequencesOut = [];
  for (const seq of model.Sequences ?? []) {
    const start = Number(seq.Interval?.[0]) || 0;
    const end = Number(seq.Interval?.[1]) || 0;
    if (end <= start) continue;
    const animName = String(seq.Name || "Anim").replace(/\s+/g, "_");
    const frames = collectSampleFrames(
      model.Nodes || [],
      start,
      end,
      33,
      model.GeosetAnims || [],
    );
    /** @type {Record<string, Array<{ t: number, v: number }>>} */
    const geosets = {};
    for (const gi of ids) {
      /** @type {Array<{ t: number, v: number }>} */
      const keys = [];
      let last = /** @type {number | null} */ (null);
      for (const frame of frames) {
        const timeSec = (frame - start) / 1000;
        const alpha = sampleGeosetAlphaInSequence(
          model.GeosetAnims,
          gi,
          frame,
          start,
          end,
        );
        const v = alpha >= 0.5 ? 1 : 0;
        if (last === null || last !== v) {
          keys.push({ t: Math.round(timeSec * 1000) / 1000, v });
          last = v;
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
    version: 1,
    source: normalizeLogicalPath(logicalPath),
    sequences: sequencesOut,
  };
  // P3-10：原子写盘
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}

/**
 * @param {ArrayBuffer | Buffer} data
 * @param {string} logicalPath
 */
function parseModel(data, logicalPath) {
  const buf =
    data instanceof ArrayBuffer
      ? data
      : data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  if (logicalPath.toLowerCase().endsWith(".mdl")) {
    return parseMDL(Buffer.from(buf).toString("utf8"));
  }
  return parseMDX(buf);
}

/** Classic WC3 replaceable texture IDs → default BLP (used when Image is empty). */
const REPLACEABLE_DEFAULTS = {
	1: null, // team color → _placeholders/team_color.png
	2: null, // team glow → _placeholders/team_glow.png（编辑器常跳过纯 glow geoset）
	11: "ReplaceableTextures/Cliff/Cliff0.blp",
	31: "ReplaceableTextures/LordaeronTree/LordaeronSnowTree.blp",
	// Icecrown / Lost Temple uses Ice_Tree on AshenTree models (ITtw).
	32: "ReplaceableTextures/AshenvaleTree/Ice_Tree.blp",
	33: "ReplaceableTextures/BarrensTree/BarrensTree.blp",
	34: "ReplaceableTextures/NorthrendTree/NorthTree.blp",
	35: "ReplaceableTextures/Mushroom/MushroomTree.blp",
	36: "ReplaceableTextures/RuinsTree/RuinsTree.blp",
	37: "ReplaceableTextures/UndergroundTree/UnderTree.blp",
};

/** ReplaceableId → 占位 PNG 逻辑路径与默认 RGBA */
const REPLACEABLE_PLACEHOLDERS = {
	1: { pngLogical: "_placeholders/team_color.png", rgba: [30, 70, 180, 255] },
	// 半透明白：加法混合时才像光晕；误当成不透明时也不至于整块实心蓝
	2: { pngLogical: "_placeholders/team_glow.png", rgba: [255, 255, 255, 96] },
};

/**
 * @param {string} logical
 * @param {string} inDir
 */
function findBlpOnDisk(logical, inDir) {
  const parts = normalizeLogicalPath(logical).split("/");
  let cur = inDir;
  for (const part of parts) {
    if (!fs.existsSync(cur)) return null;
    const names = fs.readdirSync(cur);
    const hit = names.find((n) => n.toLowerCase() === part.toLowerCase());
    if (!hit) return null;
    cur = path.join(cur, hit);
  }
  return fs.existsSync(cur) ? cur : null;
}

function resolveTexturePng(
	imagePath,
	inDir,
	outDir,
	{ isReplaceable = false, replaceableId = 0 } = {},
) {
	let raw = normalizeLogicalPath(imagePath || "");
	if (!raw && replaceableId) {
		const def = REPLACEABLE_DEFAULTS[replaceableId];
		if (def) raw = def;
	}
	if (!raw) {
		const ph =
			REPLACEABLE_PLACEHOLDERS[replaceableId] ||
			REPLACEABLE_PLACEHOLDERS[1];
		const pngLogical = ph.pngLogical;
		const dest = path.join(outDir, ...pngLogical.split("/"));
		if (!fs.existsSync(dest)) writePlaceholderPng(dest, ph.rgba);
		return {
			pngLogical,
			pngBytes: fs.readFileSync(dest),
			isReplaceable: true,
			replaceableId: replaceableId || 1,
		};
	}

	const pngLogical = blpLogicalToPng(raw);
	const pngDest = path.join(outDir, ...pngLogical.split("/"));
	if (fs.existsSync(pngDest)) {
		return {
			pngLogical,
			pngBytes: fs.readFileSync(pngDest),
			isReplaceable,
			replaceableId: replaceableId || 0,
		};
	}

	const blpSrc = findBlpOnDisk(raw, inDir);
	if (!blpSrc) {
		console.warn(`  缺少贴图: ${raw} → 占位`);
		const pngLogicalPh = "_placeholders/missing.png";
		const dest = path.join(outDir, ...pngLogicalPh.split("/"));
		if (!fs.existsSync(dest)) writePlaceholderPng(dest, [255, 0, 0, 255]);
		return {
			pngLogical: pngLogicalPh,
			pngBytes: fs.readFileSync(dest),
			isReplaceable,
			replaceableId: replaceableId || 0,
		};
	}

	const pngBytes = blpBufferToPng(fs.readFileSync(blpSrc));
	fs.mkdirSync(path.dirname(pngDest), { recursive: true });
	fs.writeFileSync(pngDest, pngBytes);
	return {
		pngLogical,
		pngBytes,
		isReplaceable,
		replaceableId: replaceableId || 0,
	};
}

function textureIdOfLayer(layer) {
	const tid = layer?.TextureID;
	return typeof tid === "number" ? tid : 0;
}

/**
 * Pick the best diffuse layer: prefer a layer with a real Image path.
 * Fixes team-color-first materials (Layer0=Replaceable, Layer1=Footman.blp).
 */
function pickDiffuseLayer(matDef, textures) {
	const layers = matDef?.Layers ?? [];
	for (const layer of layers) {
		const tid = textureIdOfLayer(layer);
		const tex = textures?.[tid];
		if (tex?.Image) {
			return { layer, textureId: tid, replaceableId: tex.ReplaceableId || 0 };
		}
	}
	const layer = layers[0] ?? {};
	const tid = textureIdOfLayer(layer);
	const tex = textures?.[tid];
	return { layer, textureId: tid, replaceableId: tex?.ReplaceableId || 0 };
}

/**
 * WC3 常见：Layer0=ReplaceableId1（队色）+ Layer1=漫反射 Blend。
 * 队色从透明处透出；convert 取漫反射层时仍须标 rep1，供 Godot 垫底混合。
 */
function materialHasTeamColorUnderlay(matDef, textures) {
	const layers = matDef?.Layers ?? [];
	let hasRep1 = false;
	let hasImage = false;
	for (const layer of layers) {
		const tex = textures?.[textureIdOfLayer(layer)];
		if (!tex) continue;
		const rid = tex.ReplaceableId || 0;
		if (rid === 1 && !tex.Image) hasRep1 = true;
		if (tex.Image) hasImage = true;
	}
	return hasRep1 && hasImage;
}

/**
 * 材质是否「仅」某 ReplaceableId（所有层都无 Image，且 RepId 一致）。
 * RepId=2 → Team Glow（英雄光环/武器光晕面片）；Stand 下 WE 通常不可见。
 */
function materialExclusiveReplaceableId(matDef, textures) {
	const layers = matDef?.Layers ?? [];
	if (layers.length === 0) return 0;
	let only = 0;
	for (const layer of layers) {
		const tex = textures?.[textureIdOfLayer(layer)];
		if (!tex) return 0;
		if (tex.Image) return 0;
		const rid = tex.ReplaceableId || 0;
		if (!rid) return 0;
		if (only === 0) only = rid;
		else if (only !== rid) return 0;
	}
	return only;
}

function alphaModeForFilter(filterMode) {
  // WC3: 0 None, 1 Transparent, 2 Blend, 3 Additive, 4 AddAlpha, 5 Modulate, 6 Modulate2x
  // Godot 里 BLEND 会进透明队列导致建筑透视；仍导出 BLEND，由 MapModelCache 改 DEPTH_PRE_PASS。
  // Additive 无 glTF 对应：BLEND + 材质名 _fm3/_fm4，Godot 再改 ADD。
  if (filterMode === 0) return "OPAQUE";
  if (filterMode === 1) return "MASK";
  return "BLEND";
}

function alphaCutoffForFilter(filterMode) {
  // Match war3-model discard threshold for Transparent layers (~0.75).
  return filterMode === 1 ? 0.75 : 0.5;
}

/** @param {number} filterMode */
function isAdditiveFilter(filterMode) {
  return filterMode === 3 || filterMode === 4;
}

/** MDX Layer.Shading bit 4 (16) = TwoSided；勿默认双面，否则屋顶背面透出来发黑。 */
function isTwoSidedLayer(layer) {
  const shading = Number(layer?.Shading ?? layer?.Flags ?? 0) || 0;
  return (shading & 16) !== 0;
}

function transformMat4Wc3ToGltf(m) {
  // Apply basis change B * M * B^-1 for column-major M, B:(x,y,z)->(x,z,-y)
  // Faster: transform translation and rebuild from decomposed TRS.
  const { t, r, s } = mat4DecomposeTRS(m);
  const tg = wc3ToGltfVec3(t[0], t[1], t[2]);
  const rg = wc3ToGltfQuat(r[0], r[1], r[2], r[3]);
  // Scale axes permute with basis: (sx,sy,sz)_wc3 -> (sx,sz,sy)
  const sg = [s[0], s[2], s[1]];
  return { t: tg, r: rg, s: sg };
}

/**
 * @param {string} absPath
 * @param {string} logicalPath
 * @param {string} inDir
 * @param {string} outDir
 */
export async function convertOneMdx(absPath, logicalPath, inDir, outDir) {
  const model = parseModel(fs.readFileSync(absPath), logicalPath);
  const document = new Document();
  const buffer = document.createBuffer();

  const rootName = path.basename(logicalPath, path.extname(logicalPath));
  const root = document.createNode(rootName).setScale([MODEL_SCALE, MODEL_SCALE, MODEL_SCALE]);
  const scene = document.createScene(logicalPath).addChild(root);

  /** @type {Map<number, import('@gltf-transform/core').Texture>} */
  const textureCache = new Map();
  /** @type {Map<number, import('@gltf-transform/core').Material>} */
  const materialCache = new Map();

  // 方案 B：.gltf + 外部 URI 指向 assets/asset-converted/Textures|… 下唯一 PNG。
  // 不再 setImage embed（GLB 规范强制内嵌，无法跨模型共享）。
  const gltfLogical = mdxLogicalToGltf(logicalPath);

  function getTexture(textureId) {
    if (textureCache.has(textureId)) return textureCache.get(textureId);
    const texInfo = model.Textures?.[textureId];
    const resolved = resolveTexturePng(texInfo?.Image ?? "", inDir, outDir, {
      isReplaceable: Boolean(texInfo?.ReplaceableId),
      replaceableId: texInfo?.ReplaceableId || 0,
    });
    const uri = uriFromModelToPng(gltfLogical, resolved.pngLogical);
    // 必须同时 setImage + setURI：仅 URI 会被 writer 丢弃；
    // 有二者时 .gltf writer 把图写到 uri 路径（canonical 已在 Textures/ 则覆盖同文件）。
    const texture = document
      .createTexture(resolved.pngLogical)
      .setMimeType("image/png")
      .setImage(resolved.pngBytes)
      .setURI(uri);
    textureCache.set(textureId, texture);
    return texture;
  }

	function getMaterial(materialId) {
		if (materialCache.has(materialId)) return materialCache.get(materialId);
		const matDef = model.Materials?.[materialId];
		const picked = pickDiffuseLayer(matDef, model.Textures);
		let filterMode = picked.layer?.FilterMode ?? 0;
		const teamUnderlay = materialHasTeamColorUnderlay(matDef, model.Textures);
		// 双层队色垫底：漫反射层本身 Rep=0，仍标 rep1 供运行时混合
		let replaceableId = picked.replaceableId || 0;
		if (teamUnderlay) {
			replaceableId = 1;
		}
		// Team Glow 在 MDX 里几乎总是 Additive；若数据异常也强制按光晕处理
		if (replaceableId === 2 && !isAdditiveFilter(filterMode)) {
			filterMode = 3;
		}
		// 名称带 _fmN / _repN，供 Godot 识别 Additive 与队伍色/光晕
		const material = document
			.createMaterial(`Material_${materialId}_fm${filterMode}_rep${replaceableId}`)
			.setDoubleSided(isTwoSidedLayer(picked.layer))
			.setAlphaMode(alphaModeForFilter(filterMode))
			.setAlphaCutoff(alphaCutoffForFilter(filterMode))
			.setMetallicFactor(0)
			.setRoughnessFactor(1);
		material.setExtras({
			wc3FilterMode: filterMode,
			wc3Additive: isAdditiveFilter(filterMode),
			wc3ReplaceableId: replaceableId,
			wc3TeamGlow: replaceableId === 2,
			wc3TeamColorUnderlay: teamUnderlay,
			wc3TwoSided: isTwoSidedLayer(picked.layer),
		});
		material.setBaseColorTexture(getTexture(picked.textureId));
		if (isAdditiveFilter(filterMode)) {
			// 略提亮，逼近 WC3 Additive 光晕
			material.setEmissiveFactor([0.15, 0.15, 0.1]);
		}
		materialCache.set(materialId, material);
		return material;
	}

  // --- Skeleton (flat under Armature; IBM = I to match WC3 model-space skinning) ---
  const boneNodes = model.Bones ?? [];
  const allNodes = model.Nodes ?? [];
  const armature = document.createNode("Armature");
  root.addChild(armature);

  /** @type {Map<number, import('@gltf-transform/core').Node>} */
  const jointByObjectId = new Map();
  /** @type {import('@gltf-transform/core').Node[]} */
  const jointList = [];

  for (const bone of boneNodes) {
    const joint = document.createNode(bone.Name || `Bone_${bone.ObjectId}`);
    jointByObjectId.set(bone.ObjectId, joint);
    jointList.push(joint);
    armature.addChild(joint);
  }

  const skin =
    jointList.length > 0
      ? document.createSkin("Skin").setSkeleton(armature)
      : null;

  if (skin) {
    const ibmData = new Float32Array(jointList.length * 16);
    for (let i = 0; i < jointList.length; i += 1) {
      ibmData.set(mat4Identity(), i * 16);
      skin.addJoint(jointList[i]);
    }
    skin.setInverseBindMatrices(
      document
        .createAccessor("IBM")
        .setType("MAT4")
        .setArray(ibmData)
        .setBuffer(buffer),
    );
  }

  const objectIdToJointIndex = new Map();
  boneNodes.forEach((b, i) => objectIdToJointIndex.set(b.ObjectId, i));

  // --- Geosets ---
  // Godot GLTFDocument drops TRS on skinned mesh nodes; visibility for Godot is
  // written to *.geosetvis.json and injected as :visible during load/bake.
  // GLB still carries Geoset_* scale channels for non-Godot glTF consumers.
  const geosets = model.Geosets ?? [];
  /** @type {Map<number, import('@gltf-transform/core').Node>} */
  const geosetMeshNodes = new Map();
  const restSeq = model.Sequences?.[0];
  const restStart = restSeq?.Interval?.[0] ?? 0;
  const restEnd = restSeq?.Interval?.[1] ?? restStart;
  const restFrame = restStart;

	for (let gi = 0; gi < geosets.length; gi += 1) {
		const g = geosets[gi];
		const vertCount = (g.Vertices?.length ?? 0) / 3;
		if (!vertCount || !g.Faces?.length) continue;

		// 纯 Team Glow geoset（英雄光环/武器光晕大面片）：Stand 下 WE 不可见，
		// 导出成实心色块会污染编辑器预览 → 跳过。
		const matId = g.MaterialID ?? 0;
		const exclusiveRep = materialExclusiveReplaceableId(
			model.Materials?.[matId],
			model.Textures,
		);
		if (exclusiveRep === 2) {
			continue;
		}

		const positions = new Float32Array(vertCount * 3);
    const normals = new Float32Array(vertCount * 3);
    const uvs = new Float32Array(vertCount * 2);
    const joints = new Uint16Array(vertCount * 4);
    const weights = new Float32Array(vertCount * 4);

    for (let i = 0; i < vertCount; i += 1) {
      const x = g.Vertices[i * 3];
      const y = g.Vertices[i * 3 + 1];
      const z = g.Vertices[i * 3 + 2];
      const p = wc3ToGltfVec3(x, y, z);
      positions[i * 3] = p[0];
      positions[i * 3 + 1] = p[1];
      positions[i * 3 + 2] = p[2];

      if (g.Normals?.length >= (i + 1) * 3) {
        const n = wc3ToGltfVec3(g.Normals[i * 3], g.Normals[i * 3 + 1], g.Normals[i * 3 + 2]);
        normals[i * 3] = n[0];
        normals[i * 3 + 1] = n[1];
        normals[i * 3 + 2] = n[2];
      } else {
        normals[i * 3 + 1] = 1;
      }

      const tv = g.TVertices?.[0];
      if (tv && tv.length >= (i + 1) * 2) {
        // Do NOT flip V — war3-model uploads raw TVertices to WebGL/glTF-like V=0 bottom space.
        uvs[i * 2] = tv[i * 2];
        uvs[i * 2 + 1] = tv[i * 2 + 1];
      }

      // Skin weights from matrix groups (equal weight, up to 4).
      const group = g.Groups?.[g.VertexGroup?.[i] ?? 0] ?? [];
      const usable = group
        .map((objectId) => objectIdToJointIndex.get(objectId))
        .filter((idx) => idx !== undefined);
      const count = Math.min(4, usable.length || 0);
      const w = count > 0 ? 1 / count : 1;
      for (let k = 0; k < 4; k += 1) {
        joints[i * 4 + k] = count > 0 && k < count ? usable[k] : 0;
        weights[i * 4 + k] = count > 0 && k < count ? w : k === 0 ? 1 : 0;
      }
    }

    // Keep original winding — with (x,z,-y) this matches WC3 front faces in practice for most units.
    const indices = Uint32Array.from(g.Faces);

    const prim = document
      .createPrimitive()
      .setAttribute(
        "POSITION",
        document.createAccessor().setType("VEC3").setArray(positions).setBuffer(buffer),
      )
      .setAttribute(
        "NORMAL",
        document.createAccessor().setType("VEC3").setArray(normals).setBuffer(buffer),
      )
      .setAttribute(
        "TEXCOORD_0",
        document.createAccessor().setType("VEC2").setArray(uvs).setBuffer(buffer),
      )
      .setIndices(
        document.createAccessor().setType("SCALAR").setArray(indices).setBuffer(buffer),
      )
      .setMaterial(getMaterial(g.MaterialID ?? 0));

    if (skin && jointList.length > 0) {
      prim
        .setAttribute(
          "JOINTS_0",
          document.createAccessor().setType("VEC4").setArray(joints).setBuffer(buffer),
        )
        .setAttribute(
          "WEIGHTS_0",
          document.createAccessor().setType("VEC4").setArray(weights).setBuffer(buffer),
        );
    }

    const mesh = document.createMesh(`Geoset_${gi}`).addPrimitive(prim);
    const meshNode = document.createNode(`Geoset_${gi}`).setMesh(mesh);
    if (skin) meshNode.setSkin(skin);

    // Hide geosets that WC3 keeps invisible at rest (sequence-scoped).
    const restAlpha = sampleGeosetAlphaInSequence(
      model.GeosetAnims,
      gi,
      restFrame,
      restStart,
      restEnd,
    );
    if (restAlpha < 0.5) {
      meshNode.setScale([0, 0, 0]);
    }
    geosetMeshNodes.set(gi, meshNode);
    root.addChild(meshNode);
  }

  // --- Animations (one glTF animation per WC3 Sequence) ---
  if (model.Sequences?.length) {
    for (const seq of model.Sequences) {
      const start = seq.Interval[0];
      const end = seq.Interval[1];
      if (end <= start) continue;

      const animName = (seq.Name || "Anim").replace(/\s+/g, "_");
      const animation = document.createAnimation(animName);
      const frames = collectSampleFrames(
        allNodes,
        start,
        end,
        33,
        model.GeosetAnims || [],
      );

      /** @type {Map<number, { times: number[], t: number[], r: number[], s: number[] }>} */
      const tracks = new Map();
      for (const bone of boneNodes) {
        tracks.set(bone.ObjectId, { times: [], t: [], r: [], s: [] });
      }

      /** @type {Map<number, { times: number[], s: number[] }>} */
      const geosetScaleTracks = new Map();
      for (const gi of geosetMeshNodes.keys()) {
        geosetScaleTracks.set(gi, { times: [], s: [] });
      }

      for (const frame of frames) {
        const worlds = evaluateNodeWorldMatrices(allNodes, frame);
        const timeSec = (frame - start) / 1000;
        for (const bone of boneNodes) {
          const world = worlds[bone.ObjectId] || mat4Identity();
          const { t, r, s } = transformMat4Wc3ToGltf(world);
          const track = tracks.get(bone.ObjectId);
          track.times.push(timeSec);
          track.t.push(t[0], t[1], t[2]);
          track.r.push(r[0], r[1], r[2], r[3]);
          track.s.push(s[0], s[1], s[2]);
        }

        for (const gi of geosetMeshNodes.keys()) {
          const alpha = sampleGeosetAlphaInSequence(
            model.GeosetAnims,
            gi,
            frame,
            start,
            end,
          );
          const visible = alpha >= 0.5 ? 1 : 0;
          const gTrack = geosetScaleTracks.get(gi);
          gTrack.times.push(timeSec);
          gTrack.s.push(visible, visible, visible);
        }
      }

      for (const bone of boneNodes) {
        const joint = jointByObjectId.get(bone.ObjectId);
        const track = tracks.get(bone.ObjectId);
        if (!joint || !track?.times.length) continue;

        const input = document
          .createAccessor(`${animName}_${bone.ObjectId}_time`)
          .setType("SCALAR")
          .setArray(new Float32Array(track.times))
          .setBuffer(buffer);

        const tOut = document
          .createAccessor(`${animName}_${bone.ObjectId}_t`)
          .setType("VEC3")
          .setArray(new Float32Array(track.t))
          .setBuffer(buffer);
        const rOut = document
          .createAccessor(`${animName}_${bone.ObjectId}_r`)
          .setType("VEC4")
          .setArray(new Float32Array(track.r))
          .setBuffer(buffer);
        const sOut = document
          .createAccessor(`${animName}_${bone.ObjectId}_s`)
          .setType("VEC3")
          .setArray(new Float32Array(track.s))
          .setBuffer(buffer);

        // glTF-Transform requires samplers to be attached to the Animation
        // via addSampler(); otherwise channels are written without sampler
        // indices and Godot rejects the GLB.
        const tSampler = document
          .createAnimationSampler()
          .setInterpolation("LINEAR")
          .setInput(input)
          .setOutput(tOut);
        const rSampler = document
          .createAnimationSampler()
          .setInterpolation("LINEAR")
          .setInput(input)
          .setOutput(rOut);
        const sSampler = document
          .createAnimationSampler()
          .setInterpolation("LINEAR")
          .setInput(input)
          .setOutput(sOut);

        animation.addSampler(tSampler).addSampler(rSampler).addSampler(sSampler);
        animation
          .addChannel(
            document
              .createAnimationChannel()
              .setTargetNode(joint)
              .setTargetPath("translation")
              .setSampler(tSampler),
          )
          .addChannel(
            document
              .createAnimationChannel()
              .setTargetNode(joint)
              .setTargetPath("rotation")
              .setSampler(rSampler),
          )
          .addChannel(
            document
              .createAnimationChannel()
              .setTargetNode(joint)
              .setTargetPath("scale")
              .setSampler(sSampler),
          );
      }

      // Drive geoset visibility (WC3 GeosetAnim alpha) via node scale.
      // Godot drops these on skinned meshes — see writeGeosetVisSidecar.
      for (const [gi, meshNode] of geosetMeshNodes) {
        const gTrack = geosetScaleTracks.get(gi);
        if (!gTrack?.times.length) continue;
        const input = document
          .createAccessor(`${animName}_geoset${gi}_time`)
          .setType("SCALAR")
          .setArray(new Float32Array(gTrack.times))
          .setBuffer(buffer);
        const sOut = document
          .createAccessor(`${animName}_geoset${gi}_s`)
          .setType("VEC3")
          .setArray(new Float32Array(gTrack.s))
          .setBuffer(buffer);
        const sSampler = document
          .createAnimationSampler()
          .setInterpolation("STEP")
          .setInput(input)
          .setOutput(sOut);
        animation.addSampler(sSampler);
        animation.addChannel(
          document
            .createAnimationChannel()
            .setTargetNode(meshNode)
            .setTargetPath("scale")
            .setSampler(sSampler),
        );
      }
    }
  }

  document.getRoot().setDefaultScene(scene);

  const dest = path.join(outDir, ...gltfLogical.split("/"));
  const destBin = dest.replace(/\.gltf$/i, ".bin");
  const pe2Dest = path.join(outDir, ...mdxLogicalToPe2(logicalPath).split("/"));
  const geosetVisDest = path.join(
    outDir,
    ...mdxLogicalToGeosetVis(logicalPath).split("/"),
  );
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  // 直接写最终路径（避免 .partial.bin 写进 buffers[].uri）。
  // sidecar 先写；gltf/bin 后写。中途失败清掉本模型产物。
  try {
    writePe2Sidecar(model, logicalPath, inDir, outDir);
    writeGeosetVisSidecar(model, logicalPath, outDir, geosetMeshNodes.keys());
    await new NodeIO().write(dest, document);
    unlinkQuiet(dest.replace(/\.gltf$/i, ".glb"));
  } catch (err) {
    unlinkQuiet(dest);
    unlinkQuiet(destBin);
    unlinkQuiet(pe2Dest);
    unlinkQuiet(geosetVisDest);
    throw err;
  }
  return dest;
}

export async function convertMdxBatch(options) {
  const { inDir, outDir, force, include, exclude } = options;
  const files = walkFiles(inDir, new Set([".mdx", ".mdl"]), include, exclude);

  let converted = 0;
  let skipped = 0;
  let errors = 0;

  console.log(`\n[models] 发现 ${files.length} 个 .mdx/.mdl`);

  for (const file of files) {
    const gltfLogical = mdxLogicalToGltf(file.logicalPath);
    const dest = path.join(outDir, ...gltfLogical.split("/"));
    const pe2Dest = path.join(outDir, ...mdxLogicalToPe2(file.logicalPath).split("/"));
    const geosetVisDest = path.join(
      outDir,
      ...mdxLogicalToGeosetVis(file.logicalPath).split("/"),
    );

    if (
      !force &&
      fs.existsSync(dest) &&
      fs.existsSync(pe2Dest) &&
      fs.existsSync(geosetVisDest)
    ) {
      const srcStat = fs.statSync(file.absPath);
      const dstStat = fs.statSync(dest);
      const pe2Stat = fs.statSync(pe2Dest);
      const visStat = fs.statSync(geosetVisDest);
      const valid = isValidGltfOnDisk(dest);
      if (
        dstStat.mtimeMs >= srcStat.mtimeMs &&
        dstStat.size > 0 &&
        valid &&
        pe2Stat.mtimeMs >= srcStat.mtimeMs &&
        visStat.mtimeMs >= srcStat.mtimeMs
      ) {
        skipped += 1;
        continue;
      }
      if (!valid && dstStat.size > 0) {
        unlinkQuiet(dest);
        unlinkQuiet(dest.replace(/\.gltf$/i, ".bin"));
      }
    }

    try {
      await convertOneMdx(file.absPath, file.logicalPath, inDir, outDir);
      converted += 1;
    } catch (err) {
      console.error(`  失败 ${file.logicalPath}: ${err.stack ?? err.message ?? err}`);
      errors += 1;
    }
  }

  console.log(`[models] 完成: 转换 ${converted}, 跳过 ${skipped}, 错误 ${errors}`);
  return { converted, skipped, errors, fileCount: files.length };
}
