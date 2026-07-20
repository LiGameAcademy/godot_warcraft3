import fs from "node:fs";
import path from "node:path";
import { Document, NodeIO } from "@gltf-transform/core";
import { parseMDL, parseMDX } from "war3-model";
import {
  collectSampleFrames,
  evaluateNodeWorldMatrices,
  sampleGeosetAlpha,
} from "./anim.js";
import { blpBufferToPng, writePlaceholderPng } from "./convert-blp.js";
import {
  mat4DecomposeTRS,
  mat4Identity,
  wc3ToGltfQuat,
  wc3ToGltfVec3,
} from "./mat4.js";
import { blpLogicalToPng, mdxLogicalToGlb, normalizeLogicalPath } from "./paths.js";
import { walkFiles } from "./walk.js";

const MODEL_SCALE = 0.01;

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
  1: null, // team color → placeholder
  2: null, // team glow → placeholder
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
    // Default human-ish team blue instead of magenta debug color.
    const pngLogical = "_placeholders/team_color.png";
    const dest = path.join(outDir, ...pngLogical.split("/"));
    if (!fs.existsSync(dest)) writePlaceholderPng(dest, [30, 70, 180, 255]);
    return { pngLogical, pngBytes: fs.readFileSync(dest), isReplaceable: true };
  }

  const pngLogical = blpLogicalToPng(raw);
  const pngDest = path.join(outDir, ...pngLogical.split("/"));
  if (fs.existsSync(pngDest)) {
    return { pngLogical, pngBytes: fs.readFileSync(pngDest), isReplaceable };
  }

  const blpSrc = findBlpOnDisk(raw, inDir);
  if (!blpSrc) {
    console.warn(`  缺少贴图: ${raw} → 占位`);
    const pngLogicalPh = "_placeholders/missing.png";
    const dest = path.join(outDir, ...pngLogicalPh.split("/"));
    if (!fs.existsSync(dest)) writePlaceholderPng(dest, [255, 0, 0, 255]);
    return { pngLogical: pngLogicalPh, pngBytes: fs.readFileSync(dest), isReplaceable };
  }

  const pngBytes = blpBufferToPng(fs.readFileSync(blpSrc));
  fs.mkdirSync(path.dirname(pngDest), { recursive: true });
  fs.writeFileSync(pngDest, pngBytes);
  return { pngLogical, pngBytes, isReplaceable };
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

function alphaModeForFilter(filterMode) {
  // 0 None/Opaque, 1 Transparent (alpha test), 2+ blend/additive ≈ BLEND
  if (filterMode === 0) return "OPAQUE";
  if (filterMode === 1) return "MASK";
  return "BLEND";
}

function alphaCutoffForFilter(filterMode) {
  // Match war3-model discard threshold for Transparent layers (~0.75).
  return filterMode === 1 ? 0.75 : 0.5;
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

  function getTexture(textureId) {
    if (textureCache.has(textureId)) return textureCache.get(textureId);
    const texInfo = model.Textures?.[textureId];
    const resolved = resolveTexturePng(texInfo?.Image ?? "", inDir, outDir, {
      isReplaceable: Boolean(texInfo?.ReplaceableId),
      replaceableId: texInfo?.ReplaceableId || 0,
    });
    const texture = document
      .createTexture(resolved.pngLogical)
      .setMimeType("image/png")
      .setImage(resolved.pngBytes);
    textureCache.set(textureId, texture);
    return texture;
  }

  function getMaterial(materialId) {
    if (materialCache.has(materialId)) return materialCache.get(materialId);
    const matDef = model.Materials?.[materialId];
    const picked = pickDiffuseLayer(matDef, model.Textures);
    const filterMode = picked.layer?.FilterMode ?? 0;
    const material = document
      .createMaterial(`Material_${materialId}`)
      .setDoubleSided(true)
      .setAlphaMode(alphaModeForFilter(filterMode))
      .setAlphaCutoff(alphaCutoffForFilter(filterMode))
      .setMetallicFactor(0)
      .setRoughnessFactor(1);
    material.setBaseColorTexture(getTexture(picked.textureId));
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
  const geosets = model.Geosets ?? [];
  /** @type {Map<number, import('@gltf-transform/core').Node>} */
  const geosetMeshNodes = new Map();
  const restFrame = model.Sequences?.[0]?.Interval?.[0] ?? 0;

  for (let gi = 0; gi < geosets.length; gi += 1) {
    const g = geosets[gi];
    const vertCount = (g.Vertices?.length ?? 0) / 3;
    if (!vertCount || !g.Faces?.length) continue;

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

    // Hide geosets that WC3 keeps invisible at rest (death guts, temporary props).
    const restAlpha = sampleGeosetAlpha(model.GeosetAnims, gi, restFrame);
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
          const alpha = sampleGeosetAlpha(model.GeosetAnims, gi, frame);
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

  const glbLogical = mdxLogicalToGlb(logicalPath);
  const dest = path.join(outDir, ...glbLogical.split("/"));
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  await new NodeIO().write(dest, document);
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
    const glbLogical = mdxLogicalToGlb(file.logicalPath);
    const dest = path.join(outDir, ...glbLogical.split("/"));

    if (!force && fs.existsSync(dest)) {
      const srcStat = fs.statSync(file.absPath);
      const dstStat = fs.statSync(dest);
      if (dstStat.mtimeMs >= srcStat.mtimeMs && dstStat.size > 0) {
        skipped += 1;
        continue;
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
