import path from "node:path";
import { minimatch } from "minimatch";

export function normalizeLogicalPath(p) {
  return String(p)
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .trim();
}

export function resolveFromPackage(p, packageRoot) {
  return path.isAbsolute(p) ? path.normalize(p) : path.resolve(packageRoot, p);
}

/**
 * @param {string} logicalPath
 * @param {string[]} include
 * @param {string[]} exclude
 */
export function matchesFilters(logicalPath, include, exclude) {
  const opts = { nocase: true, dot: true };
  if (include.length > 0 && !include.some((g) => minimatch(logicalPath, g, opts))) {
    return false;
  }
  if (exclude.some((g) => minimatch(logicalPath, g, opts))) {
    return false;
  }
  return true;
}

/** Map WC3 texture path to converted PNG logical path. */
export function blpLogicalToPng(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  if (n.toLowerCase().endsWith(".blp")) {
    return `${n.slice(0, -4)}.png`;
  }
  return `${n}.png`;
}

/**
 * Map WC3 model path to converted glTF logical path（JSON + 外部 URI 贴图）。
 * 方案 B：不再写二进制 .glb（embed 贴图无法跨模型共享）。
 */
export function mdxLogicalToGltf(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  if (n.toLowerCase().endsWith(".mdx") || n.toLowerCase().endsWith(".mdl")) {
    return `${n.slice(0, -4)}.gltf`;
  }
  return `${n}.gltf`;
}

/** @deprecated 兼容旧调用名；现返回 .gltf */
export function mdxLogicalToGlb(logicalPath) {
  return mdxLogicalToGltf(logicalPath);
}

/** Map WC3 model path to ParticleEmitter2 sidecar JSON (next to .gltf). */
export function mdxLogicalToPe2(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.pe2.json`;
  }
  return `${gltf}.pe2.json`;
}

/** Map WC3 model path to Geoset visibility sidecar. */
export function mdxLogicalToGeosetVis(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.geosetvis.json`;
  }
  return `${gltf}.geosetvis.json`;
}

/** Map WC3 model path to attachments sidecar (C-1: 小件 / 特效烘焙元数据). */
export function mdxLogicalToAttachments(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.attachments.json`;
  }
  return `${gltf}.attachments.json`;
}

/** Godot GLTFDocument 解析 skinned mesh 时丢弃 joint node 的 TRS（视为 identity rest），
 * 这导致 WC3 多层骨骼（马 + 人 + 手臂 + 杖）的父子偏移全为 0，BA / PE2 漂在原点。
 * 把每个 joint 的 global_rest 写进 sidecar，bake 后用 set_bone_rest() 还原。 */
export function mdxLogicalToBoneRest(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.bone_rest.json`;
  }
  return `${gltf}.bone_rest.json`;
}

/** Map WC3 model path to cameras sidecar（MDX Cameras → Godot 机位）. */
export function mdxLogicalToCameras(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.cameras.json`;
  }
  return `${gltf}.cameras.json`;
}

/** Map WC3 model path to raw animation keyframe sidecar（MDX Keys，毫秒时间轴）. */
export function mdxLogicalToAnimKeys(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.animkeys.json`;
  }
  return `${gltf}.animkeys.json`;
}

/** Map WC3 model path to CollisionShapes sidecar. */
export function mdxLogicalToCollision(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.collision.json`;
  }
  return `${gltf}.collision.json`;
}

/**
 * 从模型逻辑路径到贴图逻辑路径的相对 URI（posix，供 glTF images[].uri）。
 * WC3 路径大小写混乱：公共前缀按不敏感匹配，下行段保留 pngLogical 原大小写。
 */
export function uriFromModelToPng(modelLogical, pngLogical) {
  const model = normalizeLogicalPath(modelLogical);
  const to = normalizeLogicalPath(pngLogical);
  const fromParts = path.posix.dirname(model).split("/").filter(Boolean);
  const toParts = path.posix.dirname(to).split("/").filter(Boolean);
  const base = path.posix.basename(to);

  let i = 0;
  while (
    i < fromParts.length &&
    i < toParts.length &&
    fromParts[i].toLowerCase() === toParts[i].toLowerCase()
  ) {
    i += 1;
  }
  const ups = fromParts.length - i;
  const down = toParts.slice(i);
  const segs = [...Array.from({ length: ups }, () => ".."), ...down, base];
  let rel = segs.join("/");
  if (!rel.startsWith(".")) {
    rel = `./${rel}`;
  }
  return rel;
}
