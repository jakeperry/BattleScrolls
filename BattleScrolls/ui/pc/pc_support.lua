-----------------------------------------------------------
-- PC Support
-- Entry points that only exist on PC: slash commands and a
-- rebindable key for opening the journal.
--
-- The journal is built on ESO's gamepad UI framework, which
-- ships on PC too but only renders correctly while the client
-- is in Gamepad Mode. When a PC player in keyboard mode asks
-- for the journal we offer to flip the input mode for them and
-- put it back when they close the journal.
--
-- Console reaches the journal through the gamepad main menu
-- (see ui/journal/journal.lua AddToMainMenu), so nothing here
-- fires there: consoles have no chat input and ignore
-- Bindings.xml.
-----------------------------------------------------------

if not SemisPlaygroundCheckAccess() then
    return
end

BattleScrolls = BattleScrolls or {}

local JOURNAL_SCENE = "battleScrollsJournalGamepad"
local DIALOG_ID = "BATTLESCROLLS_GAMEPAD_MODE"

---@class BattleScrolls_PCSupport
local pcSupport = {}
BattleScrolls.pcSupport = pcSupport

-- Input mode to restore once the player is done, nil when we did not switch.
-- Holds the raw GetSetting value so it round-trips exactly.
local restoreMode = nil ---@type string|number|nil
-- Set once the journal has actually appeared, so the transient HUD frame during
-- the mode switch itself does not count as "the player is finished".
local restoreOwed = false
local restoreHooksRegistered = false

-------------------------
-- Platform probes
-------------------------

---Whether the client offers both interface modes (true on PC, false on console).
---@return boolean
local function isDualUISupported()
    return IsGamepadUISupported() and IsKeyboardUISupported()
end

---Whether we may flip the player's input mode.
---Accessibility mode pins the client to the gamepad interface, so leave it alone.
---@return boolean
local function canSwitchInputMode()
    if not isDualUISupported() then return false end
    return not GetSetting_Bool(SETTING_TYPE_ACCESSIBILITY, ACCESSIBILITY_SETTING_ACCESSIBILITY_MODE)
end

---The INPUT_PREFERRED_MODE value meaning "always gamepad".
---Guarded because the constant is absent on older API versions.
---@return number
local function gamepadModeValue()
    return INPUT_PREFERRED_MODE_ALWAYS_GAMEPAD or 1
end

-------------------------
-- Messaging
-------------------------

---Writes a system message to chat. No-op where chat does not exist.
---@param message string
local function notify(message)
    if CHAT_ROUTER then
        CHAT_ROUTER:AddSystemMessage(message)
    end
end

-------------------------
-- Input mode handling
-------------------------

---Restores the input mode we replaced, if any.
local function restoreInputMode()
    if restoreMode == nil then return end
    local mode = restoreMode
    restoreMode = nil
    restoreOwed = false
    SetSetting(SETTING_TYPE_GAMEPAD, GAMEPAD_SETTING_INPUT_PREFERRED_MODE, mode)
end

---Registers the listeners that hand the input mode back.
---
---We deliberately do not restore when the journal itself hides: the player can
---leave it for another gamepad screen (the main menu, the character sheet), and
---flipping back to keyboard mode there would break whatever they opened.
---Instead we wait until they are back in the world.
---@param scene table The journal scene
local function registerRestoreHooks(scene)
    if restoreHooksRegistered then return end
    restoreHooksRegistered = true

    scene:RegisterCallback("StateChange", function(_oldState, newState)
        if newState == SCENE_SHOWN then
            restoreOwed = true
        end
    end)

    local function onHudStateChange(_oldState, newState)
        if newState == SCENE_SHOWN and restoreOwed then
            restoreInputMode()
        end
    end

    HUD_SCENE:RegisterCallback("StateChange", onHudStateChange)
    HUD_UI_SCENE:RegisterCallback("StateChange", onHudStateChange)
end

---Switches to Gamepad Mode and opens the journal, remembering the old mode.
---@param scene table The journal scene
local function switchToGamepadModeAndOpen(scene)
    restoreMode = GetSetting(SETTING_TYPE_GAMEPAD, GAMEPAD_SETTING_INPUT_PREFERRED_MODE)
    restoreOwed = false
    registerRestoreHooks(scene)
    SetSetting(SETTING_TYPE_GAMEPAD, GAMEPAD_SETTING_INPUT_PREFERRED_MODE, gamepadModeValue())

    -- Changing the setting tears down the keyboard scene tree and stands up the
    -- gamepad one. Let that settle before pushing our scene onto it.
    zo_callLater(function()
        SCENE_MANAGER:Show(JOURNAL_SCENE)
    end, 50)
end

-------------------------
-- Gamepad Mode prompt
-------------------------

---Lazily creates the shared confirm dialog.
---@return table
local function getDialog()
    if not ESO_Dialogs[DIALOG_ID] then
        ESO_Dialogs[DIALOG_ID] = {
            canQueue = true,
            gamepadInfo = {
                dialogType = GAMEPAD_DIALOGS.CENTERED,
            },
            title = {
                text = GetString(BATTLESCROLLS_UI_NAME),
            },
            mainText = {
                text = GetString(BATTLESCROLLS_PC_GAMEPAD_MODE_PROMPT),
            },
            buttons = {
                [1] = {
                    text = GetString(BATTLESCROLLS_PC_SWITCH_AND_OPEN),
                    callback = function() end,
                },
                [2] = {
                    text = GetString(SI_DIALOG_CANCEL),
                },
            },
        }
    end
    return ESO_Dialogs[DIALOG_ID]
end

---Asks the player whether to switch interface modes.
---@param scene table The journal scene
local function promptForGamepadMode(scene)
    local dialog = getDialog()
    dialog.buttons[1].callback = function()
        switchToGamepadModeAndOpen(scene)
    end

    -- Only reached from keyboard mode, so the keyboard dialog is the right one.
    ZO_Dialogs_ShowDialog(DIALOG_ID)
end

-------------------------
-- Public entry point
-------------------------

---Opens the Battle Scrolls journal, handling PC interface modes.
---Safe to call at any time: the journal UI is built asynchronously a moment
---after load, and this reports that rather than erroring.
function pcSupport.OpenJournal()
    local scene = SCENE_MANAGER:GetScene(JOURNAL_SCENE)
    if not scene then
        notify(GetString(BATTLESCROLLS_PC_NOT_READY))
        return
    end

    if IsInGamepadPreferredMode() then
        SCENE_MANAGER:Show(JOURNAL_SCENE)
        return
    end

    if not canSwitchInputMode() then
        notify(GetString(BATTLESCROLLS_PC_REQUIRES_GAMEPAD_MODE))
        return
    end

    promptForGamepadMode(scene)
end

-- Called by Bindings.xml and reachable from other addons.
BattleScrolls.OpenJournal = pcSupport.OpenJournal

-------------------------
-- Registration
-------------------------

-- Keybind name for the BATTLESCROLLS_OPEN_JOURNAL action in Bindings.xml.
ZO_CreateStringId("SI_BINDING_NAME_BATTLESCROLLS_OPEN_JOURNAL", GetString(BATTLESCROLLS_PC_KEYBIND_OPEN_JOURNAL))
-- Category heading under Controls.
ZO_CreateStringId("SI_BINDING_NAME_BATTLESCROLLS_CATEGORY", GetString(BATTLESCROLLS_PC_KEYBIND_CATEGORY))

SLASH_COMMANDS["/bs"] = pcSupport.OpenJournal
SLASH_COMMANDS["/battlescrolls"] = pcSupport.OpenJournal
