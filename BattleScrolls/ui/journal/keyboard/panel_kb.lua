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
-- to put the panel on the gamepad character sheet.
--
-- Unlike that case we do re-anchor it. Its native anchors cover
-- gamepad quadrants 2-4, whose left edge leaves too little room
-- for a usable list beside it, so the panel is confined to the
-- space right of the journal window. The original anchors are
-- captured first and restored on release, otherwise the gamepad
-- journal would inherit our layout.
--
-- Shown on click rather than hover: at this size it is a detail
-- pane you ask for, not something that should appear under the
-- pointer.
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

local WINDOW_LEFT_MARGIN = 30
local PANEL_GAP = 12
local PANEL_RIGHT_MARGIN = 20
local PANEL_MIN_WIDTH = 420

local panelKB = {}

local borrowed = false
local savedAnchors = nil ---@type table[]|nil

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
-- Anchor save / restore
-------------------------

---Captures a control's current anchors so they can be put back verbatim.
---@param control Control
---@return table[]
local function captureAnchors(control)
    local anchors = {}
    -- Controls carry at most two anchors.
    for index = 0, 1 do
        local valid, point, relativeTo, relativePoint, offsetX, offsetY = control:GetAnchor(index)
        if valid then
            anchors[#anchors + 1] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                offsetX = offsetX,
                offsetY = offsetY,
            }
        end
    end
    return anchors
end

---@param control Control
---@param anchors table[]
local function applyAnchors(control, anchors)
    control:ClearAnchors()
    for _, a in ipairs(anchors) do
        control:SetAnchor(a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY)
    end
end

-------------------------
-- Geometry
-------------------------

---Moves the journal window to the left, keeping its width so the tab strip
---still fits. Narrowing it clipped the tabs.
---@param journalUI BattleScrolls_Journal_Keyboard
local function dockWindowLeft(journalUI)
    if journalUI._dockedLeft then return end
    journalUI._dockedLeft = true

    local control = journalUI.control
    control:ClearAnchors()
    control:SetAnchor(LEFT, GuiRoot, LEFT, WINDOW_LEFT_MARGIN, 0)
end

---@param journalUI BattleScrolls_Journal_Keyboard
local function restoreWindow(journalUI)
    if not journalUI._dockedLeft then return end
    journalUI._dockedLeft = false

    local control = journalUI.control
    control:ClearAnchors()
    control:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
end

---Confines the panel to the space right of the journal window.
---@param panelControl Control
---@param windowControl Control
---@return boolean fits
local function anchorBesideWindow(panelControl, windowControl)
    local available = GuiRoot:GetWidth()
        - (WINDOW_LEFT_MARGIN + windowControl:GetWidth() + PANEL_GAP + PANEL_RIGHT_MARGIN)
    if available < PANEL_MIN_WIDTH then
        return false
    end

    panelControl:ClearAnchors()
    panelControl:SetAnchor(TOPLEFT, windowControl, TOPRIGHT, PANEL_GAP, 0)
    panelControl:SetAnchor(BOTTOMRIGHT, GuiRoot, BOTTOMRIGHT, -PANEL_RIGHT_MARGIN,
        -(windowControl:GetTop() or 0))
    return true
end

-------------------------
-- Show / hide
-------------------------

---@return boolean
function panelKB.IsShowing()
    return borrowed
end

---Shows a panel spec beside the journal window.
---@param journalUI BattleScrolls_Journal_Keyboard
---@param spec PanelSpec
---@return boolean shown False if there is no panel or no room, so the caller can fall back
function panelKB.Show(journalUI, spec)
    local panel = getPanel()
    if not panel or not spec then return false end

    local panelControl = panel.control

    if not borrowed then
        savedAnchors = captureAnchors(panelControl)
        panelControl:SetParent(journalUI.control)
        dockWindowLeft(journalUI)

        if not anchorBesideWindow(panelControl, journalUI.control) then
            -- Not enough width: undo and let the caller show a text tooltip.
            applyAnchors(panelControl, savedAnchors)
            savedAnchors = nil
            panel:RestoreParent()
            restoreWindow(journalUI)
            return false
        end
        borrowed = true
    end

    panelControl:SetAlpha(1)
    panel:Show()
    panel:Render(spec)
    return true
end

---Hides the panel and hands it back with its original anchors.
---@param journalUI BattleScrolls_Journal_Keyboard
function panelKB.Hide(journalUI)
    local panel = getPanel()
    if panel then
        panel:Hide()
        panel:Clear()
        if borrowed then
            if savedAnchors then
                applyAnchors(panel.control, savedAnchors)
                savedAnchors = nil
            end
            -- Returns it to the gamepad journal's own top level control.
            panel:RestoreParent()
            borrowed = false
        end
    end
    restoreWindow(journalUI)
end

---Shows the spec if hidden, hides it if already showing.
---@param journalUI BattleScrolls_Journal_Keyboard
---@param spec PanelSpec
---@return boolean showing
function panelKB.Toggle(journalUI, spec)
    if borrowed then
        panelKB.Hide(journalUI)
        return false
    end
    return panelKB.Show(journalUI, spec)
end

journal.keyboard.panel = panelKB
