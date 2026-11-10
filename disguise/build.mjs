import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const stockPath = 'D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack';
const mainPath = 'script\\talkhammer\\main.lua';
const worldPath = 'script\\talkhammer\\lib\\world.lua';
const modulePath = 'script\\talkhammer\\lib\\changeling_mask.lua';
const exposurePath = 'script\\talkhammer\\lib\\mask_exposure.lua';
const panelPath = 'script\\talkhammer\\lib\\mask_panel.lua';
const layoutPath = 'ui\\talkhammer\\th_panel.twui.xml';
const output = fileURLToPath(new URL('./00_talkhammer_true_changeling_roleplay.pack', import.meta.url));

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

function addPanelButtons(layout) {
  const hierarchy = layout.match(/<th_accept this="[^"]+"\s*\/>/g);
  const definitions = layout.match(/<th_accept\r?\n[^>]*>[\s\S]*?<\/th_accept>/g);
  if (hierarchy?.length !== 1 || definitions?.length !== 1 ||
      !definitions[0].includes('id="th_accept"') || !definitions[0].includes('offset="368.00,454.00"') ||
      !definitions[0].includes('width="560"')) {
    throw new Error('The installed TalkHammer no longer matches the panel button layout');
  }
  const links = [], components = [];
  for (const [id, x, width] of [
    ['th_mask_toggle', 20, 196],
    ['th_mask_explain', 368, 178],
    ['th_mask_withdraw', 554, 178],
    ['th_mask_insist', 740, 188],
  ]) {
    function clone(text) {
      return text.replaceAll('th_accept', id)
        .replace(/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{16}/g, (guid) => {
          const hex = createHash('sha256').update(id + guid).digest('hex').slice(0, 32).toUpperCase();
          return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16)}`;
        });
    }
    links.push(clone(hierarchy[0]));
    components.push(clone(definitions[0])
      .replace('offset="368.00,454.00"', `offset="${x}.00,454.00"`)
      .replaceAll('width="560"', `width="${width}"`));
  }
  return layout.replace(hierarchy[0], [hierarchy[0], ...links].join('\r\n\t\t\t\t'))
    .replace(definitions[0], [definitions[0], ...components].join('\r\n\t\t'));
}

const original = unpack(await readFile(process.argv[2] ?? stockPath));
const mainEntry = original.get(mainPath);
const worldEntry = original.get(worldPath);
const layoutEntry = original.get(layoutPath);
if (!mainEntry || mainEntry.compressed) throw new Error(`Missing uncompressed ${mainPath} in TalkHammer`);
if (!worldEntry || worldEntry.compressed) throw new Error('Missing uncompressed TalkHammer world module');
if (!layoutEntry || layoutEntry.compressed) throw new Error('Missing uncompressed TalkHammer conversation layout');
const main = mainEntry.content.toString('utf8');
const world = worldEntry.content.toString('utf8');
const tradeReader = '{ "trade agreement", "faction_has_trade_agreement_with_faction", "cm" }';
const nativeTradeReader = '{ "trade agreement", "trade_agreement_with", "faction" }';
if (world.split(tradeReader).length !== 2) {
  throw new Error('The installed TalkHammer no longer matches the trade reader hook');
}
const leaderCache = /(^[ \t]*)(f\.leader = world\.leader_name\(key\))(\r?\n)(?=[ \t]*list\[#list \+ 1\])/gm;
if ([...world.matchAll(leaderCache)].length !== 1) {
  throw new Error('The installed TalkHammer no longer matches the faction snapshot hook');
}
const hook = 'voices.load(function(ok)';
const speakHook = 'local typed = ui.compose_take()';
if (main.split(hook).length !== 2 || main.split(speakHook).length !== 2 ||
    !main.includes('ruler.init({ p2 = p2') || !main.includes('parley.init({ state = state')) {
  throw new Error('The installed TalkHammer no longer matches the add-on hook');
}
const patch = `do
    local mask = load_module("talkhammer/lib/changeling_mask.lua")
    local exposure = load_module("talkhammer/lib/mask_exposure.lua")
    local panel = load_module("talkhammer/lib/mask_panel.lua")
    if mask and exposure and parley and orders then
        local ok, error = pcall(mask.install, {
            ruler = ruler, state = state, world = world, parley = parley,
            actions = actions, orders = orders, terms = terms, lang = lang, p2 = p2, json = json, exposure = exposure,
            ui = ui, panel = panel,
        })
        if not ok then log("MASK|install failed: " .. tostring(error)) end
    end
end

`;
const entries = [
  [modulePath, await readFile(new URL('./mask.lua', import.meta.url))],
  [exposurePath, await readFile(new URL('./mask_exposure.lua', import.meta.url))],
  [panelPath, await readFile(new URL('./mask_panel.lua', import.meta.url))],
  [layoutPath, Buffer.from(addPanelButtons(layoutEntry.content.toString('utf8')), 'utf8')],
  [mainPath, Buffer.from(main.replace(hook, patch + hook).replace(speakHook,
    'if ruler.mask_speak_ready and not ruler.mask_speak_ready() then return end\r\n' + speakHook), 'utf8')],
  [worldPath, Buffer.from(world.replace(leaderCache, '$1$2$3$1f.leader_subtype = subtype$3')
    .replace(tradeReader, nativeTradeReader), 'utf8')],
];
const result = pack(entries);
const decoded = unpack(result);
if (decoded.size !== entries.length || entries.some(([name, data]) => !decoded.get(name)?.content.equals(data))) {
  throw new Error('Failed to verify the generated pack');
}
await writeFile(output, result);
console.log(output);
