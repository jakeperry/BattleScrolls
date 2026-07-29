-----------------------------------------------------------
-- Aggregate / Pivot (keyboard)
-- Drives the shared pivot modules from the keyboard window.
--
-- Almost nothing needed porting: config_renderer.render()
-- populates a list through EntryBuilder, so the ListCollector
-- accepts it as-is, and every row it emits is tagged with a
-- `pivotField` name. engine.runQueryAsync(), query.lua and
-- extractors.lua are entirely platform-neutral.
--
-- Interaction differs from the gamepad UI by necessity. There,
-- selecting a field opens a parametric chooser; here a click
-- advances the field to its next option, which needs no dialog.
-- Options that require a multi-select dialog (pick zones, pick
-- instances, pick boss names, custom day count) are skipped
-- while cycling rather than being offered and then failing.
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

local pivotKB = {}

-------------------------
-- Option cycling
-------------------------

-- Field values whose configuration needs a multi-select dialog we do not have.
-- Keyed by field name, then by option key.
local function buildUnsupportedKeys()
    local pivot = journal.pivot
    return {
        instanceScope = {
            [pivot.InstanceMode.ZONES] = true,
            [pivot.InstanceMode.SPECIFIC] = true,
        },
        encounterFilter = {
            [pivot.EncounterCategory.BOSS_NAMES] = true,
            [pivot.EncounterCategory.SPECIFIC] = true,
        },
        timeFilter = {
            ["custom"] = true,
        },
    }
end

---Advances a config field to its next selectable option.
---@param query PivotQuery
---@param fieldName string
---@return boolean changed
function pivotKB.CycleField(query, fieldName)
    local pivotNS = journal.pivot
    local configRenderer = pivotNS.configRenderer
    local queryNS = pivotNS.query

    local options = configRenderer.getFieldOptions(fieldName, query)
    if not options or #options == 0 then return false end

    local unsupported = buildUnsupportedKeys()[fieldName] or {}

    -- Selectable options only, so cycling can never land somewhere unconfigurable.
    local usable = {}
    for _, option in ipairs(options) do
        if not unsupported[option.key] then
            usable[#usable + 1] = option
        end
    end
    if #usable == 0 then return false end

    local current = queryNS.getCurrentFieldValue(query, fieldName)
    local index = 1
    for i, option in ipairs(usable) do
        if option.key == current then
            index = i
            break
        end
    end

    local nextOption = usable[(index % #usable) + 1]
    queryNS.applyFieldSelection(query, fieldName, nextOption.key)
    return true
end

-------------------------
-- Config list
-------------------------

---Populates the config rows for the current query.
---@param collector BattleScrolls_KB_ListCollector
---@param query PivotQuery
---@param journalUI BattleScrolls_Journal_Keyboard
function pivotKB.RenderConfig(collector, query, journalUI)
    journal.pivot.configRenderer.render(collector, query, journalUI)

    -- A run action has to live in the list: there is no keybind strip here.
    local runEntry = journal.EntryBuilder.addEntry(collector, {
        label = GetString(BATTLESCROLLS_PIVOT_RUN),
        icon = "EsoUI/Art/Crafting/Gamepad/gp_crafting_menuIcon_research.dds",
        sublabel = journal.pivot.configRenderer.describeQuery(query),
    })
    runEntry.pivotRun = true

    collector:Commit()
end

-------------------------
-- Results
-------------------------

---Formats one cell using the same formatter the gamepad table uses.
---@param result PivotResult
---@param columnKey string
---@param value number|nil
---@return string
local function formatCell(result, columnKey, value)
    if value == nil then return "" end

    local extractors = journal.pivot.extractors
    local metricIds = result.query and result.query.metrics
    local formatter
    if extractors.getMetricFormatter then
        -- Column keys are metric ids when several metrics are requested;
        -- otherwise every column shares the single metric's formatter.
        formatter = extractors.getMetricFormatter(columnKey)
            or (metricIds and metricIds[1] and extractors.getMetricFormatter(metricIds[1]))
    end
    if formatter then
        local ok, text = pcall(formatter, value)
        if ok and text then return text end
    end
    return journal.utils.formatNumber(value)
end

---Populates result rows. Each row shows its dimension value plus the first
---column; the full set of columns goes in the row's tooltip.
---@param collector BattleScrolls_KB_ListCollector
---@param result PivotResult
function pivotKB.RenderResult(collector, result)
    collector:Clear()

    local header = result.rowDimensionLabel
    if result.encounterCount then
        header = string.format("%s  (%s)", header,
            zo_strformat(GetString(BATTLESCROLLS_PIVOT_ENCOUNTERS_PROCESSED), result.encounterCount))
    end

    if #result.rows == 0 then
        collector:SetNoItemText(GetString(BATTLESCROLLS_PIVOT_NO_RESULTS))
        collector:Commit()
        return
    end

    local firstColumn = result.columns and result.columns[1]

    for index, row in ipairs(result.rows) do
        -- Every column as tooltip detail rows, so nothing is hidden by only
        -- having room for one value in the list.
        local detailRows = {}
        for _, columnKey in ipairs(result.columns or {}) do
            detailRows[#detailRows + 1] = {
                icon = "",
                label = result.columnLabels and result.columnLabels[columnKey] or columnKey,
                value = formatCell(result, columnKey, row.values and row.values[columnKey]),
            }
        end

        journal.EntryBuilder.addEntry(collector, {
            label = row.key,
            sublabel = firstColumn
                and formatCell(result, firstColumn, row.values and row.values[firstColumn])
                or nil,
            header = index == 1 and header or nil,
            tooltip = #detailRows > 0
                and { type = "detailRows", title = row.key, rows = detailRows }
                or nil,
        })
    end

    -- The engine's caps are file-locals, so report the size we actually got
    -- rather than duplicating the constants here.
    if result.rowsCapped then
        journal.EntryBuilder.addEntry(collector, {
            label = zo_strformat(GetString(BATTLESCROLLS_PIVOT_ROWS_CAPPED), #result.rows),
        })
    end
    if result.columnsCapped then
        journal.EntryBuilder.addEntry(collector, {
            label = zo_strformat(GetString(BATTLESCROLLS_PIVOT_COLUMNS_CAPPED),
                #(result.columns or {})),
        })
    end

    collector:Commit()
end

journal.keyboard.pivot = pivotKB
