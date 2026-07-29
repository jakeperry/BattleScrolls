-----------------------------------------------------------
-- PC Support
-- Entry points that only exist on PC: slash commands and a
-- rebindable key for opening the journal.
--
-- The journal is built on ESO's gamepad UI framework, which
-- ships on PC too but only renders correctly while the client
-- is actually in gamepad mode. We therefore require that mode
-- rather than trying to arrange it ourselves.
--
-- Deliberately NOT done here: forcing
-- GAMEPAD_SETTING_INPUT_PREFERRED_MODE to gamepad on the
-- player's behalf. The journal scene carries
-- FRAME_TARGET_GAMEPAD and FRAME_EMOTE_FRAGMENT_SOCIAL, and
-- flipping the input mode around its show/hide races the frame
-- teardown, stranding a render target that stays on screen
-- until the UI is reloaded. It is worse under the Automatic
-- setting, where the client also switches modes on its own
-- and undoes any arrangement we make.
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

---@class BattleScrolls_PCSupport
local pcSupport = {}
BattleScrolls.pcSupport = pcSupport

-------------------------
-- Messaging
-------------------------

---Writes a message to chat, matching the addon's existing convention
---(see onboarding.lua). Not BattleScrolls.log, which is gated behind
---settings.logLevel and unset by default.
---@param message string
local function notify(message)
    d(message)
end

-------------------------
-- Public entry point
-------------------------

---Opens the Battle Scrolls journal when the client is in gamepad mode.
---Safe to call at any time: the journal UI is built asynchronously a moment
---after load, and this reports that rather than erroring.
function pcSupport.OpenJournal()
    -- Keyboard mode gets its own presentation; see ui/journal/keyboard/.
    if not IsInGamepadPreferredMode() then
        local keyboardJournal = BattleScrolls.journal
            and BattleScrolls.journal.keyboard
            and BattleScrolls.journal.keyboard.instance
        if keyboardJournal then
            keyboardJournal:Show()
        else
            notify(GetString(BATTLESCROLLS_PC_REQUIRES_GAMEPAD_MODE))
        end
        return
    end

    local scene = SCENE_MANAGER:GetScene(JOURNAL_SCENE)
    if not scene then
        notify(GetString(BATTLESCROLLS_PC_NOT_READY))
        return
    end

    SCENE_MANAGER:Show(JOURNAL_SCENE)
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
