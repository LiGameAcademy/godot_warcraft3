import { renameWithRetrySync } from "./atomic-write.js";
import fs from "node:fs";
import crypto from "node:crypto";
import path from "node:path";

export const MODEL_IR_SCHEMA_VERSION = 1;

const STATUS_VALUES = new Set([
  "parsed",
  "exported",
  "consumed",
  "approximated",
  "fallback",
  "validated",
]);

const PROFILE_VALUES = new Set(["fidelity", "enhanced"]);

/**
 * Create the stable envelope shared by developer import and runtime import.
 * Feature payloads are intentionally open objects for now; the schema is
 * tightened only after the first representative asset batch is measured.
 * @param {object} input
 * @returns {object}
 */
export function createModelIr(input = {}) {
  const profile = String(input.profile ?? "fidelity");
  if (!PROFILE_VALUES.has(profile)) {
    throw new Error(`model IR profile must be fidelity or enhanced: ${profile}`);
  }
  return {
    schema_version: MODEL_IR_SCHEMA_VERSION,
    identity: {
      asset_id: String(input.asset_id ?? ""),
      logical_path: String(input.logical_path ?? ""),
      source_format: String(input.source_format ?? "unknown"),
    },
    source: {
      source_path: String(input.source_path ?? ""),
      source_hash: String(input.source_hash ?? ""),
      source_package: String(input.source_package ?? ""),
      overlay_priority: Number(input.overlay_priority ?? 0),
    },
    profile,
    geometry: input.geometry ?? {},
    skeleton: input.skeleton ?? {},
    animations: input.animations ?? {},
    materials: input.materials ?? {},
    textures: input.textures ?? {},
    geoset_visibility: input.geoset_visibility ?? {},
    texture_animations: input.texture_animations ?? {},
    particles: input.particles ?? {},
    ribbons: input.ribbons ?? {},
    attachments: input.attachments ?? {},
    team_color: input.team_color ?? {},
    glow_categories: input.glow_categories ?? [],
    cameras: input.cameras ?? {},
    events: input.events ?? {},
    dependencies: Array.isArray(input.dependencies) ? input.dependencies : [],
    diagnostics: Array.isArray(input.diagnostics) ? input.diagnostics : [],
    feature_status: input.feature_status ?? {},
  };
}

/**
 * Validate the stable parts of a Model IR document. Unknown feature fields
 * are allowed so older converters can be migrated incrementally, but every
 * diagnostic and feature status must use the shared vocabulary.
 * @param {unknown} value
 * @returns {{ok: boolean, errors: string[]}}
 */
export function validateModelIr(value) {
  const errors = [];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, errors: ["model IR must be an object"] };
  }
  const ir = /** @type {Record<string, any>} */ (value);
  if (ir.schema_version !== MODEL_IR_SCHEMA_VERSION) {
    errors.push(`unsupported schema_version: ${String(ir.schema_version)}`);
  }
  if (!ir.identity || typeof ir.identity !== "object") {
    errors.push("identity is required");
  } else {
    if (!String(ir.identity.asset_id ?? "").trim()) errors.push("identity.asset_id is required");
    if (!String(ir.identity.logical_path ?? "").trim()) errors.push("identity.logical_path is required");
  }
  if (!PROFILE_VALUES.has(String(ir.profile ?? ""))) {
    errors.push("profile must be fidelity or enhanced");
  }
  if (!Array.isArray(ir.dependencies)) errors.push("dependencies must be an array");
  if (!Array.isArray(ir.diagnostics)) errors.push("diagnostics must be an array");
  if (!ir.feature_status || typeof ir.feature_status !== "object") {
    errors.push("feature_status must be an object");
  } else {
    for (const [feature, status] of Object.entries(ir.feature_status)) {
      if (!STATUS_VALUES.has(String(status))) {
        errors.push(`feature_status.${feature} has invalid status: ${String(status)}`);
      }
    }
  }
  for (const [index, diagnostic] of (Array.isArray(ir.diagnostics) ? ir.diagnostics : []).entries()) {
    if (!diagnostic || typeof diagnostic !== "object") {
      errors.push(`diagnostics[${index}] must be an object`);
      continue;
    }
    if (!String(diagnostic.code ?? "").trim()) errors.push(`diagnostics[${index}].code is required`);
    if (!String(diagnostic.severity ?? "").trim()) errors.push(`diagnostics[${index}].severity is required`);
  }
  return { ok: errors.length === 0, errors };
}

/**
 * Write IR atomically enough for a batch job: a complete temporary file is
 * renamed only after JSON serialization succeeds.
 * @param {string} destination
 * @param {object} value
 */
export function writeModelIr(destination, value) {
  const result = validateModelIr(value);
  if (!result.ok) throw new Error(`invalid model IR: ${result.errors.join("; ")}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.tmp-${process.pid}`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
    renameWithRetrySync(temporary, destination);
  } catch (error) {
    try { fs.unlinkSync(temporary); } catch { /* Preserve the original failure. */ }
    throw error;
  }
}

/** @param {Buffer} bytes */
export function sha256Bytes(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}
