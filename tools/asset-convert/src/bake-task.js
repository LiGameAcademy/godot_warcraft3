import fs from "node:fs";
import path from "node:path";

export const BAKE_TASK_VERSION = 1;

const PROFILES = new Set(["fidelity", "enhanced"]);

export function createBakeTask(input = {}) {
  const profile = String(input.profile ?? "fidelity");
  if (!PROFILES.has(profile)) throw new Error(`invalid bake profile: ${profile}`);
  return {
    task_version: BAKE_TASK_VERSION,
    asset_id: String(input.asset_id ?? ""),
    ir_path: String(input.ir_path ?? ""),
    geometry_path: String(input.geometry_path ?? ""),
    output_scene: String(input.output_scene ?? ""),
    profile,
    rules_version: String(input.rules_version ?? ""),
    expected_signature: String(input.expected_signature ?? ""),
    dependencies: Array.isArray(input.dependencies) ? input.dependencies : [],
  };
}

export function validateBakeTask(value) {
  const errors = [];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, errors: ["bake task must be an object"] };
  }
  const task = /** @type {Record<string, any>} */ (value);
  if (task.task_version !== BAKE_TASK_VERSION) errors.push(`unsupported task_version: ${String(task.task_version)}`);
  for (const key of ["asset_id", "ir_path", "geometry_path", "output_scene"]) {
    if (!String(task[key] ?? "").trim()) errors.push(`${key} is required`);
  }
  if (!PROFILES.has(String(task.profile ?? ""))) errors.push("profile must be fidelity or enhanced");
  if (!Array.isArray(task.dependencies)) errors.push("dependencies must be an array");
  return { ok: errors.length === 0, errors };
}

export function writeBakeTask(destination, task) {
  const result = validateBakeTask(task);
  if (!result.ok) throw new Error(`invalid bake task: ${result.errors.join("; ")}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.tmp-${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(task, null, 2)}\n`, "utf8");
  fs.renameSync(temporary, destination);
}

export function validateWorkerResult(value) {
  const errors = [];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, errors: ["worker result must be an object"] };
  }
  const result = /** @type {Record<string, any>} */ (value);
  if (result.result_version !== BAKE_TASK_VERSION) errors.push(`unsupported result_version: ${String(result.result_version)}`);
  if (typeof result.ok !== "boolean") errors.push("ok must be boolean");
  if (!String(result.asset_id ?? "").trim()) errors.push("asset_id is required");
  if (!Array.isArray(result.diagnostics)) errors.push("diagnostics must be an array");
  if (result.ok && !String(result.output_scene ?? "").trim()) errors.push("successful result requires output_scene");
  return { ok: errors.length === 0, errors };
}
