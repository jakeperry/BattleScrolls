-----------------------------------------------------------
-- Tooltips (keyboard)
-- Renders the shared TooltipDescriptor shapes into the
-- keyboard InformationTooltip / ItemTooltip.
--
-- The gamepad side of this lives in chronicler.lua and draws
-- into GAMEPAD_LEFT_TOOLTIP. Both consume the same descriptors
-- produced by the renderers, so nothing shared changes.
--
-- See the TooltipDescriptor alias in entry_builder.lua for the
-- full set of shapes.
-----------------------------------------------------------

if not SemisPlaygroundCheckAccess() then
    return
end

if not IsKeyboardUISupported() then
    return
end

BattleScrolls = BattleScrolls or {}
BattleScrolls.journal = BattleScrolls.journal or {}

local journal = BattleScrolls.journal
journal.keyboard = journal.keyboard or {}

local ICON_SIZE = 24

local tooltipsKB = {}

---@return number r, number g, number b
local function normalColor()
    return ZO_NORMAL_TEXT:UnpackRGB()
end

---@return number r, number g, number b
local function highlightColor()
    return ZO_SELECTED_TEXT:UnpackRGB()
end

---Adds "icon  label" with an optional right-hand value.
---@param label string
---@param icon string|nil
---@param value string|nil
---@param highlighted boolean|nil
local function addIconLine(label, icon, value, highlighted)
    local text = label or ""
    if icon and icon ~= "" then
        text = zo_iconTextFormat(icon, ICON_SIZE, ICON_SIZE, text)
    end
    if value then
        text = string.format("%s  |cFFFFFF%s|r", text, value)
    end
    local r, g, b = normalColor()
    if highlighted then
        r, g, b = highlightColor()
    end
    InformationTooltip:AddLine(text, "", r, g, b)
end

---@param title string|nil
local function addTitle(title)
    if not title or title == "" then return end
    local r, g, b = highlightColor()
    InformationTooltip:AddLine(title, "ZoFontHeader2", r, g, b)
end

-------------------------
-- Descriptor renderers
-------------------------

---@param descriptor table
local function renderText(descriptor)
    addTitle(descriptor.title)
    if descriptor.text and descriptor.text ~= "" then
        ZO_Tooltip_AddDivider(InformationTooltip)
        local r, g, b = normalColor()
        InformationTooltip:AddLine(descriptor.text, "", r, g, b, TOPLEFT, MODIFY_TEXT_TYPE_NONE,
            TEXT_ALIGN_LEFT, true)
    end
end

---@param descriptor table
local function renderDetailRows(descriptor)
    addTitle(descriptor.title)
    if descriptor.subtitle then
        local r, g, b = normalColor()
        InformationTooltip:AddLine(descriptor.subtitle, "", r, g, b)
    end
    if descriptor.rows and #descriptor.rows > 0 then
        ZO_Tooltip_AddDivider(InformationTooltip)
        for _, row in ipairs(descriptor.rows) do
            addIconLine(row.label, row.icon, row.value, row.isHighlighted)
        end
    end
end

---@param descriptor table
local function renderAbilityList(descriptor)
    addTitle(descriptor.title)
    if not descriptor.abilities or #descriptor.abilities == 0 then return end
    ZO_Tooltip_AddDivider(InformationTooltip)
    for _, ability in ipairs(descriptor.abilities) do
        local name = GetAbilityName(ability.abilityId)
        local icon = GetAbilityIcon(ability.abilityId)
        addIconLine(zo_strformat(SI_ABILITY_NAME, name), icon, nil, ability.isUltimate)
        if ability.scripts then
            for _, script in ipairs(ability.scripts) do
                addIconLine("  " .. script.name, script.icon)
            end
        end
    end
end

