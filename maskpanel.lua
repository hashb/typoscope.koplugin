-- A compact settings panel docked at the screen edge away from the reading
-- line, so each change previews on the page immediately. KOReader's touch menu
-- rows cannot host sliders, so this follows the Frontlight panel's approach.
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local FONT_SIZE = 16

local MaskPanel = FocusManager:extend{
    name = "typoscope_mask_panel",
    typoscope = nil,
    -- Each row is either { label, options = {{text, value}}, value(), apply(value) }
    -- or a slider: { label, min, max, step, default, value(), apply(value), format(value) }.
    rows = nil,
}

function MaskPanel:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.width = math.floor(screen_w * 0.95)
    local inner_width = self.width - 2 * Size.padding.default
    self.label_width = math.floor(inner_width * 0.3)
    self.control_width = inner_width - self.label_width
    self.face = Font:getFace("cfont", FONT_SIZE)

    self.layout = {}
    local group = VerticalGroup:new{ align = "left" }
    for index, row in ipairs(self.rows) do
        local control
        if row.options then
            row.group = HorizontalGroup:new{}
            row.layout_index = #self.layout + 1
            self:buildChoices(row)
            control = row.group
        else
            control = self:buildSlider(row)
            self:mergeLayoutInVertical(control)
        end
        row.text = TextWidget:new{
            text = self:getLabel(row),
            face = self.face,
            max_width = self.label_width - Size.padding.default,
        }
        if index > 1 then group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_default } end
        group[#group + 1] = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = self.label_width, h = control:getSize().h },
                row.text,
            },
            control,
        }
    end

    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.default,
        background = Blitbuffer.COLOR_WHITE,
        group,
    }
    self[1] = self.frame

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h } },
        }
    end
end

function MaskPanel:getLabel(row)
    if row.options then return row.label end
    return row.label .. " (" .. row.format(row.value()) .. ")"
end

-- A segmented choice: the current option is drawn inverted, like the filled
-- part of a slider.
function MaskPanel:buildChoices(row)
    row.group:clear()
    row.buttons = {}
    -- Button widths include their margins; the last one takes the rounding
    -- remainder so the row ends where the sliders do.
    local width = math.floor(self.control_width / #row.options)
    for index, option in ipairs(row.options) do
        local button = Button:new{
            text = option.text,
            width = index < #row.options and width or self.control_width - (#row.options - 1) * width,
            radius = 0,
            margin = Size.margin.tiny,
            padding = Size.padding.small,
            text_font_size = FONT_SIZE,
            preselect = option.value == row.value(),
            show_parent = self,
            callback = function() self:onChoice(row, option.value) end,
        }
        row.group[#row.group + 1] = button
        row.buttons[#row.buttons + 1] = button
    end
    self.layout[row.layout_index] = row.buttons
end

function MaskPanel:onChoice(row, value)
    row.apply(value)
    self:buildChoices(row)
    self:refocusWidget()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function MaskPanel:buildSlider(row)
    row.progress = ButtonProgressWidget:new{
        width = self.control_width,
        font_size = FONT_SIZE,
        padding = 0,
        num_buttons = (row.max - self:getFirstValue(row)) / row.step + 1,
        position = self:getPosition(row, row.value()),
        default_position = self:getPosition(row, row.default),
        fine_tune = true,
        show_parent = self,
        callback = function(choice) self:onSliderChoice(row, choice) end,
    }
    return row.progress
end

-- Segments start at the first non-zero value, so a zero setting shows as an
-- empty bar that the "−" button reaches.
function MaskPanel:getFirstValue(row)
    return row.min == 0 and row.step or row.min
end

function MaskPanel:getPosition(row, value)
    return math.floor((value - self:getFirstValue(row)) / row.step) + 1
end

function MaskPanel:onSliderChoice(row, choice)
    local value
    if choice == "-" then
        value = row.value() - row.step
    elseif choice == "+" then
        value = row.value() + row.step
    else
        value = self:getFirstValue(row) + (choice - 1) * row.step
    end
    value = math.max(row.min, math.min(value, row.max))
    row.apply(value)
    row.text:setText(self:getLabel(row))
    row.progress:setPosition(self:getPosition(row, row.value()), self:getPosition(row, row.default))
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

-- Dock opposite the reading line, so the preview stays in view.
function MaskPanel:getOrigin()
    local size = self.frame:getSize()
    local plugin = self.typoscope
    local line = plugin.lines and plugin.lines[plugin.line_index]
    local margin = Size.margin.default
    local x = math.floor((Screen:getWidth() - size.w) / 2)
    if line and line.y + line.h / 2 > Screen:getHeight() / 2 then return x, margin end
    return x, Screen:getHeight() - size.h - margin
end

function MaskPanel:show()
    local x, y = self:getOrigin()
    UIManager:show(self, "ui", nil, x, y)
end

function MaskPanel:onTapClose(arg, ges)
    if self.frame.dimen and not ges.pos:intersectWith(self.frame.dimen) then
        self:onClose()
    end
    -- Swallow taps inside the panel that miss a button.
    return true
end

function MaskPanel:onClose()
    UIManager:close(self)
    return true
end

function MaskPanel:onCloseWidget()
    -- Live previews use quick refreshes; clean up the ghosting once at the end.
    self.typoscope:redraw(true)
end

return MaskPanel
