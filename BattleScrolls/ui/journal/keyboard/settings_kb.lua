-----------------------------------------------------------
-- Settings (keyboard)
-- Exposes the settings through LibAddonMenu-2.0, where PC
-- players expect to find addon settings.
--
-- No settings are redefined here. SettingsRenderer already
-- emits declarative rows -- text/header/tooltip plus
-- getFunction/setFunction closures -- and encodes the control
-- type in the gamepad template name it asks for. We feed it a
-- ListCollector and translate what it collects into LAM
-- descriptors, so the settings model stays in exactly one
-- place.
--
-- Template -> LAM control:
--   ZO_GamepadOptionsCheckboxRow[WithHeader] -> checkbox
--   ZO_GamepadHorizontalListRow[WithHeader]  -> dropdown
--   ZO_GamepadOptionsSliderRow               -> slider
--   ZO_GamepadOptionsLabelRow                -> description
-- A row's `header` field emits a LAM header before it.
--
-- Known limitation: LAM builds a panel's controls once per
-- session (optionsState == OPTIONS_CREATED) and will not
-- rebuild them. The gamepad list adds some rows conditionally
-- (e.g. meter offsets only while the personal meter is on), so
-- enabling such a feature reveals its dependent settings only
-- after a UI reload. Values themselves are always live, since
-- LAM re-reads getFunc whenever the panel is shown.
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

local PANEL_ID = "BattleScrollsOptions"

local settingsKB = {}

local panel = nil       ---@type table|nil
local registered = false

-------------------------
-- Row translation
-------------------------

---@param data table Row data from SettingsRenderer
---@return string|nil
local function tooltipText(data)
    local tooltip = data.tooltip
    if type(tooltip) == "string" then return tooltip end
    if type(tooltip) == "table" then
        -- SettingsRenderer builds { type = "text", title = ..., text = ... }
        return tooltip.text
    end
    return nil
end

---Builds a LAM dropdown from a row carrying `valid` values and `valueStrings`.
---LAM wants display strings in `choices` and the underlying values in
---`choicesValues`, matched by index.
---@param data table
---@return table|nil
local function toDropdown(data)
    local values = data.valid
    local labels = data.valueStrings
    if type(values) ~= "table" or type(labels) ~= "table" then
        return nil
    end

    local choices, choicesValues = {}, {}
    for i = 1, #values do
        choices[i] = labels[i] or tostring(values[i])
        choicesValues[i] = values[i]
    end

    return {
        type = "dropdown",
        name = data.text,
        tooltip = tooltipText(data),
        choices = choices,
        choicesValues = choicesValues,
        getFunc = data.getFunction,
        setFunc = function(value)
            if data.setFunction then data.setFunction(value) end
            if data.onChangeFunction then data.onChangeFunction() end
        end,
        width = "full",
    }
end

---@param data table
---@return table
local function toSlider(data)
    return {
        type = "slider",
        name = data.text,
        tooltip = tooltipText(data),
        min = data.minValue or 0,
        max = data.maxValue or 100,
        step = data.step or 1,
        getFunc = data.getFunction,
        setFunc = function(value)
            if data.setFunction then data.setFunction(value) end
            if data.onChangeFunction then data.onChangeFunction() end
        end,
        clampInput = true,
        width = "full",
    }
end

---@param data table
---@return table
local function toCheckbox(data)
    return {
        type = "checkbox",
        name = data.text,
        tooltip = tooltipText(data),
        getFunc = data.getFunction,
        setFunc = function(value)
            if data.setFunction then data.setFunction(value) end
            if data.onChangeFunction then data.onChangeFunction() end
        end,
        width = "full",
    }
end

---@param data table
---@return table
local function toDescription(data)
    return {
        type = "description",
        title = data.text,
        text = tooltipText(data) or "",
        width = "full",
    }
end

-- Template name -> converter. Header variants share a converter; the header
-- itself is emitted separately from the row's `header` field.
local CONVERTERS = {
    ["ZO_GamepadOptionsCheckboxRow"] = toCheckbox,
    ["ZO_GamepadOptionsCheckboxRowWithHeader"] = toCheckbox,
    ["ZO_GamepadHorizontalListRow"] = toDropdown,
    ["ZO_GamepadHorizontalListRowWithHeader"] = toDropdown,
    ["ZO_GamepadOptionsSliderRow"] = toSlider,
    ["ZO_GamepadOptionsLabelRow"] = toDescription,
}

-------------------------
-- Options table
-------------------------

---Runs SettingsRenderer against a collector and converts the result.
---@return table optionsTable
local function buildOptionsTable()
    local collector = journal.keyboard.ListCollector:New()

    -- SettingsRenderer asks for a refresh when a change would add or remove
    -- rows. LAM cannot rebuild an existing panel, so there is nothing useful to
    -- do here; see the limitation note at the top of this file.
    journal.renderers.settings.renderSettings(collector, function() end)

    local options = {}
    for _, item in ipairs(collector:GetEntries()) do
        local data = item.data

        if data.header then
            options[#options + 1] = { type = "header", name = data.header }
        end

        local converter = CONVERTERS[item.template]
        local control = converter and converter(data)
        if control then
            options[#options + 1] = control
        end
    end

    return options
end

-------------------------
-- Registration
-------------------------

---Registers the panel with LAM. Safe to call repeatedly.
---@return boolean registered
local function ensureRegistered()
    if registered then return true end

    local LAM = LibAddonMenu2
    if not LAM then return false end

    panel = LAM:RegisterAddonPanel(PANEL_ID, {
        type = "panel",
        name = GetString(BATTLESCROLLS_UI_NAME),
        displayName = GetString(BATTLESCROLLS_UI_NAME),
        author = "Semigroup1329",
        registerForRefresh = true,
        registerForDefaults = false,
    })
    LAM:RegisterOptionControls(PANEL_ID, buildOptionsTable())

    registered = true
    return true
end

-------------------------
-- Public API
-------------------------

---Opens the settings panel. Called from the keyboard journal's Settings row.
---@return boolean opened
function settingsKB.Open()
    if not ensureRegistered() then
        return false
    end

    -- Close the journal first: LAM lives in its own scene and the two windows
    -- would otherwise overlap.
    local journalUI = journal.keyboard.instance
    if journalUI and journalUI:IsShowing() then
        journalUI:Hide()
    end

    LibAddonMenu2:OpenToPanel(panel)
    return true
end

---@return boolean
function settingsKB.IsAvailable()
    return LibAddonMenu2 ~= nil
end

-- Register at load so the panel is listed under Settings > Addons even if the
-- journal is never opened.
EVENT_MANAGER:RegisterForEvent("BattleScrolls_KBSettings", EVENT_ADD_ON_LOADED,
    function(_, addonName)
        if addonName ~= "BattleScrolls" then return end
        EVENT_MANAGER:UnregisterForEvent("BattleScrolls_KBSettings", EVENT_ADD_ON_LOADED)
        -- Storage must be initialized before the renderer reads settings, and
        -- main.lua does that on this same event; defer a frame to be sure.
        zo_callLater(function() ensureRegistered() end, 0)
    end)

journal.keyboard.settings = settingsKB
