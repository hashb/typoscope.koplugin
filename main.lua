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
    self.show_last_line_after_page_turn = nil
    if #self.lines > 0 then
        if self.line_index < #self.lines then
            self.line_index = self.line_index + 1
        else
            self.line_index = 1
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", 1))
        end
    else
        local step = self.manual_height / Screen:getHeight()
        if self.manual_center + step > 0.95 then
            self.manual_center = 0.05
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", 1))
        else
            self.manual_center = self.manual_center + step
        end
        self.settings:saveSetting("manual_center", self.manual_center)
    end
    self:redraw()
    return true
end

function Typoscope:onTyposcopePreviousLine()
    if not self.is_enabled then return false end
    if #self.lines > 0 then
        if self.line_index > 1 then
            self.line_index = self.line_index - 1
        else
            self.show_last_line_after_page_turn = true
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", -1))
        end
    else
        local step = self.manual_height / Screen:getHeight()
        if self.manual_center - step < 0.05 then
            self.manual_center = 0.95
            self.ui:handleEvent(require("ui/event"):new("GotoViewRel", -1))
        else
            self.manual_center = self.manual_center - step
        end
        self.settings:saveSetting("manual_center", self.manual_center)
    end
    self:redraw()
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
