local panel = {}
local buttons = {
    toggle = { "th_mask_toggle" },
    explain = { "th_mask_explain", "Уточнить" },
    withdraw = { "th_mask_withdraw", "Отступить" },
    insist = { "th_mask_insist", "Настоять" },
}
local terms = {
    peace = "Мир", trade = "Торговое соглашение", non_aggression = "Пакт о ненападении",
    alliance = "Военный союз", defensive_alliance = "Оборонительный союз",
    military_access = "Военный доступ для фракции облика",
    grant_military_access = "Военный доступ для собеседника",
    break_military_access_incoming = "Отзыв доступа у фракции облика",
    break_military_access_outgoing = "Отзыв доступа у собеседника",
    break_alliance = "Разрыв союза", break_non_aggression = "Разрыв пакта", break_trade = "Разрыв торговли",
    war = "Объявление войны собеседником", declare_war = "Объявление войны фракцией облика",
    attack_third = "Нападение собеседника на третью фракцию",
    join_visitor_war = "Вступление собеседника в войну фракции облика",
    join_recipient_war = "Вступление фракции облика в войну собеседника",
    confederate = "Вступление собеседника в конфедерацию фракции облика",
    join_confederation = "Вступление фракции облика в конфедерацию собеседника",
    warm = "Улучшение отношений", cool = "Ухудшение отношений",
}

function panel.new(deps)
    local ui, ruler = deps.ui, deps.ruler
    if not ui or not ui.show_history then return end
    local u8 = deps.u8 or TALKHAMMER_U8
    local components, shown, root = {}, {}
    local view = {}

    function view.ready()
        return ui.label ~= nil
    end

    function view.in_news()
        return ui.mode == "news"
    end

    function view.visible()
        local frame = ui.frame or ui.panel
        if not frame then return false end
        local ok, visible = pcall(function() return frame:Visible() end)
        return ok and visible == true
    end

    local function set_button(mode, label)
        local button = components[mode]
        shown[mode] = nil
        if not button then return end
        local ok = pcall(function()
            if label then button:SetStateText(label) end
            button:SetVisible(label ~= nil)
        end)
        if ok then shown[mode] = label end
    end

    function view.controls(available, enabled, checking)
        set_button("toggle", available and (enabled and "Маска: вкл." or "Маска: выкл.") or nil)
        for mode, button in pairs(buttons) do
            if mode ~= "toggle" then set_button(mode, checking and button[2] or nil) end
        end
    end

    function view.command(id)
        if ui.mode ~= "talk" or not view.visible() then return end
        for mode, button in pairs(buttons) do
            if id == button[1] and shown[mode] then return mode end
        end
    end

    function view.take_text()
        if ui.compose_take then return ui.compose_take() end
        return ""
    end

    function view.describe_plan(plan, third)
        local lines = { "Условия на проверке" }
        for _, outcome in ipairs(plan) do lines[#lines + 1] = terms[outcome] or outcome end
        if third then lines[#lines + 1] = "Цель войны — " .. third end
        return table.concat(lines, "\n")
    end

    function view.hide_accept()
        ruler.accept_shown, ruler.accept_armed, ui.pending_accept = nil, nil, nil
        if ui.set_accept then ui.set_accept(nil) end
    end

    local original_init, original_clear = ui.init, ui.clear_ledger
    ui.init = function(...)
        local result = original_init(...)
        if root ~= ui.panel then
            root, components = ui.panel, {}
            if root and ui.deep_find then
                for mode, button in pairs(buttons) do components[mode] = ui.deep_find(root, button[1]) end
            end
            view.controls(false)
        end
        return result
    end
    if original_clear then
        ui.clear_ledger = function(...)
            local result = original_clear(...)
            if ui.mode ~= "talk" then set_button("toggle") end
            set_button("explain")
            set_button("withdraw")
            set_button("insist")
            return result
        end
    end

    local function append(lines, value)
        if not value or value == "" then return end
        local from = 1
        local stop = u8.index_of(value, "\n", from)
        while stop do
            lines[#lines + 1] = u8.sub(value, from, stop - 1)
            from = stop + 1
            stop = u8.index_of(value, "\n", from)
        end
        lines[#lines + 1] = u8.sub(value, from)
    end

    function view.render(data)
        local label = ruler.label_for(data.target)
        local lines = {}
        for _, entry in ipairs(data.history) do
            if type(entry) == "string" then
                append(lines, entry)
            else
                append(lines, data.identity .. " — " .. entry.text)
                append(lines, label .. " — " .. entry.reply)
                append(lines, entry.result)
            end
            lines[#lines + 1] = ""
        end
        if data.speech then append(lines, data.identity .. " — " .. data.speech) end
        if data.waiting then lines[#lines + 1] = label .. " обдумывает ответ…" end
        if #lines == 0 then lines[1] = data.fallback or "Введи реплику и нажми SPEAK." end
        if ui.has_ledger and not ui.has_ledger() then
            append(lines, data.deal)
            for _, note in ipairs(data.notice) do append(lines, note) end
        end

        ui.mode = "talk"
        view.hide_accept()
        ui.show_history("", lines, label)
        if ruler.update_news_label then ruler.update_news_label() end
        if ui.set_sub then ui.set_sub(data.identity and ("Под обликом — " .. data.identity) or "Маска включена") end
        if ruler.header_facts and ui.set_image then
            local ok, facts = pcall(ruler.header_facts, data.target)
            facts = ok and facts or {}
            ui.set_image("crest", facts.crest)
            ui.set_image("portrait", facts.portrait)
        end
        if ui.set_badge then
            ui.set_badge("att", "ОТНОШЕНИЕ\n" .. tostring(data.attitude or "—"))
            ui.set_badge("reg", "МАСКА\n" .. (data.blocked and "Раскрыта" or "Включена"))
            ui.set_badge("mood", "ПРОВЕРКА\n" .. (data.checking and "Идёт" or "—"))
        end
        local detail = table.concat(data.notice, "\n")
        local deal = data.deal or data.result or "Условий сделки пока нет."
        if ui.set_deal then ui.set_deal(deal) end
        if ui.set_ledger then ui.set_ledger(detail) end
        view.controls(true, true, data.checking)
    end
    return view
end

return panel
