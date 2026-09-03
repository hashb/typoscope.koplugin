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

local Geometry
local ok, mod = pcall(require, "plugins/typoscope.koplugin/geometry")
if ok and mod then
    Geometry = mod
else
    Geometry = require("geometry")
end

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
    manual_height = 42,
    manual_center = 0.35,
    lines = nil,
}

function Typoscope:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/typoscope.lua")
    self.is_enabled = self.settings:isTrue("enabled")
    self.leave_image_pages_unmasked = self.settings:isTrue("leave_image_pages_unmasked")
    self.flash_on_line_change = self.settings:nilOrTrue("flash_on_line_change")
    self.line_padding = self.settings:readSetting("line_padding") or scaleBySize(self.line_padding)
    self.manual_height = self.settings:readSetting("manual_height") or scaleBySize(self.manual_height)
    self.manual_center = self.settings:readSetting("manual_center") or self.manual_center
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

function Typoscope:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("typoscope", self)
    self:refreshLines(true)
    self:setupTouchZones()
end

function Typoscope:setupTouchZones()
    if not Device:isTouchDevice() then return end

    local forward_zone, backward_zone = self.view:getTapZones()
    self.ui:registerTouchZones({
        {
            id = "typoscope_tap_forward",
            ges = "tap",
            screen_zone = forward_zone,
            overrides = { "tap_forward" },
            handler = function()
                if self.is_enabled then return self:onTyposcopeNextLine() end
            end,
        },
        {
            id = "typoscope_tap_backward",
            ges = "tap",
            screen_zone = backward_zone,
            overrides = { "tap_backward" },
            handler = function()
                if self.is_enabled then return self:onTyposcopePreviousLine() end
            end,
        },
    })
end

