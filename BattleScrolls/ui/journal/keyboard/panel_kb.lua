-----------------------------------------------------------
-- Overview Panel (keyboard)
-- Renders panel-type tooltips using the real OverviewPanel
-- rather than a degraded text version.
--
-- The panel is built from a PanelSpec whose build(q2, q3, q4)
-- writes into ColumnBuilder objects that acquire real pooled
-- controls. Reimplementing that as text would mean reproducing
-- ten factory methods and losing the bars and icons, so instead
-- we borrow the existing panel: BATTLESCROLLS_JOURNAL_GAMEPAD
-- builds it on PC in either interface mode, and it is only
-- visible while its parent is.
--
-- This is the same trick ui/character/character_stats.lua uses
-- to put the panel on the gamepad character sheet: re-parent it
-- to something visible and render. Its anchors are relative to
-- GuiRoot, so we deliberately do NOT touch them -- the panel
-- lands in its native position covering the right of the
-- screen. To avoid overlapping it, the journal window moves
-- left while a panel is showing, which reproduces the console
-- layout of list-on-left, detail-on-right.
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

-- Window geometry while a panel is docked beside the list.
local LIST_WIDTH_WITH_PANEL = 520
local LIST_LEFT_MARGIN = 40

local panelKB = {}

local borrowed = false

-------------------------
-- Panel access
-------------------------

---@return BattleScrolls_Journal_OverviewPanel|nil
local function getPanel()
    local gamepadJournal = BATTLESCROLLS_JOURNAL_GAMEPAD
    return gamepadJournal and gamepadJournal.overviewPanel or nil
end

---@return boolean
function panelKB.IsAvailable()
    return getPanel() ~= nil
end

-------------------------
-- Window geometry
-------------------------

---Moves the journal window left and narrows it so the panel has room.
---@param journalUI BattleScrolls_Journal_Keyboard
local function dockWindowLeft(journalUI)
    local control = journalUI.control
    if journalUI._dockedLeft then return end
    journalUI._dockedLeft = true

    journalUI._restoreWidth = control:GetWidth()
    control:ClearAnchors()
    control:SetAnchor(LEFT, GuiRoot, LEFT, LIST_LEFT_MARGIN, 0)
    control:SetWidth(LIST_WIDTH_WITH_PANEL)
end

---Returns the journal window to its centred position.
---@param journalUI BattleScrolls_Journal_Keyboard
local function restoreWindow(journalUI)
    local control = journalUI.control
    if not journalUI._dockedLeft then return end
    journalUI._dockedLeft = false

    control:ClearAnchors()
    control:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    if journalUI._restoreWidth then
        control:SetWidth(journalUI._restoreWidth)
        journalUI._restoreWidth = nil
    end
end

-------------------------
-- Show / hide
-------------------------

---Shows a panel spec beside the journal window.
---@param journalUI BattleScrolls_Journal_Keyboard
---@param spec PanelSpec
---@return boolean shown False if no panel is available, so the caller can fall back
function panelKB.Show(journalUI, spec)
    local panel = getPanel()
    if not panel or not spec then return false end

    -- Deliberately no anchor changes: the panel positions itself against
    -- GuiRoot and only needs a visible parent.
    if not borrowed then
        panel.control:SetParent(journalUI.control)
        borrowed = true
    end
    panel.control:SetAlpha(1)

    dockWindowLeft(journalUI)
    panel:Show()
    panel:Render(spec)
    return true
end

---Hides the panel and hands it back.
---@param journalUI BattleScrolls_Journal_Keyboard
function panelKB.Hide(journalUI)
    local panel = getPanel()
    if panel then
        panel:Hide()
        panel:Clear()
        if borrowed then
            -- Returns it to the gamepad journal's own top level control.
            panel:RestoreParent()
            borrowed = false
        end
    end
    restoreWindow(journalUI)
end

journal.keyboard.panel = panelKB
