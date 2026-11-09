local addon = ...
if type(addon) ~= "table" then addon = dofile("disguise/mask.lua") end
local player = "wh3_dlc24_tze_the_deceivers"
local form, owner, is_leader = "emp_karl_franz", "reikland", true
local turn, queued, applied, last, ordinary = 7, nil, nil, nil, 0
local listeners, scheduled, in_diplomacy, context_reads = {}, nil, false, 0
local faction_reads = {}
local factions = { [player] = true, reikland = true, gelt = true, kislev = true }
local ruler = {
    COMMANDS = {}, awaiting = {},
    talk_to = function() ordinary = ordinary + 1 end,
    handle_command = function() end,
    report = function(title, lines) last = table.concat(lines, "\n") end,
    publish_status = function() end,
    label_for = function(key) return key end,
    identity = function(key) return key end,
    snapshot = function(key) return { ok = factions[key], key = key, turn = turn } end,
    describe = function(snapshot) return snapshot.key end,
    persona_block = function() return "proud and cautious" end,
}
local settings = {}
local actions = { blocked = false }
local state = {
    data = {},
    setting = function(key, fallback) if settings[key] == nil then return fallback end return settings[key] end,
    set_setting = function(key, value) settings[key] = value end,
    load_faction_sheet = function() end,
    character_of = function() return "experienced diplomat" end,
    save = function() end,
}
local at_war = true
local parley = { apply = function(action, from, to) applied = { action, from, to }; return true end }
local world = { keys = { "reikland", "kislev", "gelt" },
    factions = { reikland = { leader_subtype = "emp_karl_franz" }, kislev = { leader_subtype = "ksl_katarin" } },
    exists = function(key) return factions[key] end, attitude = function() return -60 end }
local orders = { at_war = function() return at_war end }
local function value(kind, key, field)
    context_reads = context_reads + 1
    assert(not in_diplomacy, "Form UI was queried while diplomacy was open")
    assert(kind == "CcoCampaignFaction" and key == player)
    if field == "EquippedShapeshiftFormContext.AgentSubtypeRecordContext.Key" then return form end
    error("Unexpected context query: " .. field)
end
local cm = {
    get_local_faction_name = function() return player end,
    turn_number = function() return turn end,
    callback = function(_, callback) scheduled = callback end,
    get_faction = function(_, key)
        faction_reads[#faction_reads + 1] = key
        return {
            is_null_interface = function() return false end,
            is_dead = function() return false end,
            faction_leader = function()
                return { is_null_interface = function() return false end,
                    character_subtype_key = function() return key == owner and is_leader and form or "other" end }
            end,
        }
    end,
    apply_dilemma_diplomatic_bonus = function(_, from, to, bonus) applied = { bonus, from, to } end,
}
local p2 = { post = function(path, request, callback)
    assert(path == "/chat/completions")
    queued = { request = request, callback = callback }
    return "r001"
end }
local core = { add_listener = function(_, id, event, condition, callback)
    listeners[event] = { condition = condition, callback = callback }
end }

local native_find, native_match, native_sub = string.find, string.match, string.sub
local u8 = TALKHAMMER_U8 or {
    index_of = function(text, needle) return native_find(text, needle, 1, true) end,
    sub = native_sub,
}
addon.install({
    u8 = u8, cm = cm, core = core, context_value = value, ruler = ruler, state = state, actions = actions,
    world = world, parley = parley, orders = orders, p2 = p2,
    json = { decode = function(content) return content end },
})

local function dispatch(event, name)
    local listener = listeners[event]
    local context = { string = name }
    if listener and listener.condition(context) then listener.callback(context) end
end

local function refresh()
    if scheduled then local callback = scheduled; scheduled = nil; callback() end
end

local function unsafe_pattern() error("The add-on used a native Lua pattern function") end
string.find, string.match = unsafe_pattern, unsafe_pattern
refresh()
in_diplomacy = true
dispatch("PanelOpenedCampaign", "diplomacy_dropdown")
local reads_before = context_reads
ruler.handle_command({ cmd = "mask", text = " \t" })
string.find, string.match = native_find, native_match
assert(context_reads == reads_before, "/mask queried game UI contexts inside diplomacy")
assert(#faction_reads == 1 and faction_reads[1] == "reikland", "/mask read unrelated live factions")
assert(last:find("emp_karl_franz", 1, true), "/mask did not show the equipped form")

dispatch("ComponentLClickUp", "button_shapeshift")
refresh()
assert(context_reads == reads_before, "A form refresh ran while diplomacy was open")
in_diplomacy = false
dispatch("PanelClosedCampaign", "diplomacy_dropdown")
refresh()
assert(context_reads > reads_before, "Closing diplomacy did not refresh the equipped form")
in_diplomacy = true
dispatch("PanelOpenedCampaign", "diplomacy_dropdown")

local function equip()
    in_diplomacy = false
    dispatch("PanelClosedCampaign", "diplomacy_dropdown")
    dispatch("ComponentLClickUp", "button_shapeshift")
    refresh()
    in_diplomacy = true
    dispatch("PanelOpenedCampaign", "diplomacy_dropdown")
end

local function reply(outcome, line)
    local callback = assert(queued).callback
    queued = nil
    callback(nil, { choices = { { message = { content = { line = line or "Agreed.", outcome = outcome } } } } })
end
local function assert_pair(action, from, to)
    assert(applied and applied[1] == action and applied[2] == from and applied[3] == to,
        "Diplomacy used the wrong outcome or pair")
end

faction_reads = {}
ruler.talk_to("gelt", "Let us sign a peace treaty.")
assert(queued.request.response_format.json_schema.name == "changeling_mask_reply")
assert(string.find(queued.request.messages[2].content, "reikland", 1, true))
assert(not string.find(queued.request.messages[2].content, player, 1, true))
string.find, string.match = unsafe_pattern, unsafe_pattern
reply("peace", " \tСогласна.\r\n")
string.find, string.match = native_find, native_match
assert(last:find("\nСогласна.\n", 1, true), "The reply text was not trimmed")
assert_pair("peace", "reikland", "gelt")
assert(#faction_reads == 2 and faction_reads[1] == "reikland" and faction_reads[2] == "reikland",
    "Masked dialogue read unrelated live factions")

ruler.talk_to("gelt", "I withdraw our assurances.")
reply("cool")
assert_pair(-2, "reikland", "gelt")

applied = nil
ruler.talk_to("gelt", "I ask for a treaty.")
form, owner = "ksl_katarin", "kislev"
equip()
reply("peace")
assert(not applied, "A reply from a previous disguise was applied")

at_war = false
ruler.talk_to("gelt", "We now speak for Kislev.")
reply("war")
assert_pair("war", "gelt", "kislev")

applied = nil
at_war = true
actions.blocked = true
ruler.talk_to("gelt", "Will you accept peace?")
reply("peace")
assert(not applied, "TalkHammer /apply off was bypassed")
actions.blocked = false

is_leader = false
ruler.talk_to("gelt", "A hero should not commit any faction.")
assert(not queued and ordinary == 0)
is_leader = true
ruler.talk_to("kislev", "I cannot negotiate with my own faction.")
assert(not queued and ordinary == 0)

ruler.handle_command({ cmd = "mask", text = "off" })
ruler.talk_to("gelt", "This goes through normal TalkHammer.")
assert(ordinary == 1 and not queued)
ruler.handle_command({ cmd = "mask", text = "on" })
form = nil
equip()
ruler.talk_to("gelt", "No form selected.")
assert(ordinary == 2 and not queued)

print("Mask diplomacy tests passed")
