import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { extractMpqs } from "./extract.js";

function fixture(t, archives, include = [], exclude = []) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wc3-patch-test-"));
  t.after(() => {
    const relative = path.relative(path.resolve(os.tmpdir()), path.resolve(root));
    assert.ok(!path.isAbsolute(relative) && !relative.startsWith("..") && relative.startsWith("wc3-patch-test-"));
    fs.rmSync(root, { recursive: true, force: true });
  });
  const options = {
    mpqs: Object.keys(archives).map(name => ({ canonicalName: name, absolutePath: name })),
    gameDir: root, outDir: path.join(root, "out"), manifestPath: path.join(root, "manifest.json"),
    force: false, include, exclude,
  };
  const io = {
    openArchive: name => archives[name], closeArchive: () => {},
    listFiles: archive => archive.list,
    hasFile: (archive, name) => Object.hasOwn(archive.files, name.toLowerCase()),
    extractToBuffer: (archive, name) => {
      const contents = archive.files[name.toLowerCase()];
      if (contents === undefined) throw new Error("Missing file");
      if (contents instanceof Error) throw contents;
      return Buffer.from(contents);
    },
  };
  return {
    options, run: () => extractMpqs(options, io),
    read: name => fs.readFileSync(path.join(options.outDir, name), "utf8"),
    manifest: () => JSON.parse(fs.readFileSync(options.manifestPath, "utf8")),
  };
}

test("unlisted patch overrides base by a known path, including repeat extraction", t => {
  const f = fixture(t, {
    base: { list: ["Units\\Data.txt", "Units\\BaseOnly.txt"], files: { "units\\data.txt": "old", "units\\baseonly.txt": "base" } },
    patch: { list: ["(listfile)"], files: { "units\\data.txt": "patched" } },
  }, ["Units/**"]);
  for (let i = 0; i < 2; i++) {
    assert.equal(f.run().errors, 0);
    assert.equal(f.read("Units/Data.txt"), "patched");
    assert.equal(f.read("Units/BaseOnly.txt"), "base");
    assert.equal(f.manifest().files["Units/Data.txt"].sourceMpq, "patch");
    assert.equal(f.manifest().files["Units/BaseOnly.txt"].sourceMpq, "base");
  }
});

test("exact includes discover files absent from every listfile; missing probes are normal", t => {
  const f = fixture(t, { patch: { list: [], files: { "units\\hidden.txt": "found" } } },
    ["Units/Hidden.txt", "Units/Missing.txt"]);
  assert.equal(f.run().errors, 0);
  assert.equal(f.read("Units/Hidden.txt"), "found");
  assert.equal(Object.keys(f.manifest().files).length, 1);
});

test("excluded known paths are not extracted or probed into output", t => {
  const f = fixture(t, {
    base: { list: ["Units\\Data.txt"], files: { "units\\data.txt": "old" } },
    patch: { list: [], files: { "units\\data.txt": "new" } },
  }, ["Units/**"], ["Units/Data.txt"]);
  assert.equal(f.run().errors, 0);
  assert.equal(Object.keys(f.manifest().files).length, 0);
});

test("case variants are one logical file and preserve patch precedence", t => {
  const f = fixture(t, {
    base: { list: ["Units\\Data.txt"], files: { "units\\data.txt": "old" } },
    patch: { list: ["units\\DATA.txt"], files: { "units\\data.txt": "new" } },
  });
  assert.equal(f.run().errors, 0);
  assert.equal(f.read("Units/Data.txt"), "new");
  assert.equal(Object.keys(f.manifest().files).length, 1);
});

test("an existing but unreadable patch file remains an extraction error", t => {
  const f = fixture(t, {
    base: { list: ["Units\\Data.txt"], files: { "units\\data.txt": "old" } },
    patch: { list: [], files: { "units\\data.txt": new Error("Corrupt patch") } },
  });
  assert.equal(f.run().errors, 1);
  assert.equal(f.manifest().files["Units/Data.txt"].sourceMpq, "base");
});
