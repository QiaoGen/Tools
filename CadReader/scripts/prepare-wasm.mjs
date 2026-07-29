import { copyFile, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const outputDir = join(projectRoot, 'public', 'wasm');
const packageRoot = dirname(require.resolve('@flyfish-dev/cad-viewer/package.json'));

const assets = [
  'libredwg-web.js',
  'libredwg-web.wasm',
  'dwg-worker.js'
];

await mkdir(outputDir, { recursive: true });

for (const asset of assets) {
  await copyFile(join(packageRoot, 'dist', 'wasm', asset), join(outputDir, asset));
}

console.log(`Prepared ${assets.length} DWG runtime assets.`);
