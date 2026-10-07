import fs from "node:fs";
import path from "node:path";
import { Document, NodeIO } from "@gltf-transform/core";
import { sampleGeosetAlphaInSequence } from "./anim.js";
import { mat4Identity, wc3ToGltfVec3 } from "./mat4.js";
import { mdxLogicalToAnimKeys, mdxLogicalToAttachments, mdxLogicalToBoneRest, mdxLogicalToCameras, mdxLogicalToCollision, mdxLogicalToModelIr, mdxLogicalToGeosetVis, mdxLogicalToGltf, mdxLogicalToPe2, uriFromModelToPng } from "./paths.js";

import { MODEL_SCALE } from "./mdx-values.js";
import { writePe2Sidecar, bakePivotDeltaGltf } from "./mdx-particles.js";
import { writeRibbonSidecar, writeCamerasSidecar, writeCollisionSidecar } from "./mdx-effects-sidecars.js";
import { writeGeosetVisSidecar, writeAnimKeysSidecar } from "./mdx-animation-sidecars.js";
import { writeAttachmentsSidecar } from "./mdx-attachments.js";
import { writeBoneRestSidecar, extraHelperNodes, uniqueJointName, parseModel } from "./mdx-skeleton.js";
import { resolveTexturePng, pickDiffuseLayer, materialHasTeamColorUnderlay, alphaModeForFilter, alphaCutoffForFilter, isAdditiveFilter, isTwoSidedLayer } from "./mdx-materials.js";
import { writeModelIrSidecar } from "./mdx-ir.js";
import { compileAnimations } from "./mdx-gltf-animation.js";
import { unlinkQuiet } from "./convert-mdx.js";

/**
 * @param {string} absPath
 * @param {string} logicalPath
 * @param {string} inDir
 * @param {string} outDir
 */
