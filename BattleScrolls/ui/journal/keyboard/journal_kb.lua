-----------------------------------------------------------
-- Journal (keyboard)
-- Keyboard-mode presentation for the combat journal, so PC
-- players do not need Gamepad Mode.
--
-- Design: this is presentation only. It duck-types the fields
-- the shared controllers read off journalUI, hands them a
-- ListCollector instead of a ZO_ParametricScrollList, and draws
-- the collected entries into a ZO_ScrollList. The renderers,
-- controllers, EntryBuilder and every spec type are reused
-- unchanged -- see ui/journal/keyboard/list_collector.lua.
--
-- The async decode (StatsListController.refresh) is likewise
-- reused as-is: it only ever touches plain fields and three
-- methods on journalUI, all provided below.
--
-- Pivot fields are advanced by clicking rather than via a
-- chooser dialog; options needing multi-select are skipped.
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

local SCENE_NAME = "battleScrollsJournalKeyboard"
local ROW_HEIGHT = 32
local HEADER_HEIGHT = 30
local SUBTAB_STRIP_HEIGHT = 30
local ROW_DATA = 1
local HEADER_DATA = 2

local NAVIGATION_MODE = journal.NavigationMode
local INSTANCE_TAB = journal.InstanceTab
local ENCOUNTER_TAB = journal.EncounterTab
local STATS_TAB = journal.StatsTab

---@class BattleScrolls_Journal_Keyboard
local JournalKeyboard = ZO_Object:Subclass()

---@return BattleScrolls_Journal_Keyboard
function JournalKeyboard:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

-------------------------
-- Setup
-------------------------

function JournalKeyboard:Initialize(control)
    self.control = control
    self.titleLabel = control:GetNamedChild("Title")
    self.subtitleLabel = control:GetNamedChild("Subtitle")
    self.emptyLabel = control:GetNamedChild("EmptyText")
    self.tabsControl = control:GetNamedChild("Tabs")
    self.subTabsControl = control:GetNamedChild("SubTabs")
    self.listControl = control:GetNamedChild("List")
    self.backButton = control:GetNamedChild("Back")

    self.titleLabel:SetText(GetString(BATTLESCROLLS_UI_NAME))
    self.backButton:SetText(GetString(SI_DIALOG_CLOSE))

    -- Lets the shared chronicler hand control back to us instead of driving
    -- gamepad-only machinery. See chronicler.refreshList / refreshTooltip.
    self.isKeyboard = true

    -- Fields the shared controllers expect to find on journalUI.
    self.mode = NAVIGATION_MODE.INSTANCES
    self.selectedInstanceTab = INSTANCE_TAB.ALL
    self.selectedEncounterTab = ENCOUNTER_TAB.ALL
    self.selectedTab = STATS_TAB.OVERVIEW
    self.selectedInstance = nil
    self.selectedEncounter = nil
    self.defaultInstancePosition = nil
    self.defaultEncounterPosition = nil

    -- Decode cache, owned by StatsListController.refresh.
    self.decodedEncounter = nil
    self.abilityInfo = nil
    self.unitNames = nil
    self.arithmancer = nil
    self.taskInProgress = nil
    self.filters = {}
    -- Remembers which sub-view each tab group was last on; read by pickSubView
    -- when building the stats tab strip.
    self.lastSubView = {}

    local onCommit = function() self:OnListCommitted() end
    self.instanceList = journal.keyboard.ListCollector:New(onCommit)
    self.encounterList = journal.keyboard.ListCollector:New(onCommit)
    self.statsList = journal.keyboard.ListCollector:New(onCommit)
    self.pivotList = journal.keyboard.ListCollector:New(onCommit)

    self.pivotQuery = nil
    self.pivotResult = nil

    self:InitializeScrollList()
    self:InitializeHandlers()
    self:InitializeScene()
end

function JournalKeyboard:InitializeScrollList()
    ZO_ScrollList_AddDataType(self.listControl, ROW_DATA, "BattleScrolls_KB_Row", ROW_HEIGHT,
        function(rowControl, data) self:SetupRow(rowControl, data) end)
    ZO_ScrollList_AddDataType(self.listControl, HEADER_DATA, "BattleScrolls_KB_Header", HEADER_HEIGHT,
        function(rowControl, data) self:SetupHeader(rowControl, data) end)
    -- Keep rows sized to the list when the window or resolution changes.
    ZO_ScrollList_AddResizeOnScreenResize(self.listControl)
