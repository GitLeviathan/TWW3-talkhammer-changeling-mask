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
local actions = { blocked = false, CONCLUDE = {} }
local pacts, access, alliances, trades, wars, absorbed = {}, {}, {}, {}, {}, {}
local engine_accepts = true
local function conclude(action, agreements, value)
    return function(from, to)
        applied = { action, from, to }
        if engine_accepts then agreements[from .. "|" .. to] = value end
        return true
    end
end
actions.CONCLUDE["non aggression pact"] = conclude("non_aggression", pacts, true)
actions.CONCLUDE["soft military access"] = conclude("military_access", access, true)
local break_alliance = conclude("break_alliance", alliances, false)
local state = {
    data = {},
    setting = function(key, fallback) if settings[key] == nil then return fallback end return settings[key] end,
    set_setting = function(key, value) settings[key] = value end,
    load_faction_sheet = function() end,
    character_of = function() return "experienced diplomat" end,
    save = function() end,
}
local at_war = true
local applied_actions = {}
local failed_outcome
local parley = { apply = function(action, from, to)
    if action == failed_outcome then return false end
    applied = { action, from, to }
    applied_actions[#applied_actions + 1] = action
    if action == "peace" then at_war = false end
    if action == "war" then wars[from .. "|" .. to] = true end
    return true
end }
local world = { keys = { "reikland", "kislev", "gelt" },
    factions = { reikland = { leader_subtype = "emp_karl_franz" }, kislev = { leader_subtype = "ksl_katarin", subculture = "emp" }, gelt = { subculture = "emp" }, reikland_enemy = {} },
    exists = function(key) return factions[key] or key == "reikland_enemy" end,
    resolve = function(name) if name == "Enemy" then return "reikland_enemy" end end, attitude = function() return -60 end }
local orders = { at_war = function(a, b) if a == "reikland_enemy" or b == "reikland_enemy" then return wars[a .. "|" .. b] == true end; return at_war end }
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
            key = key,
            non_aggression_pact_with = function(_, other) return pacts[key .. "|" .. other.key] == true end,
            military_access_pact_with = function(_, other) return access[key .. "|" .. other.key] == true end,
            allied_with = function(_, other) return not not alliances[key .. "|" .. other.key] end,
            is_null_interface = function() return false end,
            trade_agreement_with = function(_, other) return trades[key .. "|" .. other.key] == true end,
            at_war_with = function(_, other) return wars[key .. "|" .. other.key] == true end,
            is_dead = function() return absorbed[key] == true end,
            faction_leader = function()
                return { is_null_interface = function() return false end,
                    character_subtype_key = function() return key == owner and is_leader and form or "other" end }
            end,
        }
    end,
    force_non_aggression_pact = function() end,
    force_grant_military_access = function() end,
    force_break_non_aggression_pact = function(_, from, to, dissolved)
        assert(dissolved == false); conclude("break_non_aggression", pacts, false)(from, to)
    end,
    force_break_military_access = function(_, from, to, dissolved, hard)
        assert(dissolved == false and hard == false); conclude("break_military_access", access, false)(from, to)
    end,
    force_break_trade_agreement = function(_, from, to) conclude("break_trade", trades, false)(from, to) end,
    force_confederation = function(_, from, to)
        applied = { "confederation", from, to }; if engine_accepts then absorbed[to] = true end
    end,
    force_break_alliance = function(_, from, to) return break_alliance(from, to) end,
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
    index_of = function(text, needle, from) return native_find(text, needle, from or 1, true) end,
    sub = native_sub, lower = string.lower,
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
    callback(nil, { choices = { { message = { content = { line = line or "Agreed.", outcomes = type(outcome) == "table" and outcome or { outcome } } } } } })
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
for _, key in ipairs(faction_reads) do
    assert(key == "reikland" or key == "gelt", "Masked dialogue read an unrelated live faction")
end

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

local function has_outcome(wanted)
    for _, outcome in ipairs(queued.request.response_format.json_schema.schema.properties.outcomes.items.enum) do
        if outcome == wanted then return true end
    end
    return false
end

form, owner, at_war = "ksl_katarin", "kislev", false
equip()
ruler.talk_to("gelt", "Let us sign a non-aggression pact.")
assert(has_outcome("non_aggression"), "A new pact is unavailable in peacetime")
assert(has_outcome("military_access"), "Military access is unavailable in peacetime")
assert(not has_outcome("break_alliance"), "Alliance break was offered without an alliance")
reply("non_aggression")
assert_pair("non_aggression", "gelt", "kislev")
assert(last:find("Заключён договор о ненападении.", 1, true))

ruler.talk_to("gelt", "Grant Kislev military access.")
assert(not has_outcome("non_aggression"), "An existing pact was offered again")
reply("military_access")
assert_pair("military_access", "gelt", "kislev")

for _, alliance in ipairs({ "defensive", "military" }) do
    alliances["gelt|kislev"] = alliance
    ruler.talk_to("gelt", "Break your alliance with Kislev.")
    assert(has_outcome("break_alliance"), "An existing alliance could not be broken")
    assert(not has_outcome("military_access"), "Existing access was offered again")
    reply("break_alliance")
    assert_pair("break_alliance", "gelt", "kislev")
    assert(last:find("Союз расторгнут.", 1, true))
