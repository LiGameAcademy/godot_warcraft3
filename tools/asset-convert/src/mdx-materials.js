import fs from "node:fs";
import path from "node:path";
import { blpBufferToPng, writePlaceholderPng } from "./convert-blp.js";
import { blpLogicalToPng, normalizeLogicalPath } from "./paths.js";
import { getLog } from "../../pipeline-log.mjs";



export const REPLACEABLE_DEFAULTS = {
	// 默认队伍色：导出时直接嵌 TeamColor00（红/玩家1）；运行时仍可按 owner 重染
	1: "ReplaceableTextures/TeamColor/TeamColor00.blp",
	// 英雄脚底/武器光晕：软圆 TeamGlow；运行时按队伍色乘 albedo
	2: "ReplaceableTextures/TeamGlow/TeamGlow00.blp",
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

export const REPLACEABLE_PLACEHOLDERS = {
	// 对齐 TeamColor00 红，避免再出现整片占位蓝
	1: { pngLogical: "_placeholders/team_color.png", rgba: [220, 40, 40, 255] },
	// 半透明白：加法混合时才像光晕；误当成不透明时也不至于整块实心蓝
	2: { pngLogical: "_placeholders/team_glow.png", rgba: [255, 255, 255, 96] },
};

/**
 * @param {string} logical
 * @param {string} inDir
 */
export function findBlpOnDisk(logical, inDir) {
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

export function resolveTexturePng(
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
		getLog().warnOnce(
			`miss-tex:${raw}`,
			`缺少贴图: ${raw} → 占位`,
			`BLP not found under extract root; using _placeholders/missing.png`,
		);
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

export function textureIdOfLayer(layer) {
	const tid = layer?.TextureID;
	return typeof tid === "number" ? tid : 0;
}

/**
 * Pick the best diffuse layer: prefer a layer with a real Image path.
 * Fixes team-color-first materials (Layer0=Replaceable, Layer1=Footman.blp).
 */
export function pickDiffuseLayer(matDef, textures) {
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
export function materialHasTeamColorUnderlay(matDef, textures) {
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

export function alphaModeForFilter(filterMode) {
  // WC3: 0 None, 1 Transparent, 2 Blend, 3 Additive, 4 AddAlpha, 5 Modulate, 6 Modulate2x
  // Godot 里 BLEND 会进透明队列导致建筑透视；仍导出 BLEND，由 MapModelCache 改 DEPTH_PRE_PASS。
  // Additive 无 glTF 对应：BLEND + 材质名 _fm3/_fm4，Godot 再改 ADD。
  if (filterMode === 0) return "OPAQUE";
  if (filterMode === 1) return "MASK";
  return "BLEND";
}

export function alphaCutoffForFilter(filterMode) {
  // Match war3-model discard threshold for Transparent layers (~0.75).
  return filterMode === 1 ? 0.75 : 0.5;
}

/** @param {number} filterMode */
export function isAdditiveFilter(filterMode) {
  return filterMode === 3 || filterMode === 4;
}

/** MDX Layer.Shading bit 4 (16) = TwoSided；勿默认双面，否则屋顶背面透出来发黑。
 *  FilterMode Transparent(1) 例外：袍/披风多为单面壳，强制双面（否则 Godot cull_back 前胸镂空）。 */
export function isTwoSidedLayer(layer) {
  const filterMode = Number(layer?.FilterMode) || 0;
  if (filterMode === 1) return true;
  const shading = Number(layer?.Shading ?? layer?.Flags ?? 0) || 0;
  return (shading & 16) !== 0;
}