end

function JournalKeyboard:InitializeHandlers()
    self.control:GetNamedChild("Close"):SetHandler("OnClicked", function() self:Hide() end)
    self.backButton:SetHandler("OnClicked", function() self:GoBack() end)
end

function JournalKeyboard:InitializeScene()
    self.fragment = ZO_FadeSceneFragment:New(self.control)
    self.scene = ZO_Scene:New(SCENE_NAME, SCENE_MANAGER)
    self.scene:AddFragment(self.fragment)
    -- Mouse cursor plus UI mode, and nothing else. Deliberately NOT the
    -- RIGHT_BG / FRAME_TARGET_STANDARD_RIGHT_PANEL fragments that inventory-style
    -- scenes use: those reserve the right half of the screen for a backdrop and a
    -- framed render of your character, which this centered window has no use for.
    self.scene:AddFragmentGroup(FRAGMENT_GROUP.MOUSE_DRIVEN_UI_WINDOW)

    self.scene:RegisterCallback("StateChange", function(_oldState, newState)
        if newState == SCENE_SHOWING then
            self:ResetToInstances()
        elseif newState == SCENE_HIDDEN then
            journal.keyboard.tooltips.Hide()
            self:HidePanel()
            self:CancelPivot()
            -- Decoded encounters are large; do not hold them while closed.
            self:ClearDecodeCache()
            self.selectedInstance = nil
            self.selectedEncounter = nil
            BattleScrolls.gc:RequestGC(2)
        end
    end)
end

-------------------------
-- Row rendering
-------------------------

---Resolves an entry's icon path.
---
---Two producers with two storage locations: EntryBuilder sets iconFile
---explicitly, while the shared controllers pass the icon to
---ZO_GamepadEntryData:New(), which stores it where GetIcon() does not reliably
---surface it (see the note at journal.lua:442). Try every known location rather
---than depend on an internal layout.
---@param data table
---@return string|nil icon
local function readIcon(data)
    -- EntryBuilder sets this explicitly for renderer-built entries.
    if type(data.iconFile) == "string" and data.iconFile ~= "" then
        return data.iconFile
    end

    -- ZO_GamepadEntryData:New(text, icon) files icons into an iconsNormal array
    -- (with numIcons as the count). Confirmed by dumping a live entry: there is
    -- no `icon` field and GetIcon() returns nothing, which is what the note at
    -- journal.lua:442 is about.
    local normal = data.iconsNormal
    if type(normal) == "table" and type(normal[1]) == "string" and normal[1] ~= "" then
        return normal[1]
    end

    local selected = data.iconsSelected
    if type(selected) == "table" and type(selected[1]) == "string" and selected[1] ~= "" then
        return selected[1]
    end

    if type(data.icon) == "string" and data.icon ~= "" then
        return data.icon
    end

    return nil
end

---Reads display text off a ZO_GamepadEntryData-shaped entry.
---@param data table
---@return string label, string|nil value, string|nil icon
local function readEntry(data)
    local label = data.text or data.name or ""
    -- AddSubLabel stores into subLabels; the gamepad list renders them on the right.
    local value = nil
    if data.subLabels and #data.subLabels > 0 then
        value = data.subLabels[1]
    end
    return label, value, readIcon(data)
end

function JournalKeyboard:SetupRow(rowControl, data)
    local entry = data.entry
    local label, value, icon = readEntry(entry)

    rowControl:GetNamedChild("Name"):SetText(label)
    rowControl:GetNamedChild("Value"):SetText(value or "")

    local iconControl = rowControl:GetNamedChild("Icon")
    if icon and icon ~= "" then
        iconControl:SetTexture(icon)
        iconControl:SetHidden(false)
    else
        iconControl:SetHidden(true)
    end

    local highlight = rowControl:GetNamedChild("Highlight")
    highlight:SetAlpha(0)

    rowControl:SetHandler("OnMouseEnter", function()
        highlight:SetAlpha(1)
        self:ShowTooltipFor(rowControl, entry.tooltip)
    end)
    rowControl:SetHandler("OnMouseExit", function()
        highlight:SetAlpha(0)
        journal.keyboard.tooltips.Hide()
        -- The overview panel is deliberately left up: it is a docked detail
        -- pane, not a hover tooltip, so it persists until another row replaces
        -- it or the view changes.
    end)
    rowControl:SetHandler("OnClicked", function()
        self:OnRowClicked(entry)
    end)