end

access["gelt|kislev"] = false
engine_accepts = false
ruler.talk_to("gelt", "Grant Kislev access again.")
reply("military_access")
assert_pair("military_access", "gelt", "kislev")
assert(last:find("Игра не подтвердила изменение договора.", 1, true), "A refused treaty was reported as successful")
engine_accepts = true

applied = nil
ruler.talk_to("gelt", "Grant Kislev access again.")
at_war = true
reply("military_access")
assert(not applied, "A deal was applied after war began")
ruler.talk_to("gelt", "Can we sign treaties in wartime?")
assert(has_outcome("military_access") and not has_outcome("break_alliance"))
reply("military_access")
assert(not applied, "A post-peace outcome was applied without peace")

at_war = false
actions.blocked = true
alliances["gelt|kislev"] = "military"
ruler.talk_to("gelt", "Break your alliance with Kislev.")
assert(not has_outcome("break_alliance"), "Alliance break bypassed /apply off")
reply("break_alliance")
assert(not applied, "A blocked alliance was broken")

actions.blocked = false
world.factions.gelt.is_human = true
ruler.talk_to("gelt", "Break your alliance with Kislev.")
assert(not has_outcome("break_alliance"), "Alliance break was offered against a human faction")
reply("break_alliance")
assert(not applied, "A human faction was affected by a masked treaty")

world.factions.gelt.is_human = false
ruler.talk_to("gelt", "Kislev declares war.")
assert(has_outcome("declare_war"), "The visitor cannot declare war")
reply("declare_war")
assert_pair("war", "kislev", "gelt")

ruler.talk_to("gelt", "Kislev grants you military access.")
reply("grant_military_access")
assert_pair("military_access", "kislev", "gelt")
trades["gelt|kislev"], access["gelt|kislev"] = true, true
for _, outcome in ipairs({ "break_non_aggression", "break_trade", "break_military_access_incoming", "break_military_access_outgoing" }) do
    ruler.talk_to("gelt", "Cancel this agreement.")
    assert(has_outcome(outcome), "Existing agreement cannot be cancelled: " .. outcome)
    reply(outcome)
end
assert_pair("break_military_access", "kislev", "gelt")
assert(not pacts["gelt|kislev"] and not trades["gelt|kislev"] and not access["gelt|kislev"] and not access["kislev|gelt"])

ruler.talk_to("gelt", "Attack them. [цель: unknown]")
assert(not queued, "An unknown third faction reached Codex")
ruler.talk_to("gelt", "Attack them. [цель: Enemy] [цель: reikland]")
assert(not queued, "An ambiguous third faction reached Codex")
ruler.talk_to("gelt", "Attack Enemy.")
assert(not has_outcome("attack_third"), "The model received an unconfirmed third party")
reply("none")
ruler.talk_to("gelt", "Attack them. [цель: Enemy]")
assert(has_outcome("attack_third"), "Named third-party attack is unavailable")
reply("attack_third")
assert_pair("war", "gelt", "reikland_enemy")
ruler.talk_to("gelt", "Kislev will join your war. [цель: Enemy]")
assert(has_outcome("join_recipient_war"), "The visitor cannot join the recipient war")
reply("join_recipient_war")
assert_pair("war", "kislev", "reikland_enemy")
wars["gelt|reikland_enemy"] = false
ruler.talk_to("gelt", "Join our war. [цель: Enemy]")
assert(has_outcome("join_visitor_war"), "The recipient cannot join the visitor war")
reply("join_visitor_war")
assert_pair("war", "gelt", "reikland_enemy")

at_war, applied_actions = true, {}
ruler.talk_to("gelt", "Peace in exchange for trade.")
assert(has_outcome("peace") and has_outcome("trade"), "A peace-and-trade package was not offered")
reply({"trade", "peace"})
assert(table.concat(applied_actions, "|") == "peace|trade", "Peace was not applied before trade")

applied, applied_actions = nil, {}
ruler.talk_to("gelt", "Conclude an alliance and declare war on us.")
reply({"alliance", "declare_war"})
assert(not applied and #applied_actions == 0, "A contradictory package was applied")

at_war, applied_actions, failed_outcome = true, {}, "trade"
ruler.talk_to("gelt", "Peace and trade.")
reply({"peace", "trade"})
assert(table.concat(applied_actions, "|") == "peace", "Partial settlement was not preserved")
assert(last:find("частично", 1, true), "Partial settlement was not reported")
failed_outcome = nil

ruler.talk_to("gelt", "Hello.")
assert(not has_outcome("confederate"), "Confederation was offered without a request")
reply("none")
world.factions.gelt.subculture = "other"
ruler.talk_to("gelt", "Join the confederation of Kislev.")
assert(not has_outcome("confederate"), "Confederation was offered across subcultures")
reply("none")
world.factions.gelt.subculture = "emp"
ruler.talk_to("gelt", "Join the confederation of Kislev.")
assert(has_outcome("confederate"), "Same-subculture confederation was unavailable")
reply("confederate")
assert_pair("confederation", "kislev", "gelt")
absorbed.gelt = nil
ruler.talk_to("gelt", "Kislev will join your confederation.")
reply("join_confederation")
assert_pair("confederation", "gelt", "kislev")

print("Mask diplomacy tests passed")
