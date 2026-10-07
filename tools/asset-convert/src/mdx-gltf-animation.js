import {createHash} from "node:crypto";
import { collectBakeFrames, evaluateNodeWorldMatrices, isAlternateOrMorphSequenceName, normalizeGeosetAlpha, sampleGeosetAlphaInSequence, sequenceBakeDurationMs, wc3SequenceToAnimName } from "./anim.js";
import { mat4Identity } from "./mat4.js";

import { writeGeosetVisSidecar } from "./mdx-animation-sidecars.js";
import { transformMat4Wc3ToGltf, collapseConstantTrsTrack, collapseConstantScaleTrack } from "./mdx-skeleton.js";

export function compileAnimations(model, document, buffer, restSeq, restStart, restEnd, allNodes, jointList, skinAnimNodes, jointByObjectId, geosetMeshNodes) {
  const accessors = new Map();
  // Joint tracks often share identical timelines and constant transforms.
  // Reusing their float32 payloads preserves every sample and avoids thousands
  // of duplicate accessors in Godot's glTF import.
  const accessor = (name, type, values) => {
    const array = new Float32Array(values);
    const digest = createHash('sha256').update(Buffer.from(array.buffer)).digest('hex');
    const key = type + ':' + digest;
    if (!accessors.has(key)) {
      accessors.set(key, document.createAccessor(name).setType(type).setArray(array).setBuffer(buffer));
    }
    return accessors.get(key);
  };
  // --- Animations (one glTF animation per WC3 Sequence) ---
  // Global Sequence（旗/钟）不跟 Sequence 区间走：循环段烘焙时长拉到最长 GlobalSeq，
  // 段内骨骼 % seqDur，GlobalSeq 骨骼 % globalDur。MDX Billboard 位（0x8）原样保留，
  // 不在烘焙时改朝向（RTS 固定机位；旗布也不是 TwoSided）。
  const globalSequences = (model.GlobalSequences ?? []).map((d) => Number(d) || 0);
  const bindSeq =
    (model.Sequences ?? []).find((s) => /^stand/i.test(String(s.Name || "").trim())) || restSeq;
  const bindStart = bindSeq?.Interval?.[0] ?? restStart;
  const bindEnd = bindSeq?.Interval?.[1] ?? restEnd;
  const bindWorlds = evaluateNodeWorldMatrices(
    allNodes,
    bindStart,
    bindStart,
    bindEnd,
    globalSequences,
    0,
  );
  if (model.Sequences?.length) {
    for (const seq of model.Sequences) {
      const start = seq.Interval[0];
      const end = seq.Interval[1];
      if (end <= start) continue;
      const seqDur = end - start;
      const looping = !seq.NonLooping;
      const bakeDur = sequenceBakeDurationMs(
        start,
        end,
        looping,
        allNodes,
        globalSequences,
      );

      const animName = wc3SequenceToAnimName(seq.Name || "Anim");
      const animation = document.createAnimation(animName);
      const frames = collectBakeFrames(
        allNodes,
        start,
        end,
        bakeDur,
        33,
        model.GeosetAnims || [],
        globalSequences,
      );

      /** @type {Map<number, { times: number[], t: number[], r: number[], s: number[] }>} */
      const tracks = new Map();
      for (const bone of skinAnimNodes) {
        tracks.set(bone.ObjectId, { times: [], t: [], r: [], s: [] });
      }

      /** @type {Map<number, { times: number[], s: number[] }>} */
      const geosetScaleTracks = new Map();
      for (const gi of geosetMeshNodes.keys()) {
        geosetScaleTracks.set(gi, { times: [], s: [] });
      }

      const seqNameRaw = String(seq.Name || "");
      const morphFamily = isAlternateOrMorphSequenceName(seqNameRaw);
      const isMorphSeq = /^\s*morph\b/i.test(seqNameRaw.trim());

      for (const tMs of frames) {
        const wrapped = tMs % seqDur;
        const seqFrame = looping
          ? (tMs > 0 && wrapped < 0.000001 ? end : start + wrapped)
          : start + tMs;
        const morphLerp =
          isMorphSeq && seqDur > 0
            ? Math.min(1, Math.max(0, (seqFrame - start) / seqDur))
            : null;
        const worlds = evaluateNodeWorldMatrices(
          allNodes,
          seqFrame,
          start,
          end,
          globalSequences,
          tMs,
          {
            carryInScaling: morphFamily && !isMorphSeq,
            morphScaleLerp: morphLerp,
          },
        );
        const timeSec = tMs / 1000;
        for (const bone of skinAnimNodes) {
          const world = worlds[bone.ObjectId] || mat4Identity();
          // Godot 4.6 平铺骨骼：global_pose≈pose（rest 不参与蒙皮）。
          // pose 必须写 WC3 世界阵；相对 Stand 的 delta 会在播动画时把骑士打回 T-pose。
          const { t, r, s } = transformMat4Wc3ToGltf(world);
          const track = tracks.get(bone.ObjectId);
          track.times.push(timeSec);
          track.t.push(t[0], t[1], t[2]);
          track.r.push(r[0], r[1], r[2], r[3]);
          track.s.push(s[0], s[1], s[2]);
        }

        for (const gi of geosetMeshNodes.keys()) {
          const alphaRaw = sampleGeosetAlphaInSequence(
            model.GeosetAnims,
            gi,
            seqFrame,
            start,
            end,
          );
          const alphaNorm = normalizeGeosetAlpha(alphaRaw);
          const gTrack = geosetScaleTracks.get(gi);
          gTrack.times.push(timeSec);
          gTrack.s.push(alphaNorm, alphaNorm, alphaNorm);
        }
      }

      for (const bone of skinAnimNodes) {
        const joint = jointByObjectId.get(bone.ObjectId);
        let track = tracks.get(bone.ObjectId);
        if (!joint || !track?.times.length) continue;
        track = collapseConstantTrsTrack(track);

        const input = accessor(`${animName}_${bone.ObjectId}_time`, "SCALAR", track.times);

        const tOut = accessor(`${animName}_${bone.ObjectId}_t`, "VEC3", track.t);
        const rOut = accessor(`${animName}_${bone.ObjectId}_r`, "VEC4", track.r);
        const sOut = accessor(`${animName}_${bone.ObjectId}_s`, "VEC3", track.s);

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
        let gTrack = geosetScaleTracks.get(gi);
        if (!gTrack?.times.length) continue;
        gTrack = collapseConstantScaleTrack(gTrack);
        const input = accessor(`${animName}_geoset${gi}_time`, "SCALAR", gTrack.times);
        const sOut = accessor(`${animName}_geoset${gi}_s`, "VEC3", gTrack.s);
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


  return bindWorlds;
}
