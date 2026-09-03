local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local LuaSettings = require("luasettings")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

-- Resolve our helper relative to this file, including in extra plugin paths.
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local Geometry = dofile(plugin_dir .. "geometry.lua")

local function scaleBySize(size)
    if Screen and Screen.scaleBySize then
        return Screen:scaleBySize(size)
    end
    return size
end

local Typoscope = Widget:extend{
    name = "typoscope",
    is_doc_only = true,
    is_enabled = false,
    leave_image_pages_unmasked = false,
    flash_on_line_change = true,
    line_index = 1,
    line_padding = 3,
    lines = nil,
}

function Typoscope:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/typoscope.lua")
    self.is_supported = self:isSupportedDocument()
    self.is_enabled = self.is_supported and self.settings:isTrue("enabled")
    self.lines = {}
    self.leave_image_pages_unmasked = self.settings:isTrue("leave_image_pages_unmasked")
    self.flash_on_line_change = self.settings:nilOrTrue("flash_on_line_change")
    self.line_padding = self.settings:readSetting("line_padding") or scaleBySize(self.line_padding)
    self:registerActions()
end

function Typoscope.registerActions()
    Dispatcher:registerAction("typoscope_toggle", {
        category = "none", event = "TyposcopeToggle", title = _("Toggle typoscope"), reader = true,
    })
    Dispatcher:registerAction("typoscope_next_line", {
        category = "none", event = "TyposcopeNextLine", title = _("Typoscope: next line"), reader = true,
    })
    Dispatcher:registerAction("typoscope_previous_line", {
        category = "none", event = "TyposcopePreviousLine", title = _("Typoscope: previous line"), reader = true,
    })
end

Typoscope.onDispatcherRegisterActions = Typoscope.registerActions

function Typoscope:isSupportedDocument()
    local document = self.ui and self.ui.document
    if not self.ui or not self.ui.rolling or not document then return false end
    -- CRe supplies the same screen-text API for EPUB, MOBI and other reflowable
    -- formats. Require that API rather than maintaining an extension allowlist.
    return type(document.getTextFromPositions) == "function"
        and type(document.getCurrentPage) == "function"
        and type(document.getCurrentPos) == "function"
        and type(document.getVisiblePageCount) == "function"
        and type(document.getPageCount) == "function"
end

function Typoscope:onReaderReady()
    if not self.is_supported then return end
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("typoscope", self)
    self:refreshLines(true)
    if Device:isTouchDevice() and not self.original_touch_setup then
        -- Reading direction and tap-zone settings rebuild the rolling controller's
        -- zones directly, without a layout event. Follow every such rebuild.
        local rolling = self.ui.rolling
        self.original_touch_setup = rolling.setupTouchZones
        self.touch_setup_wrapper = function(controller, ...)
            self.original_touch_setup(controller, ...)
            self:setupTouchZones()
        end
        rolling.setupTouchZones = self.touch_setup_wrapper
    end
    self:setupTouchZones()
end

function Typoscope:setupTouchZones()
    if not self.is_supported or not Device:isTouchDevice() then return end

    local forward_zone, backward_zone = self.view:getTapZones()
    self.ui:registerTouchZones({
        {
            id = "typoscope_tap_forward",
            ges = "tap",
            screen_zone = forward_zone,
            overrides = { "tap_forward" },
            handler = function()
                if self.is_enabled and G_reader_settings:nilOrFalse("page_turns_disable_tap") then
                    return self:onTyposcopeNextLine()
                end
            end,
        },
        {
            id = "typoscope_tap_backward",
            ges = "tap",
            screen_zone = backward_zone,
            overrides = { "tap_backward" },
            handler = function()
                if self.is_enabled and G_reader_settings:nilOrFalse("page_turns_disable_tap") then
                    return self:onTyposcopePreviousLine()
                end
            end,
        },
    })
end

function Typoscope:getViewport()
    -- CRe's text boxes are already in screen coordinates. Keep the footer visible.
    local height = Screen:getHeight()
    if self.view.footer_visible then height = height - self.view.footer:getHeight() end
    return { x = 0, y = 0, w = Screen:getWidth(), h = math.max(0, height) }
end