end

---Routes a tooltip descriptor to the right presenter: rich panel specs go to the
---docked OverviewPanel, everything else to the hover tooltip.
---@param rowControl Control
---@param descriptor table|nil
function JournalKeyboard:ShowTooltipFor(rowControl, descriptor)
    -- Panel specs are click-toggled, not shown on hover: the panel is large
    -- enough that having it appear under the pointer is distracting. Hovering a
    -- panel row shows nothing; clicking it opens the pane.
    if descriptor and descriptor.type == "panel" then
        -- A hint, so the pane is still discoverable now that hovering does not
        -- open it. Suppressed while the pane is already up.
        local panelKB = journal.keyboard.panel
        if panelKB and panelKB.IsAvailable() and not panelKB.IsShowing() then
            journal.keyboard.tooltips.Show(rowControl, {
                type = "text",
                title = "",
                text = GetString(BATTLESCROLLS_PC_KB_CLICK_FOR_DETAILS),
            })
        end
        return
    end

    -- The groupTable descriptor carries no data; the member rows have to be
    -- derived from the decode state, which lives here.
    if descriptor and descriptor.type == "groupTable" then
        descriptor = self:BuildGroupTableDescriptor()
    end

    journal.keyboard.tooltips.Show(rowControl, descriptor)
end

---Builds the group comparison rows for the groupTable tooltip.
---
---Reuses renderers.group.buildMemberList and derives the same columns the
---gamepad table's BuildMasterList does, so both read from one source.
---@return table descriptor
function JournalKeyboard:BuildGroupTableDescriptor()
    local descriptor = { type = "groupTable", title = GetString(BATTLESCROLLS_TAB_GROUP) }

    local arithmancer = self.arithmancer
    local encounter = self.decodedEncounter
    if not arithmancer or not encounter then
        return descriptor
    end

    local ctx = {
        arithmancer = arithmancer,
        encounter = encounter,
        durationS = arithmancer:getDurationS(),
    }

    local ok, members = pcall(journal.renderers.group.buildMemberList, ctx)
    if not ok or not members then
        return descriptor
    end

    local utils = journal.utils
    local rows = {}
    for _, member in ipairs(members) do
        local data = member.data
        local durationS = data.durationMs / 1000
        if durationS <= 0 then durationS = 1 end

        rows[#rows + 1] = {
            name = member.displayName or "",
            isLocal = member.isLocal,
            dps = utils.formatDPS(data.totalDamage / durationS),
            crit = utils.formatPercent((data.critPercent or 0) * 100),
            dtps = utils.formatDPS((data.totalDamageTaken or 0) / durationS),
            hps = utils.formatDPS(data.healing and (data.healing.rawOut / durationS) or 0),
            alive = utils.formatPercent(
                (data.aliveTimeMs and data.durationMs > 0)
                    and (data.aliveTimeMs / data.durationMs * 100)
                    or 100),
        }
    end

    descriptor.members = rows
    return descriptor
end

-------------------------
-- Aggregate / pivot
-------------------------

function JournalKeyboard:EnterPivot()
    self:CancelPivot()
    self.pivotQuery = journal.pivot.defaultQuery()
    self.pivotResult = nil
    self.mode = NAVIGATION_MODE.PIVOT
    self:Refresh()
end

---Cancels any query in flight and drops pivot state.
function JournalKeyboard:CancelPivot()
    if self.pivotFiber then
        self.pivotFiber:Cancel()
        self.pivotFiber = nil
    end
    self.pivotQuery = nil
    self.pivotResult = nil
end

