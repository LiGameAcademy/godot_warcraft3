import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {inventory} from '../src/asset-audit.js';
import {collectRuntimeAssetReferences} from '../src/runtime-asset-references.js';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const raw = path.join(repo, 'assets/.staging/wc3-assets');
const dataFiles = inventory(raw).filter(name => /^(Units|TerrainArt|Doodads|Splats|UI)\//i.test(name)
  && /\.(slk|txt)$/i.test(name));
if (!dataFiles.includes('Units/AbilityBuffData.slk')) dataFiles.push('Units/AbilityBuffData.slk');
const runtime = collectRuntimeAssetReferences(['packages/map', 'packages/gameplay', 'apps/game/app', 'apps/game/client']
  .map(root => path.join(repo, root)));
const references = runtime.refs.map(({logical}) => logical);
const request = {
  request_version: 1,
  models: JSON.parse(fs.readFileSync(path.join(repo, 'apps/game/config/asset_import_samples.source'))).models,
  development_map: {
    path: 'Maps/FrozenThrone/(2)EchoIsles.w3x',
    slug: 'echoisles',
    seeds: ['hpea', 'htow'],
    asset_aliases: [
      {requested: 'ReplaceableTextures/CommandButtons/BTNBuild.blp', selected: 'ReplaceableTextures/CommandButtons/BTNHumanBuild.blp'},
      {requested: 'ReplaceableTextures/CommandButtonsDisabled/DISBTNBuild.blp', selected: 'ReplaceableTextures/CommandButtonsDisabled/DISBTNHumanBuild.blp'},
    ],
    data_files: dataFiles.sort(),
    runtime_references: [...new Set(references)].sort(),
    texture_prefixes: ['UI/', 'ReplaceableTextures/', 'TerrainArt/LordaeronSummer/', 'Textures/'],
  },
};
const output = path.join(repo, 'apps/game/config/development_asset_request.source');
fs.writeFileSync(output, JSON.stringify(request, null, 2) + '\n');
console.log(JSON.stringify({output, data_files: dataFiles.length, runtime_references: references.length}));