export async function convertOneMdx(absPath, logicalPath, inDir, outDir, sourceMetadata = {}) {
  const sourceBytes = fs.readFileSync(absPath);
  const model = parseModel(sourceBytes, logicalPath);
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
  // Bones 必须先入 joint 列表，保持已有 JOINTS_0 下标 0..Bones-1；Helpers 去重后追加。
  const boneNodes = model.Bones ?? [];
  const allNodes = model.Nodes ?? [];
  const helperJoints = extraHelperNodes(model, boneNodes);
  const skinAnimNodes = [...boneNodes, ...helperJoints];
  const armature = document.createNode("Armature");
  root.addChild(armature);

  /** @type {Map<number, import('@gltf-transform/core').Node>} */
  const jointByObjectId = new Map();
  /** @type {import('@gltf-transform/core').Node[]} */
  const jointList = [];
  const usedJointNames = new Set();

  // WC3 PivotPoint 是「旋转原点」。每个 joint 在父坐标系里的偏移 = 父 Pivot − 子 Pivot。
  // glTF joint node.translation 在 skin 场景下不被保留（IBM 才携带 chain 信息），
  // 我们把 chain 累计的 translation 写进 IBM：vertex_final = vertex_model × jointTRS × IBM，
  // IBM = inv(globalJointT) ⇒ vertex_final = vertex_model × jointTRS / globalJointT，
  // 即 jointTRS 应用到 joint-local vertex。
  const nodeByObjectId = (id) => {
    if (id == null) return null;
    for (const n of allNodes ?? []) {
      if (n && n.ObjectId === id) return n;
    }
    return null;
  };
  const jointLocalT = new Map(); // ObjectId → gltf vec3（与顶点同空间，不含根 scale）
  const jointParent = new Map(); // ObjectId → parent ObjectId
  const DBG_JOINT = globalThis.__WC3_DEBUG_JOINT === true;
  for (const src of skinAnimNodes) {
    const parentId = src.Parent;
    jointParent.set(src.ObjectId, parentId);
    const gp = parentId != null ? nodeByObjectId(parentId) : null;
    const t = bakePivotDeltaGltf(src.PivotPoint, gp?.PivotPoint ?? [0, 0, 0]);
    jointLocalT.set(src.ObjectId, t);
  }
  if (DBG_JOINT) {
    for (const src of skinAnimNodes.slice(0, 5)) {
      const t = jointLocalT.get(src.ObjectId);
      console.log("[joint]", src.Name || src.ObjectId, "t=", t);
    }
    console.log("[joint] total skinAnimNodes=", skinAnimNodes.length, "jointLocalT size=", jointLocalT.size);
  }

  for (const src of skinAnimNodes) {
    const joint = document.createNode(uniqueJointName(src, usedJointNames));
    // 不要 setTranslation：Godot 若把它收成 bone rest，而顶点已是 model space、IBM=I，
    // 蒙皮会再加一遍局部平移，骑士叠进马身。joint 保持原点，绑定网格即 MDX 外形。
    jointByObjectId.set(src.ObjectId, joint);
    jointList.push(joint);
    armature.addChild(joint);
  }

  const skin =
    jointList.length > 0
      ? document.createSkin("Skin").setSkeleton(armature)
      : null;

  /** @type {Map<number, Float32Array>} */
  const globalJointT = new Map();
  /** @param {number} oid @returns {Float32Array} */
  const computeGlobal = (oid) => {
    const cached = globalJointT.get(oid);
    if (cached) return cached;
    const t = jointLocalT.get(oid) ?? [0, 0, 0];
    const pid = jointParent.get(oid);
    const parGlobal = pid != null ? computeGlobal(pid) : null;
    const out = new Float32Array(16);
    if (parGlobal) {
      out.set(parGlobal);
      out[12] = parGlobal[0] * t[0] + parGlobal[4] * t[1] + parGlobal[8] * t[2] + parGlobal[12];
      out[13] = parGlobal[1] * t[0] + parGlobal[5] * t[1] + parGlobal[9] * t[2] + parGlobal[13];
      out[14] = parGlobal[2] * t[0] + parGlobal[6] * t[1] + parGlobal[10] * t[2] + parGlobal[14];
    } else {
      out[0] = 1; out[5] = 1; out[10] = 1; out[15] = 1;
      out[12] = t[0]; out[13] = t[1]; out[14] = t[2];
    }
    globalJointT.set(oid, out);
    return out;
  };
  for (const src of skinAnimNodes) computeGlobal(src.ObjectId);

  if (skin) {
    // Godot 导入 skinned mesh 时 joint rest=I。IBM 必须是单位阵，否则
    // pose=I、IBM=inv(bind) 会把绑定姿态顶点减回原点（网格堆成一团）。
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
  skinAnimNodes.forEach((b, i) => objectIdToJointIndex.set(b.ObjectId, i));

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
      // 顶点保持 model space。Godot rest=I + IBM=I 时视觉即绑定姿态。
      positions[i * 3] = p[0];
      positions[i * 3 + 1] = p[1];
      positions[i * 3 + 2] = p[2];
      const group = g.Groups?.[g.VertexGroup?.[i] ?? 0] ?? [];

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

  const bindWorlds = compileAnimations(model, document, buffer, restSeq, restStart, restEnd, allNodes, jointList, skinAnimNodes, jointByObjectId, geosetMeshNodes);

  document.getRoot().setDefaultScene(scene);

  const dest = path.join(outDir, ...gltfLogical.split("/"));
  const destBin = dest.replace(/\.gltf$/i, ".bin");
  const pe2Dest = path.join(outDir, ...mdxLogicalToPe2(logicalPath).split("/"));
  const geosetVisDest = path.join(
    outDir,
    ...mdxLogicalToGeosetVis(logicalPath).split("/"),
  );
  const attDest = path.join(
    outDir,
    ...mdxLogicalToAttachments(logicalPath).split("/"),
  );
  const camDest = path.join(
    outDir,
    ...mdxLogicalToCameras(logicalPath).split("/"),
  );
  const animKeysDest = path.join(
    outDir,
    ...mdxLogicalToAnimKeys(logicalPath).split("/"),
  );
  const collisionDest = path.join(
    outDir,
    ...mdxLogicalToCollision(logicalPath).split("/"),
  );
  const boneRestDest = path.join(
    outDir,
    ...mdxLogicalToBoneRest(logicalPath).split("/"),
  );
  const irDest = path.join(outDir, ...mdxLogicalToModelIr(logicalPath).split("/"));
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  // 直接写最终路径（避免 .partial.bin 写进 buffers[].uri）。
  // sidecar 先写；gltf/bin 后写。中途失败清掉本模型产物。
  try {
    writePe2Sidecar(model, logicalPath, inDir, outDir);
    writeRibbonSidecar(model, logicalPath, inDir, outDir);
    writeGeosetVisSidecar(model, logicalPath, outDir, geosetMeshNodes.keys());
    writeAttachmentsSidecar(model, logicalPath, outDir);
    writeCamerasSidecar(model, logicalPath, outDir);
    writeAnimKeysSidecar(model, logicalPath, outDir);
    writeCollisionSidecar(model, logicalPath, outDir);
    writeBoneRestSidecar(skinAnimNodes, bindWorlds, jointList, logicalPath, outDir);
    writeModelIrSidecar(model, logicalPath, sourceBytes, outDir, inDir, sourceMetadata);
    // Particle-only models have no accessors; an unused buffer writes [{}],
    // which is invalid glTF and rejected by Godot.
    if (document.getRoot().listAccessors().length === 0) buffer.dispose();
    // Empty clips stay in IR; Godot rebuilds them for particle controls.
    for (const animation of document.getRoot().listAnimations()) {
      if (animation.listChannels().length === 0) animation.dispose();
    }
    await new NodeIO().write(dest, document);
    unlinkQuiet(dest.replace(/\.gltf$/i, ".glb"));
  } catch (err) {
    unlinkQuiet(dest);
    unlinkQuiet(destBin);
    unlinkQuiet(pe2Dest);
    unlinkQuiet(pe2Dest.replace(/\.pe2\.json$/i, ".ribbon.json"));
    unlinkQuiet(geosetVisDest);
    unlinkQuiet(attDest);
    unlinkQuiet(camDest);
    unlinkQuiet(animKeysDest);
    unlinkQuiet(collisionDest);
    unlinkQuiet(boneRestDest);
    unlinkQuiet(irDest);
    throw err;
  }
  return dest;
}
