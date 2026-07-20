/**
 * Parse Blizzard's SYLK (.slk) subset used by classic Warcraft III.
 *
 * Records (one per line):
 *   ID;...     header
 *   B;Xcols;Yrows;D0   dimensions (optional)
 *   C;Xcol;Yrow;Kvalue cell (X/Y may be omitted → sticky / next column)
 *   E           end
 *
 * @see https://github.com/stijnherfst/HiveWE/wiki/SLK
 */

/**
 * Split a SYLK record line on `;`, respecting quoted K strings.
 * @param {string} line
 * @returns {string[]}
 */
function splitFields(line) {
  const fields = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
      cur += ch;
      continue;
    }
    if (ch === ";" && !inQuotes) {
      fields.push(cur);
      cur = "";
      continue;
    }
    cur += ch;
  }
  fields.push(cur);
  return fields;
}

/**
 * @param {string} raw
 * @returns {string | number | boolean | null}
 */
function parseKValue(raw) {
  if (raw === undefined || raw === "") return null;
  if (raw.startsWith('"')) {
    // "string" — unescape doubled quotes if any
    let s = raw;
    if (s.endsWith('"') && s.length >= 2) s = s.slice(1, -1);
    else s = s.slice(1);
    return s.replace(/""/g, '"');
  }
  const lower = raw.toLowerCase();
  if (lower === "true") return true;
  if (lower === "false") return false;
  if (/^-?\d+$/.test(raw)) {
    const n = Number(raw);
    if (Number.isSafeInteger(n)) return n;
  }
  if (/^-?\d+\.\d+([eE][-+]?\d+)?$/.test(raw) || /^-?\d+[eE][-+]?\d+$/.test(raw)) {
    return Number(raw);
  }
  return raw;
}

/**
 * @param {string | Buffer} input
 * @returns {{
 *   columns: number,
 *   rows: number,
 *   headers: string[],
 *   records: Record<string, unknown>[],
 *   grid: (string|number|boolean|null)[][],
 * }}
 */
export function parseSlk(input) {
  const text = typeof input === "string" ? input : input.toString("utf8");
  const lines = text.split(/\r?\n/);

  /** @type {Map<string, string|number|boolean|null>} */
  const cells = new Map();
  let maxX = 0;
  let maxY = 0;
  let declaredX = 0;
  let declaredY = 0;

  let curX = 0;
  let curY = 1;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    const fields = splitFields(line);
    const type = fields[0];

    if (type === "ID") continue;
    if (type === "E") break;

    if (type === "B") {
      for (let i = 1; i < fields.length; i += 1) {
        const f = fields[i];
        if (f.startsWith("X")) declaredX = Number(f.slice(1)) || 0;
        else if (f.startsWith("Y")) declaredY = Number(f.slice(1)) || 0;
      }
      continue;
    }

    if (type !== "C") continue;

    let x;
    let y;
    let kRaw;
    for (let i = 1; i < fields.length; i += 1) {
      const f = fields[i];
      if (!f) continue;
      const code = f[0];
      if (code === "X") x = Number(f.slice(1));
      else if (code === "Y") y = Number(f.slice(1));
      else if (code === "K") kRaw = f.slice(1);
    }

    if (y !== undefined) curY = y;
    if (x !== undefined) curX = x;
    else curX += 1;

    if (kRaw === undefined) continue;

    const value = parseKValue(kRaw);
    cells.set(`${curX},${curY}`, value);
    if (curX > maxX) maxX = curX;
    if (curY > maxY) maxY = curY;
  }

  const columns = Math.max(maxX, declaredX);
  const rows = Math.max(maxY, declaredY);

  /** @type {(string|number|boolean|null)[][]} */
  const grid = [];
  for (let y = 1; y <= rows; y += 1) {
    /** @type {(string|number|boolean|null)[]} */
    const row = [];
    for (let x = 1; x <= columns; x += 1) {
      row.push(cells.has(`${x},${y}`) ? cells.get(`${x},${y}`) ?? null : null);
    }
    grid.push(row);
  }

  const headerRow = grid[0] ?? [];
  /** @type {string[]} */
  const headers = headerRow.map((h, i) => {
    if (h === null || h === undefined || h === "") return `col_${i + 1}`;
    return String(h);
  });

  // Dedupe header names (rare, but keeps object keys unique)
  const seen = new Map();
  for (let i = 0; i < headers.length; i += 1) {
    const base = headers[i];
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    if (n > 1) headers[i] = `${base}_${n}`;
  }

  /** @type {Record<string, unknown>[]} */
  const records = [];
  for (let y = 1; y < grid.length; y += 1) {
    const row = grid[y];
    // Skip completely empty rows
    if (row.every((c) => c === null || c === undefined || c === "")) continue;

    /** @type {Record<string, unknown>} */
    const obj = {};
    for (let x = 0; x < headers.length; x += 1) {
      const v = row[x];
      if (v === null || v === undefined) continue;
      obj[headers[x]] = v;
    }
    if (Object.keys(obj).length) records.push(obj);
  }

  return { columns, rows, headers, records, grid };
}
