import path from 'node:path';
import {detectClassicMpqs} from '../../mpq-extract/src/detect.js';
import * as storm from '../../mpq-extract/src/stormlib.js';

export function safeLogical(value) {
  if (typeof value !== 'string') throw new Error('logical_path_invalid');
  const logical = value.replaceAll('\\', '/');
  if (!logical || path.posix.isAbsolute(logical) || /[:\x00-\x1f<>"|?*]/.test(logical)
      || logical.split('/').some(part => !part || part === '.' || part === '..' || /[. ]$/.test(part))) {
    throw new Error('logical_path_invalid: ' + value);
  }
  return logical;
}

/** Probe exact names, including names omitted from MPQ listfiles. */
export class ClassicMpqSource {
  constructor(gameDir, io = storm, archives = detectClassicMpqs(gameDir)) {
    this.io = io;
    this.archives = [];
    try {
      for (const [priority, entry] of archives.entries()) {
        this.archives.push({...entry, priority, handle: io.openArchive(entry.absolutePath)});
      }
    } catch (error) { this.close(); throw error; }
  }
  read(name) {
    const logical = safeLogical(name);
    const archived = logical.replaceAll('/', '\\');
    for (const entry of [...this.archives].reverse()) {
      if (this.io.hasFile(entry.handle, archived)) {
        return {logical_path: logical, bytes: this.io.extractToBuffer(entry.handle, archived),
          source_package: entry.canonicalName, overlay_priority: entry.priority};
      }
    }
    throw new Error('source_dependency_missing: ' + logical);
  }
  close() {
    for (const entry of this.archives) this.io.closeArchive(entry.handle);
    this.archives = [];
  }
}