function Typoscope:getPageAreas(viewport)
    local document = self.ui.document
    local count = document:getVisiblePageCount()
    if self.view.view_mode == "scroll" or count == 1 then return { viewport } end

    -- CRe draws the current page on the left and the next on the right.
    -- Split at the screen midpoint, not getPageOffsetX(): its rectangles can
    -- overlap in the gutter when CRe adjusts the inner margins.
    local width = math.floor(viewport.w / 2)
    local areas = {
        { x = viewport.x, y = viewport.y, w = width, h = viewport.h },
    }
    -- Visible page count describes the layout even if the final right page
    -- does not exist. Compare internal page numbers to detect that case.
    if document:getCurrentPage(true) < document:getPageCount(true) then
        areas[#areas + 1] = {
            x = viewport.x + width, y = viewport.y, w = viewport.w - width, h = viewport.h,
        }
    end
    return areas
end

function Typoscope:getLocation()
    if not self.is_supported or not self.ui.document then return end
    if self.view.view_mode == "scroll" then return self.ui.document:getCurrentPos() end
    return self.ui.document:getCurrentPage(true)
end

function Typoscope:refreshLines(reset)
    if reset then self.line_index = 1 end
    self.lines = {}
    self.location = self:getLocation()
    if not self.is_supported or not self.is_enabled or not self.ui.document then return end

    local viewport = self:getViewport()
    local areas = self:getPageAreas(viewport)
    local last_area = areas[#areas]
    -- Keep the endpoint on an existing page: CRe rejects a selection whose
    -- endpoint falls on the empty right half of the final spread.
    local ok, result = pcall(self.ui.document.getTextFromPositions, self.ui.document,
        { x = viewport.x, y = viewport.y },
        { x = last_area.x + last_area.w, y = last_area.y + last_area.h }, true)
    -- getTextFromPositions already supplies screen boxes; no second extraction
    -- is needed. An empty/failed extraction leaves the page unmasked.
    if ok and result and type(result.sboxes) == "table" then
        for _, area in ipairs(areas) do
            for _, line in ipairs(Geometry.normaliseLines(result.sboxes, area)) do
                line.area = area
                self.lines[#self.lines + 1] = line
            end
        end
    end
    self.line_index = math.max(1, math.min(self.line_index, #self.lines))
end

function Typoscope:getSlot(viewport)
    local line = self.lines[self.line_index]
    if line then return Geometry.slotForLine(line.area or viewport, line, self.line_padding) end
end

function Typoscope:pageHasImages()
    if not self.ui or not self.ui.document.getDrawnImagesStatistics then return false end
    local count = self.ui.document:getDrawnImagesStatistics()
    return count and count > 0
end

function Typoscope:paintTo(bb, x, y)
    if not self.is_supported or not self.is_enabled then return end
    if self.leave_image_pages_unmasked and self:pageHasImages() then return end
    local viewport = self:getViewport()
    local slot = self:getSlot(viewport)
    if not slot then return end
    for _, mask in ipairs(Geometry.masks(viewport, slot)) do
        if mask.w > 0 and mask.h > 0 then
            bb:paintRect(x + mask.x, y + mask.y, mask.w, mask.h, Blitbuffer.COLOR_BLACK)
        end
    end
end

function Typoscope:redraw()
    if self.view and self.view.dialog then UIManager:setDirty(self.view.dialog, "partial") end
end

function Typoscope:redrawSlotChange(viewport, old_slot)
    if not self.view or not self.view.dialog then return end
    if self.leave_image_pages_unmasked and self:pageHasImages() then return end
    local new_slot = self:getSlot(viewport)
    if not old_slot or not new_slot then return end
    local refresh_mode = self.flash_on_line_change and "flashui" or "partial"
    for _, region in ipairs(Geometry.slotChanges(viewport, old_slot, new_slot)) do
        -- Clean residual text when covering or exposing a strip.
        -- Uses flashui if regional flashing is enabled, partial otherwise.
        UIManager:setDirty(self.view.dialog, refresh_mode, Geom:new(region))
    end
end

function Typoscope:setEnabled(enabled)
    if not self.is_supported then return false end
    self.is_enabled = enabled
    self.page_turn_direction = nil
    self.settings:saveSetting("enabled", enabled)
    self:refreshLines(true)
    self:redraw()
end

function Typoscope:onTyposcopeToggle()
    if not self.is_supported then return false end
    self:setEnabled(not self.is_enabled)
    return true
end

function Typoscope:turnPage(direction)
    -- Let KOReader clamp the destination and handle hidden flows, scroll limits
    -- and end-of-book actions. Page numbers are not scroll-position boundaries.
    self.page_turn_direction = direction
    self.ui:handleEvent(Event:new("GotoViewRel", direction))
    self:onPageUpdate()
    self.page_turn_direction = nil
    if self.is_supported then self:redraw() end
    return true
end

function Typoscope:moveLine(direction)
    if not self.is_supported or not self.is_enabled then return false end
    if #self.lines == 0 or (self.leave_image_pages_unmasked and self:pageHasImages()) then
        return self:turnPage(direction)
    end
    local next_index = self.line_index + direction
    if next_index < 1 or next_index > #self.lines then return self:turnPage(direction) end
    local viewport = self:getViewport()
    local old_slot = self:getSlot(viewport)
    self.line_index = next_index
    self:redrawSlotChange(viewport, old_slot)
    return true
end

function Typoscope:onTyposcopeNextLine()
    return self:moveLine(1)
end

function Typoscope:onTyposcopePreviousLine()
    return self:moveLine(-1)
end

function Typoscope:onPageUpdate()
    if not self.is_supported or not self.ui.document then return end
    local changed = self:getLocation() ~= self.location
    self:refreshLines(changed)
    if changed and self.page_turn_direction == -1 then
        self.line_index = math.max(1, #self.lines)
    end
end

Typoscope.onPosUpdate = Typoscope.onPageUpdate

function Typoscope:onReaderFooterVisibilityChange()
    if not self.is_supported or not self.is_enabled then return end
    local current_line = self.lines[self.line_index]
    self:refreshLines(false)
    -- Footer toggles do not reflow text. Preserve the same visual line even
    -- when newly exposed lines on the left shift a right-page line's index.
    if current_line then
        for index, line in ipairs(self.lines) do
            if line.y == current_line.y and line.area.x == current_line.area.x then
                self.line_index = index
                break
            end
        end
    end
    -- KOReader may otherwise repaint only the footer, leaving the mask stale.
    self:redraw()
end

function Typoscope:onCloseDocument()
    self.is_enabled = false
    self.is_supported = false
    self.page_turn_direction = nil
    local rolling = self.ui.rolling
    if self.touch_setup_wrapper and rolling.setupTouchZones == self.touch_setup_wrapper then
        rolling.setupTouchZones = self.original_touch_setup
    end
    if self.touch_setup_wrapper then
        self.ui:unRegisterTouchZones({
            { id = "typoscope_tap_forward", overrides = { "tap_forward" } },
            { id = "typoscope_tap_backward", overrides = { "tap_backward" } },
        })
    end
end

function Typoscope:resetLayout()
    if not self.is_supported then return end
    self:refreshLines(false)
    self:setupTouchZones()
end

function Typoscope:onScreenResize()
    if not self.is_supported then return end
    self:setupTouchZones()
    self:refreshLines(false)
    self:redraw()
end

function Typoscope:addToMainMenu(menu_items)
    menu_items.typoscope = {
        text = _("Typoscope reading mask"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Enable mask"),
                checked_func = function() return self.is_enabled end,
                callback = function() self:setEnabled(not self.is_enabled) end,
            },
            {
                text = _("Next line"),
                enabled_func = function() return self.is_enabled end,
                callback = function() self:onTyposcopeNextLine() end,
            },
            {
                text = _("Previous line"),
                enabled_func = function() return self.is_enabled end,
                callback = function() self:onTyposcopePreviousLine() end,
            },
            {
                text = _("Flash screen on line change"),
                checked_func = function() return self.flash_on_line_change end,
                callback = function()
                    self.flash_on_line_change = not self.flash_on_line_change
                    self.settings:saveSetting("flash_on_line_change", self.flash_on_line_change)
                end,
            },
            {
                text = _("Line padding"),
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Line padding"),
                        value = self.line_padding,
                        value_min = 0,
                        value_max = 30,
                        value_step = 1,
                        callback = function(spin)
                            self.line_padding = spin.value
                            self.settings:saveSetting("line_padding", self.line_padding)
                            self:redraw()
                        end,
                    })
                end,
            },
            {
                text = _("Leave pages containing images unmasked"),
                checked_func = function() return self.leave_image_pages_unmasked end,
                callback = function()
                    self.leave_image_pages_unmasked = not self.leave_image_pages_unmasked
                    self.settings:saveSetting("leave_image_pages_unmasked", self.leave_image_pages_unmasked)
                    self:redraw()
                end,
            },
        },
    }
end

function Typoscope:onFlushSettings()
    self.settings:flush()
end

return Typoscope