---@param descriptor table
local function renderIconList(descriptor)
    addTitle(descriptor.title)

    local function addRows(rows)
        for _, row in ipairs(rows) do
            if row.abilityId then
                addIconLine(zo_strformat(SI_ABILITY_NAME, GetAbilityName(row.abilityId)),
                    GetAbilityIcon(row.abilityId))
            else
                addIconLine(row.label, row.icon)
            end
        end
    end

    if descriptor.groups then
        for _, group in ipairs(descriptor.groups) do
            ZO_Tooltip_AddDivider(InformationTooltip)
            addIconLine(group.headerLabel, group.headerIcon, nil, true)
            addRows(group.rows or {})
        end
    elseif descriptor.rows then
        ZO_Tooltip_AddDivider(InformationTooltip)
        addRows(descriptor.rows)
    end
end

---Renders the group comparison as an aligned text table. The member rows are
---built by the journal (which owns the decode state) and handed over here; see
---JournalKeyboard:BuildGroupTableDescriptor.
---@param descriptor table
local function renderGroupTable(descriptor)
    addTitle(descriptor.title or GetString(BATTLESCROLLS_TAB_GROUP))

    local members = descriptor.members
    if not members or #members == 0 then return end

    ZO_Tooltip_AddDivider(InformationTooltip)

    local r, g, b = normalColor()
    local hr, hg, hb = highlightColor()

    -- Fixed-width columns so the values line up in a proportional font as well
    -- as they reasonably can. The name column is truncated rather than wrapped.
    local function row(name, dps, crit, dtps, hps, alive)
        return string.format("%-20.20s %10s %7s %9s %9s %7s",
            name, dps, crit, dtps, hps, alive)
    end

    InformationTooltip:AddLine(
        row(GetString(BATTLESCROLLS_GROUP_COL_NAME), GetString(BATTLESCROLLS_STAT_DPS),
            GetString(BATTLESCROLLS_GROUP_COL_CRIT), GetString(BATTLESCROLLS_STAT_DTPS),
            GetString(BATTLESCROLLS_STAT_HPS), GetString(BATTLESCROLLS_GROUP_COL_ALIVE)),
        "ZoFontGameSmall", hr, hg, hb)

    for _, member in ipairs(members) do
        -- Your own row is highlighted, matching the gamepad table.
        local mr, mg, mb = r, g, b
        if member.isLocal then
            mr, mg, mb = hr, hg, hb
        end
        InformationTooltip:AddLine(
            row(member.name, member.dps, member.crit, member.dtps, member.hps, member.alive),
            "ZoFontGameSmall", mr, mg, mb)
    end
end

-- Shapes whose gamepad rendering is a full custom panel with no keyboard
-- equivalent. Panel specs are handled by ui/journal/keyboard/panel_kb.lua and
-- never reach here.
---@param descriptor table
local function renderUnsupported(descriptor)
    addTitle(descriptor.title or GetString(BATTLESCROLLS_TAB_OVERVIEW))
end

local RENDERERS = {
    text = renderText,
    detailRows = renderDetailRows,
    abilityList = renderAbilityList,
    iconList = renderIconList,
    groupTable = renderGroupTable,
    panel = renderUnsupported,
    vengeancePerk = renderUnsupported,
}

-------------------------
-- Public API
-------------------------

---Shows the tooltip for an entry next to the given control.
---@param control Control Row control to anchor against
---@param descriptor table|nil TooltipDescriptor, nil hides the tooltip
function tooltipsKB.Show(control, descriptor)
    tooltipsKB.Hide()
    if not descriptor or not descriptor.type then return end

    if descriptor.type == "item" then
        if not descriptor.itemLink then return end
        InitializeTooltip(ItemTooltip, control, RIGHT, -15, 0, LEFT)
        ItemTooltip:SetLink(descriptor.itemLink)
        return
    end

    local renderer = RENDERERS[descriptor.type]
    if not renderer then return end

    InitializeTooltip(InformationTooltip, control, RIGHT, -15, 0, LEFT)
    renderer(descriptor)
end

---Hides whichever tooltip is showing.
function tooltipsKB.Hide()
    ClearTooltip(InformationTooltip)
    ClearTooltip(ItemTooltip)
end

journal.keyboard.tooltips = tooltipsKB
