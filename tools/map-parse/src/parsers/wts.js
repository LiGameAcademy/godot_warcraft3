/**
 * Parse war3map.wts trigger string table.
 * @param {string | Buffer} text
 * @returns {Record<number, string>}
 */
export function parseWts(text) {
  const src = typeof text === "string" ? text : text.toString("utf8");
  /** @type {Record<number, string>} */
  const strings = {};
  const re = /STRING\s+(\d+)\s*\r?\n\{\r?\n([\s\S]*?)\r?\n\}/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const id = Number(m[1]);
    if (!(id in strings)) {
      strings[id] = m[2].replace(/\r\n/g, "\n");
    }
  }
  return strings;
}

/**
 * Resolve TRIGSTR_nnn references using a .wts table.
 * @param {string} value
 * @param {Record<number, string>} strings
 */
export function resolveTrigStr(value, strings) {
  if (typeof value !== "string") return value;
  const m = /^TRIGSTR_(-?\d+)/i.exec(value);
  if (!m) return value;
  const id = Number(m[1]);
  if (id < 0) return "";
  return strings[id] ?? value;
}
