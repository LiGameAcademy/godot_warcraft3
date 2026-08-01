import fs from "node:fs";

const root = "D:/GodotProject/laoli_gamedev_godot4_course/godot_warcraft3";
const gs = fs.readFileSync(`${root}/assets/asset-converted/UI/WorldEditGameStrings.txt`, "utf8");
const ws = fs.readFileSync(`${root}/assets/asset-converted/UI/WorldEditStrings.txt`, "utf8");
const dict = {};
for (const t of [gs, ws]) {
  for (const line of t.split(/\r?\n/)) {
    const eq = line.indexOf("=");
    if (eq <= 0) continue;
    let v = line.slice(eq + 1).trim();
    if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
    const k = line.slice(0, eq).trim();
    if (k.startsWith("WESTRING_DOOD_") || k.startsWith("WESTRING_DEST_")) dict[k] = v;
  }
}
const keys = Object.keys(dict).sort((a, b) => dict[a].localeCompare(dict[b], "zh"));
const out = {};
keys.forEach((k, i) => {
  out[k] = i;
});
fs.writeFileSync(`${root}/editor/locale/westring_name_sort_zh.json`, JSON.stringify(out));
console.log("keys", keys.length);
console.log("first", keys.slice(0, 8).map((k) => dict[k]));
