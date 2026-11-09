import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const stockPath = 'D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack';
const mainPath = 'script\\talkhammer\\main.lua';
const worldPath = 'script\\talkhammer\\lib\\world.lua';
const modulePath = 'script\\talkhammer\\lib\\changeling_mask.lua';
const output = fileURLToPath(new URL('./00_talkhammer_changeling_mask.pack', import.meta.url));

function unpack(buffer) {
  if (buffer.length < 28 || buffer.toString('ascii', 0, 4) !== 'PFH5' || buffer.readUInt32LE(4) !== 3) {
    throw new Error('Expected an unflagged PFH5 Mod pack');
  }
  const entries = new Map();
  let index = 28 + buffer.readUInt32LE(12);
  const dataStart = index + buffer.readUInt32LE(20);
  let offset = dataStart;
  const count = buffer.readUInt32LE(16);
  for (let i = 0; i < count; i++) {
    if (index + 5 >= dataStart) throw new Error('Truncated pack index');
    const size = buffer.readUInt32LE(index);
    const compressed = buffer[index + 4] !== 0;
    const end = buffer.indexOf(0, index + 5);
    if (end < 0 || end >= dataStart || offset + size > buffer.length) throw new Error('Invalid pack entry');
    const name = buffer.toString('utf8', index + 5, end);
    entries.set(name, { content: buffer.subarray(offset, offset + size), compressed });
    index = end + 1;
    offset += size;
  }
  if (index !== dataStart || offset !== buffer.length) throw new Error('Invalid pack boundaries');
  return entries;
}

function pack(entries) {
  const header = Buffer.alloc(28);
  header.write('PFH5');
  header.writeUInt32LE(3, 4); // Mod: selectable in the launcher
  header.writeUInt32LE(entries.length, 16);
  header.writeUInt32LE(Math.floor(Date.now() / 1000), 24);
  const index = Buffer.concat(entries.map(([name, content]) => {
    const metadata = Buffer.alloc(5); // size and the uncompressed marker
    metadata.writeUInt32LE(content.length);
    return Buffer.concat([metadata, Buffer.from(`${name}\0`)]);
  }));
  header.writeUInt32LE(index.length, 20);
  return Buffer.concat([header, index, ...entries.map((entry) => entry[1])]);
}

const original = unpack(await readFile(process.argv[2] ?? stockPath));
const mainEntry = original.get(mainPath);
const worldEntry = original.get(worldPath);
if (!mainEntry || mainEntry.compressed) throw new Error(`Missing uncompressed ${mainPath} in TalkHammer`);
if (!worldEntry || worldEntry.compressed) throw new Error('Missing uncompressed TalkHammer world module');
const main = mainEntry.content.toString('utf8');
const world = worldEntry.content.toString('utf8');
const leaderCache = /(^[ \t]*)(f\.leader = world\.leader_name\(key\))(\r?\n)(?=[ \t]*list\[#list \+ 1\])/gm;
if ([...world.matchAll(leaderCache)].length !== 1) {
  throw new Error('The installed TalkHammer no longer matches the faction snapshot hook');
}
const hook = 'voices.load(function(ok)';
if (main.split(hook).length !== 2 || !main.includes('ruler.init({ p2 = p2') || !main.includes('parley.init({ state = state')) {
  throw new Error('The installed TalkHammer no longer matches the add-on hook');
}
const patch = `do
    local mask = load_module("talkhammer/lib/changeling_mask.lua")
    if mask and parley and orders then
        local ok, error = pcall(mask.install, {
            ruler = ruler, state = state, world = world, parley = parley,
            actions = actions, orders = orders, terms = terms, lang = lang, p2 = p2, json = json,
        })
        if not ok then log("MASK|install failed: " .. tostring(error)) end
    end
end

`;
const entries = [
  [modulePath, await readFile(new URL('./mask.lua', import.meta.url))],
  [mainPath, Buffer.from(main.replace(hook, patch + hook), 'utf8')],
  [worldPath, Buffer.from(world.replace(leaderCache, '$1$2$3$1f.leader_subtype = subtype$3'), 'utf8')],
];
const result = pack(entries);
const decoded = unpack(result);
if (decoded.size !== entries.length || entries.some(([name, data]) => !decoded.get(name)?.content.equals(data))) {
  throw new Error('Failed to verify the generated pack');
}
await writeFile(output, result);
console.log(output);