function Typoscope:getViewport()
    local area = self.view and self.view.visible_area
    if area and area.w > 0 and area.h > 0 then
        return { x = area.x, y = area.y, w = area.w, h = area.h }
    end
    return { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
end

function Typoscope:refreshLines(reset)
    if reset then self.line_index = 1 end
    self.lines = {}
    if not self.is_enabled or not self.ui or not self.ui.rolling then return end

    local viewport = self:getViewport()
    local ok, result = pcall(self.ui.document.getTextFromPositions, self.ui.document,
        { x = viewport.x, y = viewport.y },
        { x = viewport.x + viewport.w, y = viewport.y + viewport.h }, true)
    if ok and result and result.pos0 and result.pos1
            and self.ui.document.getScreenBoxesFromPositions then
        local boxes_ok, boxes = pcall(self.ui.document.getScreenBoxesFromPositions,
            self.ui.document, result.pos0, result.pos1, true)
        if boxes_ok then self.lines = Geometry.normaliseLines(boxes, viewport) end
    end
    self.line_index = math.max(1, math.min(self.line_index, math.max(1, #self.lines)))
end

function Typoscope:getSlot(viewport)
    if #self.lines > 0 then
        return Geometry.slotForLine(viewport, self.lines[self.line_index], self.line_padding)
    end
    return Geometry.manualSlot(viewport, self.manual_center, self.manual_height)
end

function Typoscope:pageHasImages()
    if not self.ui or not self.ui.document.getDrawnImagesStatistics then return false end
    local count = self.ui.document:getDrawnImagesStatistics()
    return count and count > 0
end

function Typoscope:paintTo(bb, x, y)
    if not self.is_enabled then return end
    if self.leave_image_pages_unmasked and self:pageHasImages() then return end
    local viewport = self:getViewport()
    local slot = self:getSlot(viewport)
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
    local refresh_mode = self.flash_on_line_change and "flashui" or "partial"
    for _, region in ipairs(Geometry.slotChanges(viewport, old_slot, new_slot)) do
        -- Clean residual text when covering or exposing a strip.
        -- Uses flashui if regional flashing is enabled, partial otherwise.
        UIManager:setDirty(self.view.dialog, refresh_mode, Geom:new(region))
    end
end

function Typoscope:setEnabled(enabled)
    self.is_enabled = enabled
    self.show_last_line_after_page_turn = nil
    self.settings:saveSetting("enabled", enabled)
    self:refreshLines(true)
    self:redraw()
end

function Typoscope:onTyposcopeToggle()
    self:setEnabled(not self.is_enabled)
    return true
end

function Typoscope:onTyposcopeNextLine()
    if not self.is_enabled then return false end
    local viewport = self:getViewport()
    local old_slot = self:getSlot(viewport)
    local page_turn = false
    self.show_last_line_after_page_turn = nil
    if #self.lines > 0 then
        if self.line_index < #self.lines then
            self.line_index = self.line_index + 1
        else
            local cur_page = self.ui and self.ui.document and self.ui.document.getCurrentPage and self.ui.document:getCurrentPage()
            local total_pages = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount()
            if cur_page and total_pages and cur_page >= total_pages then
                return true
            end
            self.line_index = 1
            page_turn = true
            self.ui:handleEvent(Event:new("GotoViewRel", 1))
        end
    else
        local min_center = (self.manual_height / 2) / viewport.h
        local max_center = 1 - min_center
        local step = self.manual_height / viewport.h
        if self.manual_center + step > max_center then
            local cur_page = self.ui and self.ui.document and self.ui.document.getCurrentPage and self.ui.document:getCurrentPage()
            local total_pages = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount()
            if cur_page and total_pages and cur_page >= total_pages then
                self.manual_center = max_center
                self.settings:saveSetting("manual_center", self.manual_center)
                self:redrawSlotChange(viewport, old_slot)
                return true
            end
            self.manual_center = min_center
            page_turn = true
            self.ui:handleEvent(Event:new("GotoViewRel", 1))
        else
            self.manual_center = self.manual_center + step
        end
        self.settings:saveSetting("manual_center", self.manual_center)
    end
    if page_turn then
        self:redraw()
    else
        self:redrawSlotChange(viewport, old_slot)
    end
    return true
end

function Typoscope:onTyposcopePreviousLine()
    if not self.is_enabled then return false end
    local viewport = self:getViewport()
    local old_slot = self:getSlot(viewport)
    local page_turn = false
    if #self.lines > 0 then
        if self.line_index > 1 then
            self.line_index = self.line_index - 1
        else
            local cur_page = self.ui and self.ui.document and self.ui.document.getCurrentPage and self.ui.document:getCurrentPage()
            if cur_page and cur_page <= 1 then
                return true
            end
            self.show_last_line_after_page_turn = true
            page_turn = true
            self.ui:handleEvent(Event:new("GotoViewRel", -1))
            local new_page = self.ui and self.ui.document and self.ui.document.getCurrentPage and self.ui.document:getCurrentPage()
            if new_page and new_page == cur_page then
                self.show_last_line_after_page_turn = nil
            end
        end
    else
        local min_center = (self.manual_height / 2) / viewport.h
        local max_center = 1 - min_center
        local step = self.manual_height / viewport.h
        if self.manual_center - step < min_center then
            local cur_page = self.ui and self.ui.document and self.ui.document.getCurrentPage and self.ui.document:getCurrentPage()
            if cur_page and cur_page <= 1 then
                self.manual_center = min_center
                self.settings:saveSetting("manual_center", self.manual_center)
                self:redrawSlotChange(viewport, old_slot)
                return true
            end
            self.show_last_line_after_page_turn = true
            self.manual_center = max_center
            page_turn = true
            self.ui:handleEvent(Event:new("GotoViewRel", -1))
            local new_page = self.ui and self.ui.document and self.ui.document.getCurrentPage and self.ui.document:getCurrentPage()
            if new_page and new_page == cur_page then
                self.show_last_line_after_page_turn = nil
            end
        else
            self.manual_center = self.manual_center - step
        end
        self.settings:saveSetting("manual_center", self.manual_center)
    end
    if page_turn then
        self:redraw()
    else
        self:redrawSlotChange(viewport, old_slot)
    end
    return true
end

function Typoscope:onPageUpdate()
    self:refreshLines(true)
    local viewport = self:getViewport()
    local min_center = (self.manual_height / 2) / viewport.h
    local max_center = 1 - min_center
    if self.show_last_line_after_page_turn then
        self.show_last_line_after_page_turn = nil
        if #self.lines > 0 then
            self.line_index = math.max(1, #self.lines)
        else
            self.manual_center = max_center
            self.settings:saveSetting("manual_center", self.manual_center)
        end
    else
        if #self.lines == 0 then
            self.manual_center = min_center
            self.settings:saveSetting("manual_center", self.manual_center)
        end
    end
end

Typoscope.onPosUpdate = Typoscope.onPageUpdate

function Typoscope:resetLayout()
    self:refreshLines(false)
    self:setupTouchZones()
end

function Typoscope:onScreenResize()
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
                text = _("Reading slot height"),
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Reading slot height"),
                        value = self.manual_height,
                        value_min = 10,
                        value_max = 500,
                        value_step = 2,
                        callback = function(spin)
                            self.manual_height = spin.value
                            self.settings:saveSetting("manual_height", self.manual_height)
                            self:redraw()
                        end,
                    })
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
