import assert from "node:assert/strict";
import test from "node:test";
import { compareTables } from "./compare-tables.mjs";

const table = records => ({ headers: ["id"], records });
test("distinguishes field additions from changed gameplay values and removed units", () => {
  const r = compareTables(table([{ id: "a", hp: 520 }, { id: "b", hp: 100 }, { id: "old" }]),
    table([{ id: "b", hp: 100, type: "hero" }, { id: "a", hp: 505 }, { id: "new" }]));
  assert.deepEqual(r.added, ["new"]);
  assert.deepEqual(r.removed, ["old"]);
  assert.equal(r.existingValueChanges, 1);
  assert.deepEqual(r.changed.find(x => x.id === "a").fields, [{ field: "hp", kind: "changed", before: 520, after: 505 }]);
});
test("preserves missing versus null, value types and field removal", () => {
  const r = compareTables(table([{ id: "a", hp: "100", armor: null, speed: 200 }]),
    table([{ id: "a", hp: 100, mana: null }]));
  assert.deepEqual(r.changed[0].fields.map(x => [x.field, x.kind]),
    [["hp", "changed"], ["armor", "removed"], ["speed", "removed"], ["mana", "added"]]);
});
test("row order does not change results; duplicate or missing identifiers fail", () => {
  assert.equal(compareTables(table([{ id: "a" }, { id: "b" }]), table([{ id: "b" }, { id: "a" }])).changed.length, 0);
  assert.throws(() => compareTables(table([{ id: "a" }, { id: "a" }]), table([])), /duplicate/);
  assert.throws(() => compareTables(table([]), table([{}])), /Missing/);
});
