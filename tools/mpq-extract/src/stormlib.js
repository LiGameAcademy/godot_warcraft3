import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import koffi from "koffi";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");

const STREAM_FLAG_READ_ONLY = 0x100;
const MAX_PATH = 260;

/** @type {import('koffi').IKoffiLib | null} */
let lib = null;
/** @type {Record<string, Function>} */
let api = {};

function resolveStormLibDll() {
  const candidates = [
    process.env.STORMLIB_DLL,
    path.join(PACKAGE_ROOT, "vendor", "stormlib", "StormLib.dll"),
    path.join(PACKAGE_ROOT, "vendor", "stormlib", "x64", "StormLib.dll"),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }

  throw new Error(
    "未找到 StormLib.dll（期望 vendor/stormlib/StormLib.dll）。请运行: npm run fetch-stormlib",
  );
}

function ensureLoaded() {
  if (lib) return;

  const dllPath = resolveStormLibDll();
  lib = koffi.load(dllPath);

  // Use ANSI (char) StormLib build — Unicode DLL needs str16 and different FIND_DATA layout.
  api.SFileOpenArchive = lib.func(
    "bool SFileOpenArchive(str filename, uint32 priority, uint32 flags, _Out_ void ** handle)",
  );
  api.SFileCloseArchive = lib.func("bool SFileCloseArchive(void * handle)");
  api.SFileHasFile = lib.func("bool SFileHasFile(void * mpq, str filename)");
  api.SFileOpenFileEx = lib.func(
    "bool SFileOpenFileEx(void * mpq, str filename, uint32 scope, _Out_ void ** file)",
  );
  api.SFileCloseFile = lib.func("bool SFileCloseFile(void * file)");
  api.SFileGetFileSize = lib.func(
    "uint32 SFileGetFileSize(void * file, _Out_ uint32 * sizeHigh)",
  );
  api.SFileReadFile = lib.func(
    "bool SFileReadFile(void * file, void * buffer, uint32 toRead, _Out_ uint32 * read, void * overlapped)",
  );
  api.SFileExtractFile = lib.func(
    "bool SFileExtractFile(void * mpq, str toExtract, str extracted, uint32 scope)",
  );

  const SFILE_FIND_DATA = koffi.struct("SFILE_FIND_DATA", {
    cFileName: koffi.array("char", MAX_PATH),
    szPlainName: "char *",
    dwHashIndex: "uint32",
    dwBlockIndex: "uint32",
    dwFileSize: "uint32",
    dwFileFlags: "uint32",
    dwCompSize: "uint32",
    dwFileTimeLo: "uint32",
    dwFileTimeHi: "uint32",
    lcLocale: "uint32",
  });

  api.SFileFindFirstFile = lib.func(
    "void * SFileFindFirstFile(void * mpq, str mask, _Out_ SFILE_FIND_DATA * data, str listFile)",
  );
  api.SFileFindNextFile = lib.func(
    "bool SFileFindNextFile(void * find, _Out_ SFILE_FIND_DATA * data)",
  );
  api.SFileFindClose = lib.func("bool SFileFindClose(void * find)");
}

function charsToString(chars) {
  if (!chars) return "";
  let end = chars.length;
  for (let i = 0; i < chars.length; i += 1) {
    if (chars[i] === 0) {
      end = i;
      break;
    }
  }
  return Buffer.from(chars.slice(0, end)).toString("latin1");
}

/**
 * @param {string} archivePath
 */
export function openArchive(archivePath) {
  ensureLoaded();
  const handlePtr = [null];
  const ok = api.SFileOpenArchive(archivePath, 0, STREAM_FLAG_READ_ONLY, handlePtr);
  if (!ok || !handlePtr[0]) {
    throw new Error(`SFileOpenArchive failed: ${archivePath}`);
  }
  return { handle: handlePtr[0], path: archivePath };
}

/**
 * @param {{ handle: object | null }} archive
 */
export function closeArchive(archive) {
  if (archive?.handle) {
    api.SFileCloseArchive(archive.handle);
    archive.handle = null;
  }
}

/**
 * Prefer reading embedded (listfile); fall back to FindFirst enumeration.
 * @param {{ handle: object }} archive
 * @param {string | null} listFilePath optional external listfile
 * @returns {string[]}
 */
export function listFiles(archive, listFilePath = null) {
  ensureLoaded();

  if (listFilePath && fs.existsSync(listFilePath)) {
    return fs
      .readFileSync(listFilePath, "utf8")
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter(Boolean);
  }

  // Extract embedded (listfile) when present — most reliable for classic WC3.
  if (api.SFileHasFile(archive.handle, "(listfile)")) {
    const tmp = path.join(
      os.tmpdir(),
      `wc3-listfile-${process.pid}-${Date.now()}.txt`,
    );
    try {
      if (api.SFileExtractFile(archive.handle, "(listfile)", tmp, 0)) {
        const names = fs
          .readFileSync(tmp, "utf8")
          .split(/\r?\n/)
          .map((l) => l.trim())
          .filter(Boolean);
        if (names.length > 0) return names;
      }
    } finally {
      try {
        fs.unlinkSync(tmp);
      } catch {
        // ignore
      }
    }
  }

  const names = [];
  const data = {};
  const find = api.SFileFindFirstFile(archive.handle, "*", data, null);
  if (!find) return names;

  try {
    do {
      const name = charsToString(data.cFileName);
      if (name) names.push(name);
    } while (api.SFileFindNextFile(find, data));
  } finally {
    api.SFileFindClose(find);
  }

  return names;
}

/**
 * @param {{ handle: object }} archive
 * @param {string} archivedName MPQ path using backslashes
 * @returns {Buffer}
 */
export function extractToBuffer(archive, archivedName) {
  ensureLoaded();
  const filePtr = [null];
  const okOpen = api.SFileOpenFileEx(archive.handle, archivedName, 0, filePtr);
  if (!okOpen || !filePtr[0]) {
    throw new Error(`SFileOpenFileEx failed: ${archivedName}`);
  }

  const file = filePtr[0];
  try {
    const sizeHigh = [0];
    const sizeLow = api.SFileGetFileSize(file, sizeHigh);
    if (sizeLow === 0xffffffff) {
      throw new Error(`SFileGetFileSize failed: ${archivedName}`);
    }
    const size = sizeLow + sizeHigh[0] * 0x100000000;
    if (size > Number.MAX_SAFE_INTEGER) {
      throw new Error(`File too large: ${archivedName}`);
    }
    // Classic MPQs sometimes list 0-byte placeholders (e.g. war3x.txt).
    if (size === 0) {
      return Buffer.alloc(0);
    }

    const buf = Buffer.alloc(Number(size));
    const readOut = [0];
    const okRead = api.SFileReadFile(file, buf, buf.length, readOut, null);
    if (!okRead) {
      throw new Error(`SFileReadFile failed: ${archivedName}`);
    }
    if (readOut[0] !== buf.length) {
      return buf.subarray(0, readOut[0]);
    }
    return buf;
  } finally {
    api.SFileCloseFile(file);
  }
}

export function getStormLibArchLabel() {
  return `${os.platform()}-${process.arch}`;
}
