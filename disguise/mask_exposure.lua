local exposure = {}
local window = 5

local treaty_signed = {
    peace = "peace", trade = "trade", non_aggression = "pact",
    alliance = "alliance", defensive_alliance = "alliance",
}
local treaty_broken = {
    break_trade = "trade", break_non_aggression = "pact", break_alliance = "alliance",
}

local function recent(date, turn)
    return date and date <= turn and turn < date + window
end

function exposure.form_key(form)
    return form.subtype .. "|" .. form.faction
end

function exposure.pair(campaign, form_key, court)
    campaign.mask_diplomacy = campaign.mask_diplomacy or {}
    local key = form_key .. "|" .. court
    local records = campaign.mask_diplomacy
    records[key] = records[key] or { history = {} }
    return records[key]
end

function exposure.blocked_until(pair, turn)
    local until_turn = pair.exposed_until
    if until_turn and turn < until_turn then return until_turn end
end

function exposure.assess(pair, session, plan, allied)
    local result = { by_outcome = {}, clues = {}, local_count = 0 }
    local deeds, turn = pair.recent_deals or {}, session.turn
    for _, outcome in ipairs(plan) do
        if outcome ~= "none" and outcome ~= "warm" and outcome ~= "cool" then result.deal = true end
        local broken = treaty_broken[outcome]
        local clue
        if (outcome == "war" or outcome == "declare_war") and recent(deeds.peace, turn) then
            clue = "peace_reversed"
        elseif (outcome == "attack_third" or outcome == "join_recipient_war") and session.third
            and allied(session.form.faction, session.third) then
            clue = "ally_attacked"
        elseif broken and recent(deeds[broken], turn) then
            clue = "treaty_reversed"
        end
        if clue then
            result.by_outcome[outcome] = clue
            result.clues[clue] = true
        end
    end
    for clue, date in pairs(pair.clues or {}) do
        if recent(date, turn) then result.clues[clue] = true end
    end
    for _ in pairs(result.clues) do result.local_count = result.local_count + 1 end
    if result.deal and pair.warning and recent(pair.warning.turn, turn) then
        result.warning = pair.warning.source
    end
    return result
end

function exposure.record(pair, turn, outcome, clue)
    local treaty = treaty_signed[outcome]
    if treaty then
        pair.recent_deals = pair.recent_deals or {}
        pair.recent_deals[treaty] = turn
    end
    if clue then
        pair.clues = pair.clues or {}
        pair.clues[clue] = turn
    end
end

function exposure.expose(pair, session, assessment)
    pair.exposed_until = session.turn + window
    if assessment.local_count < 2 then return end

    local campaign, court_key = session.campaign, session.target
    campaign.mask_courts = campaign.mask_courts or {}
    local courts = campaign.mask_courts
    local court = courts[court_key] or { exposed = {} }
    courts[court_key] = court
    court.exposed[exposure.form_key(session.form)] = true
    if court.scandal then return end

    local forms = {}
    for form_key in pairs(court.exposed) do forms[#forms + 1] = form_key end
    if #forms == 2 then
        court.scandal = true
        table.sort(forms)
        return forms
    end
end

function exposure.warn(campaign, court, form_keys, source, turn)
    for _, form_key in ipairs(form_keys) do
        local pair = exposure.pair(campaign, form_key, court)
        pair.warning = { source = source, turn = turn }
    end
end

return exposure