---Runs the configured query, then swaps the list over to the results.
function JournalKeyboard:RunPivotQuery()
    if not self.pivotQuery or self.pivotFiber then return end

    self.pivotList:Clear()
    self.pivotList:SetNoItemText(GetString(BATTLESCROLLS_LIST_LOADING))
    self.pivotList:Commit()

    local pivotQuery = self.pivotQuery
    local engine = journal.pivot.engine

    self.pivotFiber = BattleScrolls.Effect.Async(function()
        local result = engine.runQueryAsync(pivotQuery, function(current, total)
            -- Progress goes in the empty-list text: there is no keybind strip or
            -- gamepad header here to put it in.
            self.pivotList:SetNoItemText(
                zo_strformat(GetString(BATTLESCROLLS_PIVOT_LOADING), current, total))
            self.pivotList:Commit()
        end):Await()

        if not result then return end

        if #result.rows == 0 then
            -- Stay on the config so the query can be adjusted, and say why.
            self.pivotResult = nil
            self.pivotList:SetNoItemText(GetString(BATTLESCROLLS_PIVOT_NO_RESULTS))
            self.pivotList:Commit()
            return
        end

        self.pivotResult = result
        if self.mode == NAVIGATION_MODE.PIVOT then
            self:Refresh()
        end
    end):Ensure(function()
        self.pivotFiber = nil
        BattleScrolls.gc:RequestGC(5)
    end):Run()
end

---Handles a click on a pivot config row.
---@param entry table
function JournalKeyboard:OnPivotRowClicked(entry)
    if entry.pivotRun then
        self:RunPivotQuery()
        return
    end

    if entry.pivotField and self.pivotQuery then
        if journal.keyboard.pivot.CycleField(self.pivotQuery, entry.pivotField) then
            self:Refresh(true)
        else
            -- Only reachable for fields whose every option needs a dialog.
            self:Notify(GetString(BATTLESCROLLS_PC_KB_NOT_YET))
        end
    end
end

---Tears down the docked panel, if one is showing.
function JournalKeyboard:HidePanel()
    local panelKB = journal.keyboard.panel
    if panelKB then
        panelKB.Hide(self)
    end
end

function JournalKeyboard:SetupHeader(rowControl, data)
    rowControl:GetNamedChild("Name"):SetText(data.header or "")
end

