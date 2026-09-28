import fs from "node:fs";
import path from "node:path";
import { mdxLogicalToAttachments } from "./paths.js";
import { atomicWriteBytesSync } from "./atomic-write.js";

import { MODEL_SCALE, sanitizeMdxText, asVec3, sidecarVec3, dumpAnimVector, attachmentVisibleByDefault } from "./mdx-values.js";
import { bakePivotDeltaGltf } from "./mdx-particles.js";

/**
 * 把 MDX 里没被 m2g 写进 .gltf 的"附加元素"导出成 sidecar JSON。
 * 包含 2 部分：
 * 1. attachments[]：4 类辅助元素（Attachment / ParticleEmitter2 / Light / RibbonEmitter）
 * 2. geoset_expansions[]：每个 geoset 按 VertexGroup 拆分成 group
 *    （每个 group 1 个 mesh 节点 + BoneAttachment3D，烘焙时由 Godot 端拼装）
 *
 * @param {object} model
 * @param {string} logicalPath
 * @returns {object} attachments sidecar
 */
export function extractAttachments(model, logicalPath) {
	const boneNames = (model.Bones ?? []).map((b) => b.Name);

	// 查 ObjectId → bone name 映射。
	// 修：war3-model 库只把 mesh-related bone (flag=256) 放进 model.Bones，
	// 真正的骨架 bone（Bone_Root / Bone_Pelvis / Bone_Foot_L 等 flag=0 Helper）
	// 只在 model.Nodes 里。attachment.Parent 可能引用任一边。
	// 例：Footman attachment "Foot Left Ref" Parent=29 → Bone_Foot_L (Helper, in Nodes)
	const _boneIdToName = (() => {
		const m = new Map();
		for (const b of model.Bones ?? []) {
			if (b.ObjectId != null) m.set(b.ObjectId, b.Name);
		}
		for (const id of Object.keys(model.Nodes ?? {})) {
			const n = model.Nodes[id];
			if (!m.has(n.ObjectId)) m.set(n.ObjectId, n.Name);
		}
		return m;
	})();

	function boneNameById(id) {
		if (id == null) return null;
		const n = _boneIdToName.get(id) ?? null;
		return n == null ? null : sanitizeMdxText(n);
	}

	const out = {
		version: 1,
		model: logicalPath,
		skeleton_bone_count: boneNames.length,
		skeleton_helper_count: (model.Helpers ?? []).length,
		attachments: [],
		geoset_expansions: [],
	};

	function nodeByObjectId(id) {
		if (id == null) return null;
		for (const n of model.Nodes ?? []) {
			if (n && n.ObjectId === id) return n;
		}
		return null;
	}

	// 4 类辅助 attachment
	for (const a of model.Attachments ?? []) {
		const parentNode = nodeByObjectId(a.Parent);
		const entry = {
			name: sanitizeMdxText(a.Name),
			type: "attachment",
			bone: boneNameById(a.Parent),
			source: `attachment_${a.AttachmentID ?? 0}`,
			object_id: a.ObjectId ?? null,
			path: String(a.Path || ""),
			// Flags 0x4 = DontInherit Scaling，不是显隐。无 KATV 则插座保持可见。
			visibility_default: attachmentVisibleByDefault(a),
			// 世界/场景根挂点：已 × MODEL_SCALE
			pivot: sidecarVec3(
				asVec3(a.PivotPoint)[0],
				asVec3(a.PivotPoint)[1],
				asVec3(a.PivotPoint)[2],
			),
		};
		// 绑骨：相对父骨 Pivot 的局部偏移（与 SkinMesh 顶点同空间；根节点再 × MODEL_SCALE）
		if (parentNode && boneNameById(a.Parent)) {
			entry.pivot_delta = bakePivotDeltaGltf(a.PivotPoint, parentNode.PivotPoint);
		}
		const vis = dumpAnimVector(a.Visibility);
		if (vis) entry.visibility = vis;
		out.attachments.push(entry);
	}
	for (const p of model.ParticleEmitters2 ?? []) {
		out.attachments.push({
			name: sanitizeMdxText(p.Name),
			type: "particle",
			bone: boneNameById(p.Parent),
			source: `pe2:${sanitizeMdxText(p.Name)}`,
		});
	}
	for (const l of model.Lights ?? []) {
		const pivot = asVec3(l.PivotPoint);
		const color = asVec3(l.Color);
		const vis = dumpAnimVector(l.Visibility);
		const vis0 = vis?.keys?.[0]?.vector?.[0];
		const visStatic = vis?.static;
		let visibilityDefault = false;
		if (typeof visStatic === "number") {
			visibilityDefault = visStatic >= 0.5;
		} else if (Array.isArray(visStatic)) {
			visibilityDefault = Number(visStatic[0]) >= 0.5;
		} else if (vis0 != null) {
			visibilityDefault = Number(vis0) >= 0.5;
		}
		const entry = {
			name: sanitizeMdxText(l.Name),
			type: "light",
			bone: boneNameById(l.Parent),
			source: Number(l.LightType) === 0 ? "OmniLight" : "DirectionalLight",
			object_id: l.ObjectId ?? null,
			light_type: Number(l.LightType) || 0,
			attenuation_start: (Number(l.AttenuationStart) || 0) * MODEL_SCALE,
			attenuation_end: (Number(l.AttenuationEnd) || 0) * MODEL_SCALE,
			intensity: Number(l.Intensity) || 0,
			color: [color[0], color[1], color[2]],
			visibility_default: visibilityDefault,
			pivot: sidecarVec3(pivot[0], pivot[1], pivot[2]),
		};
		if (vis) entry.visibility = vis;
		out.attachments.push(entry);
	}
	for (const r of model.RibbonEmitters ?? []) {
		out.attachments.push({
			name: sanitizeMdxText(r.Name),
			type: "ribbon",
			bone: boneNameById(r.Parent),
			source: "ribbon_emitter",
		});
	}

	// geoset 顶点按 VertexGroup 拆分（每 group = 1 个 mesh 节点 + BoneAttachment3D）
	// 同时识别 geoset_kind（normal / teamcolor / glow）— 用于 D-3 export_model_scenes 替换为 ShaderMaterial
	// 识别逻辑：geoset.MaterialId → Materials[mid].Layers[] → 找 TextureId=1 (teamcolor) / 2 (team_glow)
	function classifyGeosetKind(geoset) {
		const matId = geoset.MaterialId;
		if (matId == null) return "normal";
		const mat = model.Materials?.[matId];
		if (!mat || !mat.Layers) return "normal";
		let has_teamcolor = false;
		let has_teamglow = false;
		for (const layer of mat.Layers) {
			const tid = layer.TextureId;
			if (tid === 1) has_teamcolor = true;
			if (tid === 2) has_teamglow = true;
		}
		if (has_teamglow) return "glow";
		if (has_teamcolor) return "teamcolor";
		return "normal";
	}
	for (let gi = 0; gi < (model.Geosets ?? []).length; gi += 1) {
		const g = model.Geosets[gi];
		const vg = g.VertexGroup;
		const kind = classifyGeosetKind(g);
		if (!vg || vg.length === 0) {
			out.geoset_expansions.push({
				geoset_index: gi,
				geoset_name: `Geoset_${gi}`,
				kind: kind,
				groups: [],
			});
			continue;
		}
		// 按 group index 分组顶点
		const groupMap = new Map(); // groupIdx -> [vertIdx]
		for (let i = 0; i < vg.length; i += 1) {
			const groupIdx = vg[i];
			if (!groupMap.has(groupIdx)) groupMap.set(groupIdx, []);
			groupMap.get(groupIdx).push(i);
		}
		const groups = [];
		for (const [groupIdx, vertIdx] of groupMap) {
			const boneIds = g.Groups?.[groupIdx] ?? [];
			const bones = boneIds
				.map((id) => boneNameById(id))
				.filter((n) => n != null);
			groups.push({
				group_index: groupIdx,
				bones: bones,
				vertex_count: vertIdx.length,
				vertex_indices: vertIdx, // 全部 vertex indices（烘焙时 subset 顶点）
			});
		}
		out.geoset_expansions.push({
			geoset_index: gi,
			geoset_name: `Geoset_${gi}`,
			kind: kind,
			groups: groups,
		});
	}

	// rep_materials[]：列出所有 model 级别的 replaceable texture 用法（TextureId=0/1/2）
	// D-3 export_model_scenes 用此决定哪些 geoset 替换为 ShaderMaterial
	const rep_materials = [];
	for (let mi = 0; mi < (model.Materials ?? []).length; mi += 1) {
		const mat = model.Materials[mi];
		if (!mat || !mat.Layers) continue;
		for (let li = 0; li < mat.Layers.length; li += 1) {
			const layer = mat.Layers[li];
			const tid = layer.TextureId;
			if (tid == null || tid === 0) continue;
			const kind = tid === 1 ? "teamcolor" : tid === 2 ? "teamglow" : `rep${tid}`;
			rep_materials.push({
				material_index: mi,
				layer_index: li,
				replaceable_id: tid,
				kind: kind,
			});
		}
	}
	out.rep_materials = rep_materials;

	return out;
}

/**
 * 写 attachments JSON sidecar 到 <model>.attachments.json
 * @param {object} model
 * @param {string} logicalPath
 * @param {string} outDir
 * @returns {string} 写出路径
 */
export function writeAttachmentsSidecar(model, logicalPath, outDir) {
	const att = extractAttachments(model, logicalPath);
	const logical = mdxLogicalToAttachments(logicalPath);
	const dest = path.join(outDir, ...logical.split("/"));
	fs.mkdirSync(path.dirname(dest), { recursive: true });
	atomicWriteBytesSync(dest, `${JSON.stringify(att, null, 2)}\n`);
	return dest;
}
