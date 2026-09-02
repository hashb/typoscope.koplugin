local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local LuaSettings = require("luasettings")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

local Geometry = require("geometry")

local Typoscope = Widget:extend{
    name = "typoscope",
    is_doc_only = true,
    is_enabled = false,
    leave_image_pages_unmasked = false,
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
    self.line_padding = self.settings:readSetting("line_padding") or self.line_padding
    self.manual_height = self.settings:readSetting("manual_height") or self.manual_height
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
    for _, region in ipairs(Geometry.slotChanges(viewport, old_slot, new_slot)) do
        -- Clean residual text when covering or exposing a strip. "flashui"
        -- flashes only this region and does not advance the page-refresh counter.
        -- Keep repainting the reader so newly exposed text is restored.
        UIManager:setDirty(self.view.dialog, "flashui", Geom:new(region))
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
            self.line_index = 1
            page_turn = true
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", 1))
        end
    else
        local step = self.manual_height / Screen:getHeight()
        if self.manual_center + step > 0.95 then
            self.manual_center = 0.05
            page_turn = true
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", 1))
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
            self.show_last_line_after_page_turn = true
            page_turn = true
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", -1))
        end
    else
        local step = self.manual_height / Screen:getHeight()
        if self.manual_center - step < 0.05 then
            self.manual_center = 0.95
            page_turn = true
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", -1))
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
    if self.show_last_line_after_page_turn then
        self.show_last_line_after_page_turn = nil
        self.line_index = math.max(1, #self.lines)
    end
end

Typoscope.onPosUpdate = Typoscope.onPageUpdate

function Typoscope:resetLayout()
    self:refreshLines(false)
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