---Draws whatever the shared code just collected.
function JournalKeyboard:OnListCommitted()
    local collector = self:GetCurrentCollector()
    if not collector then return end

    ZO_ScrollList_Clear(self.listControl)
    local scrollData = ZO_ScrollList_GetDataList(self.listControl)

    for _, item in ipairs(collector:GetEntries()) do
        if item.hasHeader then
            local headerText = item.data.header
            scrollData[#scrollData + 1] =
                ZO_ScrollList_CreateDataEntry(HEADER_DATA, { header = headerText })
        end
        scrollData[#scrollData + 1] =
            ZO_ScrollList_CreateDataEntry(ROW_DATA, { entry = item.data })
    end

    ZO_ScrollList_Commit(self.listControl)

    local isEmpty = #collector:GetEntries() == 0
    self.emptyLabel:SetHidden(not isEmpty)
    if isEmpty then
        self.emptyLabel:SetText(collector:GetNoItemText() or "")
    end
end

-------------------------
-- Navigation
-------------------------

---@return BattleScrolls_KB_ListCollector|nil
function JournalKeyboard:GetCurrentCollector()
    if self.mode == NAVIGATION_MODE.INSTANCES then
        return self.instanceList
    elseif self.mode == NAVIGATION_MODE.ENCOUNTERS then
        return self.encounterList
    elseif self.mode == NAVIGATION_MODE.STATS then
        return self.statsList
    elseif self.mode == NAVIGATION_MODE.PIVOT then
        return self.pivotList
    end
    return nil
end

-------------------------
-- Methods StatsListController.refresh expects on journalUI
-------------------------

---Rebuilds the tab strip. Called after decoding, when tab visibility is known.
function JournalKeyboard:RefreshHeader()
    self:RefreshTabs()
end

---@param tab number
---@return table
function JournalKeyboard:GetFiltersForTab(tab)
    return self.filters and self.filters[tab] or {}
end

---@param tab number
---@param filters table
function JournalKeyboard:SetFiltersForTab(tab, filters)
    self.filters = self.filters or {}
    self.filters[tab] = filters
end

---Effects search is not wired up in the keyboard UI yet.
---@return string
function JournalKeyboard:GetSearchText()
    return ""
end

---Drops the decode cache and cancels any decode in flight.
function JournalKeyboard:ClearDecodeCache()
    if self.taskInProgress then
        self.taskInProgress:Cancel()
        self.taskInProgress = nil
    end
    self.decodedEncounter = nil
    self.abilityInfo = nil
    self.unitNames = nil
    self.arithmancer = nil
    BattleScrolls.gc:RequestGC(5)
end

function JournalKeyboard:ResetToInstances()
    self:CancelPivot()
    self.mode = NAVIGATION_MODE.INSTANCES
    self.selectedInstance = nil
    self.selectedEncounter = nil
    self.selectedInstanceTab = INSTANCE_TAB.ALL
    self:Refresh()
end

---Handles activation of a row in the current mode.
---@param entry table The ZO_GamepadEntryData-shaped entry that was clicked
function JournalKeyboard:OnRowClicked(entry)
    -- A row carrying a panel spec toggles the detail pane wherever it appears
    -- (every stats tab leads with one).
    local tooltip = entry.tooltip
    if tooltip and tooltip.type == "panel" and tooltip.panelSpec then
        local panelKB = journal.keyboard.panel
        if panelKB and panelKB.IsAvailable() then
            if not panelKB.Toggle(self, tooltip.panelSpec) then
                journal.keyboard.tooltips.Hide()
            end
            return
        end
    end

    if self.mode == NAVIGATION_MODE.INSTANCES then
        if entry.isSettings then
            self:OpenSettings()
        elseif entry.isPivot then
            self:EnterPivot()
        elseif entry.data then
            self.selectedInstance = entry.data
            self.mode = NAVIGATION_MODE.ENCOUNTERS
            self.selectedEncounterTab = ENCOUNTER_TAB.ALL
            self:Refresh()
        end
    elseif self.mode == NAVIGATION_MODE.PIVOT then
        self:OnPivotRowClicked(entry)
    elseif self.mode == NAVIGATION_MODE.ENCOUNTERS then
        if entry.isPivot then
            self:EnterPivot()
        elseif entry.data then
            -- A different encounter invalidates everything decoded for the last one.
            self:ClearDecodeCache()
            self.selectedEncounter = entry.data
            self.selectedTab = STATS_TAB.OVERVIEW
            self.mode = NAVIGATION_MODE.STATS
            self:Refresh()
        end
    end
end

function JournalKeyboard:GoBack()
    if self.mode == NAVIGATION_MODE.PIVOT then
        if self.pivotResult then
            -- Results back to the config that produced them, not out of the view.
            self.pivotResult = nil
            self:Refresh()
        else
            self:CancelPivot()
            self.mode = NAVIGATION_MODE.INSTANCES
            self:Refresh()
        end
    elseif self.mode == NAVIGATION_MODE.STATS then
        self:ClearDecodeCache()
        self.selectedEncounter = nil
        self.mode = NAVIGATION_MODE.ENCOUNTERS
        self:Refresh()
    elseif self.mode == NAVIGATION_MODE.ENCOUNTERS then
        self.mode = NAVIGATION_MODE.INSTANCES
        self.selectedInstance = nil
        self:Refresh()
    else
        self:Hide()
    end
end

function JournalKeyboard:OpenSettings()
    if journal.keyboard.settings then
        journal.keyboard.settings.Open()
    else
        self:Notify(GetString(BATTLESCROLLS_PC_KB_NOT_YET))
    end
end

---@param message string
function JournalKeyboard:Notify(message)
    -- See the note on notify() in ui/pc/pc_support.lua.
    d(message)
end

-------------------------
-- Tabs
-------------------------

---Marks the visually active tab.
---@param index number
function JournalKeyboard:SetActiveTab(index)
    self.activeTabIndex = index
    for i, button in ipairs(self.tabButtons or {}) do
        -- ZO_DefaultButton has no toggle state, so convey selection by disabling
        -- the current tab: it reads as "you are here" and blocks a redundant refresh.
        button:SetEnabled(i ~= index)
    end
end

function JournalKeyboard:RefreshTabs()
    -- Buttons are pooled by index across refreshes; the tab set changes with
    -- the available data (zone types present in history).
    self.tabButtons = self.tabButtons or {}

    local entries
    if self.mode == NAVIGATION_MODE.STATS then
        -- Stats tabs depend on what the encounter actually contains; the shared
        -- builder derives them from decodedEncounter._tabVisibility and needs no
        -- gamepad UI. Before the decode lands it returns Overview only, and
        -- RefreshHeader() runs again afterwards to fill in the rest.
        entries = journal.chronicler.getEncounterTabBarEntries(self) or {}
    else
        local controller = self.mode == NAVIGATION_MODE.INSTANCES
            and journal.controllers.instanceList
            or journal.controllers.encounterList
        entries = (controller and controller.getTabBarEntries)
            and controller.getTabBarEntries(self) or {}
    end

    local previous = nil
    for i, tabEntry in ipairs(entries) do
        local button = self.tabButtons[i]
        if not button then
            button = CreateControlFromVirtual("$(parent)Tab", self.tabsControl,
                "ZO_DefaultButton", i)
            button:SetHeight(28)
            self.tabButtons[i] = button
        end

        button:SetText(tabEntry.text or "")
        -- Size to the label so tabs do not all share one arbitrary width.
        -- GetTextWidth can read short or zero before the label has laid out, so
        -- pad generously and enforce a floor rather than clip the caption.
        local textWidth = button:GetLabelControl():GetTextWidth() or 0
        button:SetWidth(zo_max(90, textWidth + 44))
        button:ClearAnchors()
        if previous then
            button:SetAnchor(LEFT, previous, RIGHT, 8, 0)
        else
            button:SetAnchor(LEFT, self.tabsControl, LEFT, 0, 0)
        end
        button:SetHidden(false)
        button:SetHandler("OnClicked", function()
            self:SetActiveTab(i)
            if tabEntry.callback then
                -- Callbacks set the tab field and call RefreshList themselves.
                tabEntry.callback()
            end
        end)

        previous = button
    end

    -- Retire buttons left over from a longer tab set.
    for i = #entries + 1, #self.tabButtons do
        self.tabButtons[i]:SetHidden(true)
    end

    self:SetActiveTab(1)
    self:RefreshSubTabs()
end

-------------------------
-- Sub-views
-------------------------

---Builds the secondary strip for tab groups that have more than one visible
---sub-view (Damage -> Boss Damage Done / Damage Done, and similarly for Healing
---and Effects). Collapses to nothing otherwise.
function JournalKeyboard:RefreshSubTabs()
    self.subTabButtons = self.subTabButtons or {}

    local subViews = self:GetVisibleSubViews()

    for i = 1, #self.subTabButtons do
        self.subTabButtons[i]:SetHidden(true)
    end

    if #subViews <= 1 then
        self.subTabsControl:SetHeight(0)
        return
    end

    self.subTabsControl:SetHeight(SUBTAB_STRIP_HEIGHT)

    local previous = nil
    for i, tab in ipairs(subViews) do
        local button = self.subTabButtons[i]
        if not button then
            button = CreateControlFromVirtual("$(parent)SubTab", self.subTabsControl,
                "ZO_DefaultButton", i)
            button:SetHeight(24)
            self.subTabButtons[i] = button
        end

        local labelId = journal.SubViewLabels[tab]
        button:SetText(labelId and GetString(_G[labelId]) or "")
        button:SetWidth(zo_max(90, (button:GetLabelControl():GetTextWidth() or 0) + 40))
        button:ClearAnchors()
        if previous then
            button:SetAnchor(LEFT, previous, RIGHT, 8, 0)
        else
            button:SetAnchor(LEFT, self.subTabsControl, LEFT, 4, 0)
        end
        button:SetHidden(false)
        -- The current sub-view reads as "you are here" and blocks a no-op refresh.
        button:SetEnabled(tab ~= self.selectedTab)
        button:SetHandler("OnClicked", function()
            self:SelectSubView(tab)
        end)

        previous = button
    end
end

---@return StatsTab[] Visible sub-views for the active tab's group, empty if none
function JournalKeyboard:GetVisibleSubViews()
    if self.mode ~= NAVIGATION_MODE.STATS then return {} end

    local groupKey = self.selectedTab and journal.TabToGroup[self.selectedTab]
    if not groupKey then return {} end

    local tabVis = self.decodedEncounter and self.decodedEncounter._tabVisibility
    if not tabVis then return {} end

    return journal.chronicler.getVisibleSubViews(groupKey, tabVis) or {}
end

---Switches to a sub-view, remembering it so returning to the group lands here.
---@param tab number StatsTab value
function JournalKeyboard:SelectSubView(tab)
    if tab == self.selectedTab then return end

    local groupKey = journal.TabToGroup[tab]
    if groupKey then
        self.lastSubView[groupKey] = tab
    end
    self.selectedTab = tab
    -- Skip the tab strip: the parent tab has not changed, only the sub-view.
    self:Refresh(true)
end

-------------------------
-- Refresh
-------------------------

---@param skipTabs boolean|nil Skip rebuilding the tab bar (used from tab callbacks)
function JournalKeyboard:Refresh(skipTabs)
    -- Any list change invalidates whatever the panel was showing, and leaving a
    -- stale one docked would also keep the window shifted left.
    self:HidePanel()

    if not skipTabs then
        self:RefreshTabs()
    else
        -- Parent tab unchanged, but the active sub-view (and so which button is
        -- disabled) may have.
        self:RefreshSubTabs()
    end

    if self.mode == NAVIGATION_MODE.INSTANCES then
        self.subtitleLabel:SetText("")
        journal.controllers.instanceList.refresh(self)
    elseif self.mode == NAVIGATION_MODE.ENCOUNTERS then
        local zone = self.selectedInstance and self.selectedInstance.zone or ""
        self.subtitleLabel:SetText(zone)
        journal.controllers.encounterList.refresh(self)
    elseif self.mode == NAVIGATION_MODE.PIVOT then
        self.subtitleLabel:SetText(GetString(BATTLESCROLLS_PIVOT_ENTRY))
        if self.pivotResult then
            journal.keyboard.pivot.RenderResult(self.pivotList, self.pivotResult)
        else
            journal.keyboard.pivot.RenderConfig(self.pivotList, self.pivotQuery, self)
        end
    elseif self.mode == NAVIGATION_MODE.STATS then
        self.subtitleLabel:SetText(self:BuildStatsSubtitle())
        -- Async: decodes if needed, renders the tab through the shared renderers,
        -- then Commit() fires OnListCommitted and the rows appear.
        journal.controllers.statsList.refresh(self)
    end

    self.backButton:SetText(self.mode == NAVIGATION_MODE.INSTANCES
        and GetString(SI_DIALOG_CLOSE)
        or GetString(SI_GAMEPAD_BACK_OPTION))
end

---Breadcrumb for the stats view: zone then encounter name.
---@return string
function JournalKeyboard:BuildStatsSubtitle()
    local zone = self.selectedInstance and self.selectedInstance.zone or ""
    local name = self.selectedEncounter and self.selectedEncounter.displayName
    if name and name ~= "" then
        return string.format("%s  >  %s", zone, name)
    end
    return zone
end

-- The shared controllers call journalUI:RefreshList(skipHeaderRefresh) from tab
-- callbacks. Map it onto our refresh so those callbacks work untouched.
---@param skipHeaderRefresh boolean|nil
function JournalKeyboard:RefreshList(skipHeaderRefresh)
    self:Refresh(skipHeaderRefresh)
end

-------------------------
-- Show / hide
-------------------------

function JournalKeyboard:Show()
    SCENE_MANAGER:Show(SCENE_NAME)
end

function JournalKeyboard:Hide()
    SCENE_MANAGER:Hide(SCENE_NAME)
end

---@return boolean
function JournalKeyboard:IsShowing()
    return self.scene and self.scene:IsShowing() or false
end

-------------------------
-- Bootstrap
-------------------------

journal.keyboard.JournalKeyboard = JournalKeyboard

function BattleScrolls_Journal_Keyboard_OnInitialized(control)
    BATTLESCROLLS_JOURNAL_KEYBOARD = JournalKeyboard:New(control)
    journal.keyboard.instance = BATTLESCROLLS_JOURNAL_KEYBOARD
end
