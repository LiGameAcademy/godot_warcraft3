/** Exact logical names only: never pass archive-derived glob patterns to extraction. */
export function missingSourceNames(manifest) {
  const names = new Map();
  for (const asset of manifest.assets.filter(row => !row.available)) {
    const candidates = [asset.logical_path, ...asset.reasons.flatMap(reason => reason.candidates ?? [])];
    for (const candidate of candidates) {
      const clean = candidate.replaceAll('\\', '/');
      if (!clean || clean.startsWith('/') || /[:*?\[\]{}()!\x00-\x1f]/.test(clean)
        || clean.split('/').some(part => !part || part === '..' || part === '.')) {
        throw new Error(`Unsafe exact source path: ${candidate}`);
      }
      const variants = /\.(mdx|mdl)$/i.test(clean)
        ? [clean.replace(/\.(mdx|mdl)$/i, '.mdx'), clean.replace(/\.(mdx|mdl)$/i, '.mdl')] : [clean];
      for (const name of variants) names.set(name.toLowerCase(), name);
    }
  }
  return [...names.values()].sort();
}

/** Re-scan recovered models to discover their textures and model-emitter dependencies.
 * No failed name is retried endlessly, and extraction errors stop the run visibly. */
export function recoverDevelopmentSources({build, extract, maxPasses = 8}) {
  if (!Number.isInteger(maxPasses) || maxPasses < 1) throw new Error('maxPasses must be positive');
  const attempted = new Set();
  const passes = [];
  let manifest = build();
  for (let pass = 0; pass < maxPasses; pass++) {
    const requested = missingSourceNames(manifest).filter(name => !attempted.has(name.toLowerCase()));
    if (!requested.length) break;
    requested.forEach(name => attempted.add(name.toLowerCase()));
    const missing = manifest.assets.filter(row => !row.available).map(row => row.id);
    const stats = extract(requested);
    manifest = build();
    const available = new Set(manifest.assets.filter(row => row.available).map(row => row.id));
    passes.push({requested, stats, recovered: missing.filter(id => available.has(id))});
    if (stats.errors) return {status: 'extraction_failed', passes, manifest};
  }
  const remaining = missingSourceNames(manifest);
  const status = !remaining.length ? 'sources_available'
    : remaining.some(name => !attempted.has(name.toLowerCase())) ? 'pass_limit' : 'unresolved_sources';
  return {status, passes, manifest};
}
