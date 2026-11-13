import { readFile, writeFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const catalogs = await Promise.all(['StateRenderCatalog', 'StateRenderSupplementalCatalog'].map(name => readFile(resolve(root, 'Upshot', `${name}.swift`), 'utf8')));
const names = new Set(catalogs.flatMap(text => [...text.matchAll(/"([A-Z][A-Za-z]+)"/g)].map(match => match[1])));
const locations = [];
for (const name of [...names].sort()) {
    const source = `Upshot/${name}.swift`;
    try { await access(resolve(root, source)); } catch { continue; }
    const lines = (await readFile(resolve(root, source), 'utf8')).split('\n');
    const matches = lines.flatMap((text, index) => /\b(struct|class|enum)\s|NSAlert\(\)|\.alert\(|private var nameEditor/.test(text)
        ? [`        (${JSON.stringify(text.trim())}, ${index + 1}),`]
        : []);
    locations.push(`        ${JSON.stringify(source)}: [\n${matches.map(line => '    ' + line).join('\n')}\n        ],`);
}
const swift = `import Foundation\n\nenum StateRenderSource {\n    private static let locations: [String: [(String, Int)]] = [\n${locations.join('\n')}\n    ]\n\n    static func line(in file: String, containing marker: String) -> Int {\n        locations[file]?.first(where: { $0.0.contains(marker) })?.1\n            ?? locations[file]?.first(where: { $0.0.contains(".alert(") })?.1\n            ?? locations[file]?.first?.1\n            ?? 1\n    }\n}\n`;
await writeFile(resolve(root, 'Upshot/StateRenderSource.swift'), swift);
console.log(`Updated render-state source locations for ${locations.length} source files.`);
