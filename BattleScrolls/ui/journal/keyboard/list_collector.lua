-----------------------------------------------------------
-- List Collector (keyboard)
-- Stands in for ZO_ParametricScrollList so the shared journal
-- code can populate a keyboard list without knowing about it.
--
-- The renderers, controllers and EntryBuilder all talk to a
-- list through a small surface (AddEntry, AddEntryWithHeader,
-- Clear, Commit, selection accessors). This implements that
-- surface and simply records what was added, so the keyboard
-- window can draw the result however it likes.
--
-- ZO_GamepadEntryData is a plain data holder that exists in
-- both interface modes, so nothing here needs the gamepad UI
-- to be active -- we reuse the entry objects as-is.
-----------------------------------------------------------

if not SemisPlaygroundCheckAccess() then
    return
end

-- Keyboard-only. Console never loads past this point.
if not IsKeyboardUISupported() then
    return
end

BattleScrolls = BattleScrolls or {}
BattleScrolls.journal = BattleScrolls.journal or {}

local journal = BattleScrolls.journal
journal.keyboard = journal.keyboard or {}

---@class BattleScrolls_KB_ListEntry
---@field template string Template the shared code asked for
---@field data table The ZO_GamepadEntryData-shaped entry
---@field hasHeader boolean Whether this entry starts a new section

---@class BattleScrolls_KB_ListCollector
local ListCollector = ZO_Object:Subclass()

---@return BattleScrolls_KB_ListCollector
function ListCollector:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

---@param onCommit fun(collector: BattleScrolls_KB_ListCollector)|nil Called when the shared code finishes populating
function ListCollector:Initialize(onCommit)
    self.entries = {}
    self.selectedIndex = nil
    self.noItemText = ""
    self.onCommit = onCommit
    self.active = false
end

-------------------------
-- Population surface
-------------------------

function ListCollector:Clear()
    self.entries = {}
end

---@param template string
---@param data table
function ListCollector:AddEntry(template, data)
    self.entries[#self.entries + 1] = { template = template, data = data, hasHeader = false }
end

---@param template string
---@param data table
function ListCollector:AddEntryWithHeader(template, data)
    self.entries[#self.entries + 1] = { template = template, data = data, hasHeader = true }
end

---Finishes population and lets the window redraw.
function ListCollector:Commit()
    -- Keep the selection in range; the shared code re-populates wholesale.
    if self.selectedIndex and self.selectedIndex > #self.entries then
        self.selectedIndex = #self.entries > 0 and #self.entries or nil
    end
    if self.onCommit then
        self.onCommit(self)
    end
end

-- Data templates are a parametric-list concept with no keyboard equivalent:
-- the window owns its row template. Accept and ignore the registrations so
-- shared setup code runs unchanged.
function ListCollector:AddDataTemplate() end
function ListCollector:AddDataTemplateWithHeader() end
function ListCollector:SetDataTemplateReleaseFunction() end
function ListCollector:SetDataTemplateWithHeaderReleaseFunction() end
function ListCollector:SetReselectBehavior() end
function ListCollector:SetAlpha() end

-------------------------
-- Selection surface
-------------------------

---@return number
function ListCollector:GetNumEntries()
    return #self.entries
end

---@return number
function ListCollector:GetNumItems()
    return #self.entries
end

---@return table|nil
function ListCollector:GetSelectedData()
    local entry = self.selectedIndex and self.entries[self.selectedIndex]
    return entry and entry.data or nil
end

-- The parametric list distinguishes "selected" from "targeted" (what the cursor
-- is on). With a mouse there is only one notion of current row.
ListCollector.GetTargetData = ListCollector.GetSelectedData

---@return number|nil
function ListCollector:GetSelectedIndex()
    return self.selectedIndex
end

---@param index number|nil
function ListCollector:SetSelectedIndexWithoutAnimation(index)
    if index == nil or self.entries[index] then
        self.selectedIndex = index
    end
end

ListCollector.SetSelectedIndex = ListCollector.SetSelectedIndexWithoutAnimation

---@param text string
function ListCollector:SetNoItemText(text)
    self.noItemText = text
end

---@return string
function ListCollector:GetNoItemText()
    return self.noItemText
end

---@return boolean
function ListCollector:IsActive()
    return self.active
end

---@param active boolean
function ListCollector:SetActive(active)
    self.active = active
end

-------------------------
-- Read side (window)
-------------------------

---@return BattleScrolls_KB_ListEntry[]
function ListCollector:GetEntries()
    return self.entries
end

---@param index number
---@return BattleScrolls_KB_ListEntry|nil
function ListCollector:GetEntry(index)
    return self.entries[index]
end

journal.keyboard.ListCollector = ListCollector
