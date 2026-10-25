local spec_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local newPlugin = dofile(spec_dir .. "helpers.lua").newPlugin

local function paint(plugin)
    local rects = {}
    plugin:paintTo({ paintRect = function(_, x, y, w, h)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h }
    end }, 0, 0)
    return rects
end

describe("reflowable document support", function()
    it("registers the Tools menu and view module for EPUBs", function()
        local plugin, state = newPlugin{file = "BOOK.EPUB", enabled = false}
        assert.is_true(plugin.is_doc_only)
        assert.are.equal(plugin, state.modules.typoscope)
        assert.are.equal("more_tools", state.menu.typoscope.sorting_hint)
        local toggle = state.menu.typoscope.sub_item_table[1]
        assert.is_false(toggle.checked_func())
        toggle.callback()
        assert.is_true(toggle.checked_func())
        assert.are.equal(2, #plugin.lines)
        toggle.callback()
        assert.is_false(toggle.checked_func())
        assert.is_false(state.settings.enabled)
    end)

    it("uses the same mask and navigation for other reflowable formats", function()
        for _, file in ipairs({"book.mobi", "book.azw", "book.fb2", "book.html", "book.txt", "book.rtf", "book.fb2.zip", "book.custom"}) do
            local plugin, state = newPlugin{file = file}
            assert.is_true(plugin.is_enabled)
            assert.are.equal(plugin, state.modules.typoscope)
            assert.is_not_nil(state.menu.typoscope)
            assert.are.equal(2, #plugin.lines)
            assert.are.equal(2, #paint(plugin))
            assert.is_true(state.zones.typoscope_tap_forward.handler())
            assert.are.equal(2, plugin.line_index)
            assert.is_true(plugin:onTyposcopeNextLine())
            assert.are.equal(3, state.page)
            assert.are.equal(1, plugin.line_index)
        end
    end)

    it("stays inactive on fixed-layout documents without erasing the mask preference", function()
        for _, file in ipairs({"book.pdf", "book.djvu", "book.cbz"}) do
            local plugin, state = newPlugin{file = file, paging = true}
            assert.is_false(plugin.is_enabled)
            assert.is_false(plugin:onTyposcopeToggle())
            assert.is_false(plugin:onTyposcopeNextLine())
            assert.is_false(plugin:onTyposcopePreviousLine())
            plugin:setEnabled(true)
            plugin:onPageUpdate()
            plugin:onScreenResize()
            plugin:onReaderFooterVisibilityChange()
            assert.are.same({}, state.menu)
            assert.are.same({}, state.modules)
            assert.are.same({}, state.zones)
            assert.are.same({}, paint(plugin))
            assert.are.same({}, state.events)
            assert.are.same({}, state.dirty)
            assert.is_true(state.settings.enabled)
            plugin:onCloseDocument()
        end
    end)

    it("requires the reflowable reader even for a file named .epub", function()
        local plugin, state = newPlugin{paging = true}
        assert.is_false(plugin.is_enabled)
        assert.are.same({}, state.modules)
        plugin:onCloseDocument()
    end)

    it("requires the document APIs used by line tracking and navigation", function()
        for _, method in ipairs({"getTextFromPositions", "getCurrentPage", "getCurrentPos", "getVisiblePageCount", "getPageCount"}) do
            local plugin, state = newPlugin{file = "book.mobi", missing_document_method = method}
            assert.is_false(plugin.is_enabled)
            assert.is_false(plugin:onTyposcopeToggle())
            assert.are.same({}, state.modules)
            assert.are.same({}, state.zones)
            assert.are.same({}, paint(plugin))
            assert.is_true(state.settings.enabled)
        end
    end)

    it("leaves blank and unextractable EPUB pages visible with normal navigation", function()
        for _, fail in ipairs({false, true}) do
            local plugin, state = newPlugin{boxes = {}}
            state.extraction_error = fail
            plugin:refreshLines(true)
            assert.is_nil(plugin:getSlot(plugin:getViewport()))
            assert.are.same({}, paint(plugin))
            assert.is_true(plugin:onTyposcopeNextLine())
            assert.are.equal(3, state.page)
            assert.are.equal(1, #state.events)
        end
    end)

    it("keeps image pages unmasked and turns them with one tap", function()
        local plugin, state = newPlugin()
        plugin.leave_image_pages_unmasked = true
        state.image_count = 1
        assert.are.same({}, paint(plugin))
        plugin:onTyposcopeNextLine()
        assert.are.equal(3, state.page)
        for _, dirty in ipairs(state.dirty) do assert.are.equal("partial", dirty.mode) end
    end)

    it("keeps the footer outside the mask and ignores document-space offsets", function()
        local plugin = newPlugin()
        plugin.view.visible_area = { x = 120, y = 900, w = 600, h = 800 }
        plugin.view.footer_visible = true
        assert.are.same({ x = 0, y = 0, w = 600, h = 760 }, plugin:getViewport())
        for _, rect in ipairs(paint(plugin)) do assert.is_true(rect.y + rect.h <= 760) end
    end)

    it("flushes the remaining plugin preferences", function()
        local plugin, state = newPlugin()
        plugin:onFlushSettings()
        assert.is_true(state.flushed)
        state.flushed = nil
        plugin:onSaveSettings()
        assert.is_true(state.flushed)
    end)

    it("flashes the whole screen when the mask is toggled, unless flashes are disabled", function()
        local plugin, state = newPlugin()
        plugin:setEnabled(false)
        assert.are.same({{widget=plugin.view.dialog, mode="full"}}, state.dirty)
        state.dirty = {}
        plugin.flash_on_line_change = false
        plugin:setEnabled(true)
        assert.are.same({{widget=plugin.view.dialog, mode="partial"}}, state.dirty)
    end)
end)

describe("mask color", function()
    local function paintColors(plugin)
        local colors = {}
        plugin:paintTo({ paintRect = function(_, _, _, _, _, color)
            colors[color] = (colors[color] or 0) + 1
        end }, 0, 0)
        return colors
    end

    it("paints a dark mask by default", function()
        local plugin = newPlugin()
        assert.are.equal("dark", plugin.mask_color)
        assert.are.same({ [0] = 2 }, paintColors(plugin))
    end)

    it("switches to a light mask, saves it, and flashes the screen", function()
        local plugin, state = newPlugin()
        plugin:setMaskColor("light")
        assert.are.equal("light", plugin.mask_color)
        assert.are.equal("light", state.settings.mask_color)
        assert.are.same({ [255] = 2 }, paintColors(plugin))
        assert.are.same({{widget=plugin.view.dialog, mode="full"}}, state.dirty)
        -- Reselecting the current color changes nothing.
        plugin:setMaskColor("light")
        assert.are.equal(1, #state.dirty)
        plugin.flash_on_line_change = false
        plugin:setMaskColor("dark")
        assert.are.equal("dark", state.settings.mask_color)
        assert.are.same({widget=plugin.view.dialog, mode="partial"}, state.dirty[2])
    end)

    it("restores the saved color and falls back to dark for unknown values", function()
        local plugin = newPlugin()
        plugin.settings:saveSetting("mask_color", "light")
        plugin:init()
        plugin:refreshLines(true)
        assert.are.equal("light", plugin.mask_color)
        assert.are.same({ [255] = 2 }, paintColors(plugin))
        plugin.settings:saveSetting("mask_color", "purple")
        plugin:init()
        assert.are.equal("dark", plugin.mask_color)
    end)
end)

describe("mask mode", function()
    it("defaults to both masks", function()
        local plugin = newPlugin()
        assert.are.equal("both", plugin.mask_mode)
        assert.are.same({{x=0,y=0,w=600,h=97}, {x=0,y=123,w=600,h=677}}, paint(plugin))
    end)

    it("saves changes, preserves the line, and respects the flash preference", function()
        local plugin, state = newPlugin()
        plugin.line_index = 2
        for index, mode in ipairs({"top", "bottom", "both"}) do
            plugin:setMaskMode(mode)
            assert.are.equal(mode, plugin.mask_mode)
            assert.are.equal(mode, state.settings.mask_mode)
            assert.are.equal(2, plugin.line_index)
            assert.are.same({widget=plugin.view.dialog,mode=index == 1 and "full" or "partial"}, state.dirty[index])
            plugin:setMaskMode(mode) -- Reselecting the current mode changes nothing.
            assert.are.equal(index, #state.dirty)
            plugin.flash_on_line_change = false
        end
    end)

    it("restores saved modes and falls back to both for unknown values", function()
        local plugin = newPlugin()
        for _, mode in ipairs({"top", "bottom", "both", "unknown"}) do
            plugin.settings:saveSetting("mask_mode", mode)
            plugin:init()
            assert.are.equal(mode == "unknown" and "both" or mode, plugin.mask_mode)
        end
        plugin:setMaskMode("top")
        plugin:setMaskMode("unknown")
        assert.are.equal("both", plugin.mask_mode)
    end)

    it("paints only the selected side in page and scroll modes, keeping the footer visible", function()
        for _, view_mode in ipairs({"page", "scroll"}) do
            local plugin = newPlugin{mode=view_mode}
            plugin.view.footer_visible = true
            plugin:refreshLines(true)
            plugin:setMaskMode("top")
            assert.are.same({{x=0,y=0,w=600,h=97}}, paint(plugin))
            plugin:setMaskMode("bottom")
            assert.are.same({{x=0,y=123,w=600,h=637}}, paint(plugin))
        end
    end)

    it("refreshes only the moving mask edge in either direction", function()
        for _, mode in ipairs({"top", "bottom"}) do
            local plugin, state = newPlugin()
            plugin:setMaskMode(mode)
            for _, method in ipairs({"onTyposcopeNextLine", "onTyposcopePreviousLine"}) do
                state.dirty = {}
                assert.is_true(plugin[method](plugin))
                assert.are.same({{
                    widget=plugin.view.dialog, mode="flashui",
                    region={x=0,y=mode == "top" and 97 or 123,w=600,h=25},
                }}, state.dirty)
            end
        end
    end)

    it("keeps the inactive page covered and refreshes the exposed areas when crossing a spread", function()
        for _, mode in ipairs({"top", "bottom"}) do
            local plugin, state = newPlugin{visible_pages=2,boxes={
                {x=20,y=100,w=240,h=20}, {x=320,y=100,w=240,h=20},
            }}
            plugin:setMaskMode(mode)
            local edge = mode == "top" and 97 or 123
            local mask = mode == "top" and {x=0,y=0,w=600,h=edge}
                or {x=0,y=edge,w=600,h=800-edge}
            local visible_y = mode == "top" and edge or 0
            local visible_h = mode == "top" and 800-edge or edge
            assert.are.same({mask, {x=300,y=visible_y,w=300,h=visible_h}}, paint(plugin))
            for _, method in ipairs({"onTyposcopeNextLine", "onTyposcopePreviousLine"}) do
                state.dirty = {}
                plugin[method](plugin)
                assert.are.same({
                    {widget=plugin.view.dialog,mode="flashui",region={x=0,y=visible_y,w=300,h=visible_h}},
                    {widget=plugin.view.dialog,mode="flashui",region={x=300,y=visible_y,w=300,h=visible_h}},
                }, state.dirty)
                local inactive_x = plugin.line_index == 1 and 300 or 0
                assert.are.same({mask, {x=inactive_x,y=visible_y,w=300,h=visible_h}}, paint(plugin))
            end
            assert.are.same({}, state.events)
        end
    end)
end)

local function menuItem(state, text)
    for _, item in ipairs(state.menu.typoscope.sub_item_table) do
        if item.text == text then return item end
    end
end

describe("mask opacity", function()
    local function paintCalls(plugin, legacy)
        local calls = {}
        local bb = {
            setPixelBlend = "blend",
            paintRect = function(_, x, y, w, h, color, setter)
                calls[#calls + 1] = { "paint", color, setter }
            end,
        }
        if not legacy then
            bb.darkenRect = function(_, x, y, w, h, by) calls[#calls + 1] = { "darken", by } end
            bb.lightenRect = function(_, x, y, w, h, by) calls[#calls + 1] = { "lighten", by } end
        end
        plugin:paintTo(bb, 0, 0)
        return calls
    end

    it("defaults to an opaque fill and restores clamped saved values", function()
        local plugin = newPlugin()
        assert.are.equal(100, plugin.mask_opacity)
        assert.are.same({{"paint", 0}, {"paint", 0}}, paintCalls(plugin))
        for saved, expected in pairs({ [40] = 40, [0] = 10, [250] = 100, bogus = 100 }) do
            plugin.settings:saveSetting("mask_opacity", saved ~= "bogus" and saved or "50")
            plugin:init()
            assert.are.equal(expected, plugin.mask_opacity)
        end
    end)

    it("saves the value, flashes the screen and blends in the mask color", function()
        local plugin, state = newPlugin()
        plugin:setMaskOpacity(60)
        assert.are.equal(60, state.settings.mask_opacity)
        assert.are.same({{widget=plugin.view.dialog, mode="full"}}, state.dirty)
        assert.are.same({{"darken", 0.6}, {"darken", 0.6}}, paintCalls(plugin))
        plugin:setMaskColor("light")
        assert.are.same({{"lighten", 0.6}, {"lighten", 0.6}}, paintCalls(plugin))
        plugin:setMaskOpacity(60) -- Unchanged values do not redraw.
        assert.are.equal(2, #state.dirty)
    end)

    it("falls back to a per-pixel blend without the C blend helpers", function()
        local plugin = newPlugin()
        plugin:setMaskOpacity(50)
        assert.are.same({"paint", {value=0, alpha=127}, "blend"}, paintCalls(plugin, true)[1])
    end)
end)

describe("lines above and below", function()
    local boxes = {
        {x=20,y=100,w=400,h=20}, {x=20,y=125,w=400,h=20},
        {x=20,y=150,w=400,h=20}, {x=20,y=175,w=400,h=20},
    }

    it("defaults to the reading line alone and restores clamped saved values", function()
        local plugin = newPlugin()
        assert.are.same({0, 0}, {plugin.lines_above, plugin.lines_below})
        for saved, expected in pairs({ [2] = 2, [-1] = 0, [9] = 5, bogus = 0 }) do
            plugin.settings:saveSetting("lines_above", saved ~= "bogus" and saved or "2")
            plugin.settings:saveSetting("lines_below", saved ~= "bogus" and saved or "2")
            plugin:init()
            assert.are.same({expected, expected}, {plugin.lines_above, plugin.lines_below})
        end
    end)

    it("saves each count and flashes unless a slider is previewing", function()
        local plugin, state = newPlugin()
        plugin:setContextLines("above", 2)
        plugin:setContextLines("below", 3, true)
        assert.are.same({2, 3}, {state.settings.lines_above, state.settings.lines_below})
        assert.are.same({
            {widget=plugin.view.dialog, mode="full"}, {widget=plugin.view.dialog, mode="partial"},
        }, state.dirty)
        plugin:setContextLines("above", 2) -- Unchanged values do not redraw.
        assert.are.equal(2, #state.dirty)
    end)

    it("uncovers lines on both sides of the reading line, trimmed at page edges", function()
        local plugin, state = newPlugin{boxes=boxes}
        plugin:setContextLines("above", 1)
        plugin:setContextLines("below", 1)
        local function slot() return plugin:getSlot(plugin:getViewport()) end
        assert.are.same({x=0,y=97,w=600,h=51}, slot()) -- No line above the first.
        state.dirty = {}
        plugin:onTyposcopeNextLine()
        assert.are.same({x=0,y=97,w=600,h=76}, slot())
        assert.are.same({{widget=plugin.view.dialog,mode="flashui",region={x=0,y=148,w=600,h=25}}}, state.dirty)
        plugin:onTyposcopeNextLine()
        assert.are.same({x=0,y=122,w=600,h=76}, slot())
        plugin:onTyposcopeNextLine()
        assert.are.same({x=0,y=147,w=600,h=51}, slot()) -- No line below the last.
        assert.are.same({}, state.events)
        plugin:onTyposcopeNextLine()
        assert.are.same({3, 1}, {state.page, plugin.line_index})
        plugin:onTyposcopePreviousLine()
        assert.are.same({2, 4}, {state.page, plugin.line_index})
    end)

    it("can show context above the reading line only", function()
        local plugin = newPlugin{boxes=boxes}
        plugin:setContextLines("above", 2)
        plugin.line_index = 3
        assert.are.same({x=0,y=97,w=600,h=76}, plugin:getSlot(plugin:getViewport()))
        assert.are.same({{x=0,y=0,w=600,h=97}, {x=0,y=173,w=600,h=627}}, paint(plugin))
    end)

    it("never spans both pages of a spread", function()
        local plugin, state = newPlugin{visible_pages=2,boxes={
            {x=20,y=100,w=240,h=20}, {x=320,y=100,w=240,h=20},
            {x=20,y=125,w=240,h=20}, {x=320,y=125,w=240,h=20},
            {x=20,y=150,w=240,h=20}, {x=320,y=150,w=240,h=20},
        }}
        plugin:setContextLines("above", 1)
        plugin:setContextLines("below", 1)
        plugin.line_index = 3
        assert.are.same({x=0,y=122,w=300,h=51}, plugin:getSlot(plugin:getViewport()))
        plugin:onTyposcopeNextLine()
        assert.are.equal(4, plugin.line_index)
        assert.are.same({x=300,y=97,w=300,h=51}, plugin:getSlot(plugin:getViewport()))
        assert.are.same({}, state.events)
    end)
end)

describe("mask settings panel", function()
    local boxes = {
        {x=20,y=100,w=400,h=20}, {x=20,y=125,w=400,h=20},
        {x=20,y=150,w=400,h=20}, {x=20,y=600,w=400,h=20},
    }
    local function pos(inside)
        return { intersectWith = function() return inside end }
    end
    local function selected(row)
        local result = {}
        for _, button in ipairs(row.buttons) do result[#result + 1] = button.preselect end
        return result
    end

    it("replaces the mask submenus with one menu entry", function()
        local _, state = newPlugin()
        local texts = {}
        for _, item in ipairs(state.menu.typoscope.sub_item_table) do texts[#texts + 1] = item.text end
        assert.are.same({"Enable mask", "Flash screen on line change", "Mask settings",
            "Leave pages containing images unmasked"}, texts)
        menuItem(state, "Mask settings").callback()
        assert.are.equal("typoscope_mask_panel", state.shown.name)
    end)

    it("opens with every row set to the current values", function()
        local plugin, state = newPlugin()
        plugin:setMaskOpacity(60)
        plugin:setContextLines("above", 1)
        plugin:showMaskPanel()
        local color, mode, opacity, above, below, padding = unpack(state.shown.rows)
        assert.are.same({"Color", true, false}, {color.text.text, unpack(selected(color))})
        assert.are.same({"Mask", false, false, true}, {mode.text.text, unpack(selected(mode))})
        assert.are.same({"Top", "Bottom", "Both"}, {mode.buttons[1].text, mode.buttons[2].text, mode.buttons[3].text})
        assert.are.same({"Opacity (60%)", 10, 6, 10, true},
            {opacity.text.text, opacity.progress.num_buttons, opacity.progress.position,
             opacity.progress.default_position, opacity.progress.fine_tune})
        -- Zero shows as an empty bar: the segments are 1 to 5.
        assert.are.same({"Above (1)", 5, 1, 0},
            {above.text.text, above.progress.num_buttons, above.progress.position, above.progress.default_position})
        assert.are.same({"Below (0)", 0}, {below.text.text, below.progress.position})
        assert.are.same({"Padding (3)", 10, 1, 1},
            {padding.text.text, padding.progress.num_buttons, padding.progress.position, padding.progress.default_position})
        assert.are.equal(6, #state.shown.layout)
        assert.are.equal(color.buttons, state.shown.layout[1])
    end)

    it("previews choices live and redraws the selected option", function()
        local plugin, state = newPlugin()
        plugin:showMaskPanel()
        local panel = state.shown
        local color, mode = panel.rows[1], panel.rows[2]
        state.dirty = {}
        color.buttons[2].callback()
        assert.are.equal("light", state.settings.mask_color)
        assert.are.same({false, true}, selected(color))
        assert.are.equal(color.buttons, panel.layout[1])
        assert.are.equal(2, #color.group)
        mode.buttons[1].callback()
        assert.are.equal("top", plugin.mask_mode)
        assert.are.same({true, false, false}, selected(mode))
        for _, entry in ipairs(state.dirty) do assert.are_not.equal("full", entry.mode) end
        assert.are.equal(panel, state.dirty[#state.dirty].widget)
    end)

    it("previews each slider step on the page without flashing, then flashes once on close", function()
        local plugin, state = newPlugin{boxes=boxes}
        plugin:showMaskPanel()
        local panel = state.shown
        local _, _, opacity, above, below, padding = unpack(panel.rows)
        state.dirty = {}
        opacity.progress.callback(4)
        assert.are.equal(40, plugin.mask_opacity)
        assert.are.equal(40, state.settings.mask_opacity)
        assert.are.equal("Opacity (40%)", opacity.text.text)
        assert.are.equal(4, opacity.progress.position)
        assert.are.same({widget=plugin.view.dialog, mode="partial"}, state.dirty[1])
        assert.are.equal(panel, state.dirty[2].widget)
        below.progress.callback("+")
        below.progress.callback(2)
        above.progress.callback(1)
        assert.are.same({1, 2}, {plugin.lines_above, plugin.lines_below})
        assert.are.equal("Below (2)", below.text.text)
        assert.are.same({x=0,y=97,w=600,h=76}, plugin:getSlot(plugin:getViewport()))
        padding.progress.callback(4)
        assert.are.equal(12, plugin.line_padding)
        assert.are.equal(12, state.settings.line_padding)
        assert.are.same({x=0,y=88,w=600,h=94}, plugin:getSlot(plugin:getViewport()))
        for _, entry in ipairs(state.dirty) do assert.are_not.equal("full", entry.mode) end
        panel.frame.dimen = {} -- Set when KOReader paints the panel.
        panel:onTapClose(nil, { pos = pos(true) }) -- A tap inside the panel keeps it open.
        assert.is_nil(state.closed)
        state.dirty = {}
        panel:onTapClose(nil, { pos = pos(false) })
        assert.are.equal(panel, state.closed)
        assert.are.same({{widget=plugin.view.dialog, mode="full"}}, state.dirty)
    end)

    it("clamps the fine-tune buttons at both ends", function()
        local plugin, state = newPlugin()
        plugin:showMaskPanel()
        local _, _, opacity, _, below, padding = unpack(state.shown.rows)
        opacity.progress.callback("+")
        assert.are.equal(100, plugin.mask_opacity)
        below.progress.callback("-")
        assert.are.equal(0, plugin.lines_below)
        assert.are.equal(0, below.progress.position)
        opacity.progress.callback(1)
        opacity.progress.callback("-")
        assert.are.equal(10, plugin.mask_opacity)
        below.progress.callback(5)
        below.progress.callback("+")
        assert.are.equal(5, plugin.lines_below)
        padding.progress.callback("-")
        padding.progress.callback("-")
        assert.are.equal(0, plugin.line_padding)
        padding.progress.callback(10)
        padding.progress.callback("+")
        assert.are.equal(30, plugin.line_padding)
    end)

    it("docks away from the reading line so the preview stays visible", function()
        local plugin, state = newPlugin{boxes=boxes}
        plugin:showMaskPanel()
        assert.are.same({x=15, y=495}, state.shown_at) -- Line near the top: dock at the bottom.
        plugin.line_index = 4
        plugin:showMaskPanel()
        assert.are.same({x=15, y=5}, state.shown_at)
    end)

    it("closes with the back key on devices with keys", function()
        local plugin, state = newPlugin()
        state.keys = true
        plugin:showMaskPanel()
        assert.are.same({{"Back"}}, state.shown.key_events.Close)
        assert.is_true(state.shown:onClose())
        assert.are.equal(state.shown, state.closed)
    end)
end)

describe("footer visibility changes", function()
    local boxes = {
        {x=20,y=700,w=240,h=20}, {x=20,y=735,w=240,h=20},
        {x=20,y=770,w=240,h=20},
    }

    it("makes newly exposed bottom lines reachable without scrolling", function()
        local plugin, state = newPlugin{mode="scroll",boxes=boxes}
        plugin.view.footer_visible = true
        plugin:refreshLines(true)
        plugin.line_index = 2
        plugin.view.footer_visible = false
        plugin:onReaderFooterVisibilityChange()
        assert.are.equal(3, #plugin.lines)
        assert.are.equal(2, plugin.line_index)
        plugin:onTyposcopeNextLine()
        assert.are.equal(770, plugin.lines[plugin.line_index].y)
        assert.are.same({}, state.events)
        assert.are.same({widget=plugin.view.dialog,mode="partial"}, state.dirty[1])
    end)

    it("moves a covered bottom line back into the visible area", function()
        local plugin = newPlugin{mode="scroll",boxes=boxes}
        plugin.line_index = 3
        plugin.view.footer_visible = true
        plugin:onReaderFooterVisibilityChange()
        assert.are.equal(2, #plugin.lines)
        assert.are.equal(2, plugin.line_index)
        local slot = plugin:getSlot(plugin:getViewport())
        assert.is_true(slot.h > 0 and slot.y + slot.h <= 760)
        for _, rect in ipairs(paint(plugin)) do assert.is_true(rect.y + rect.h <= 760) end
    end)

    it("preserves the active right-page line when left-page lines become visible", function()
        local plugin = newPlugin{visible_pages=2,boxes={
            boxes[1], boxes[3], {x=320,y=700,w=240,h=20},
        }}
        plugin.view.footer_visible = true
        plugin:refreshLines(true)
        plugin.line_index = 2
        plugin.view.footer_visible = false
        plugin:onReaderFooterVisibilityChange()
        assert.are.equal(3, plugin.line_index)
        assert.are.equal(320, plugin.lines[plugin.line_index].x)
    end)

    it("does not repaint when the mask is disabled", function()
        local plugin, state = newPlugin{enabled=false}
        plugin.view.footer_visible = true
        plugin:onReaderFooterVisibilityChange()
        assert.are.same({}, state.dirty)
    end)
end)

describe("line refreshes", function()
    it("flashes only changed strips in either direction", function()
        local plugin, state = newPlugin()
        for _, method in ipairs({"onTyposcopeNextLine", "onTyposcopePreviousLine"}) do
            state.dirty = {}
            assert.is_true(plugin[method](plugin))
            assert.are.same({
                { widget = plugin.view.dialog, mode = "flashui", region = {x=0,y=97,w=600,h=25} },
                { widget = plugin.view.dialog, mode = "flashui", region = {x=0,y=123,w=600,h=25} },
            }, state.dirty)
        end
    end)

    it("uses partial updates when cleaning flashes are disabled", function()
        local plugin, state = newPlugin()
        plugin.flash_on_line_change = false
        plugin:onTyposcopeNextLine()
        assert.are.equal(2, #state.dirty)
        for _, dirty in ipairs(state.dirty) do assert.are.equal("partial", dirty.mode) end
    end)

    it("does not refresh an unchanged slot or consume actions when disabled", function()
        local plugin, state = newPlugin()
        plugin.lines[2] = plugin.lines[1]
        plugin:onTyposcopeNextLine()
        assert.are.same({}, state.dirty)
        plugin.is_enabled = false
        assert.is_false(plugin:onTyposcopeNextLine())
        assert.is_false(plugin:onTyposcopePreviousLine())
        assert.are.same({}, state.dirty)
    end)
end)

describe("page and scroll navigation", function()
    it("selects the corresponding edge after an actual page turn", function()
        for _, direction in ipairs({-1, 1}) do
            local plugin, state = newPlugin()
            plugin.line_index = direction == 1 and #plugin.lines or 1
            plugin:moveLine(direction)
            assert.are.equal(2 + direction, state.page)
            assert.are.equal(direction == 1 and 1 or #plugin.lines, plugin.line_index)
            assert.are.same({{name="GotoViewRel",direction=direction}}, state.events)
            assert.is_nil(plugin.page_turn_direction)
            assert.are.same({{widget=plugin.view.dialog, mode="partial"}}, state.dirty)
        end
    end)

    it("keeps the selected line at document boundaries without a pending direction", function()
        for _, direction in ipairs({-1, 1}) do
            local plugin, state = newPlugin{page = direction == 1 and 10 or 1}
            local old_index = direction == 1 and #plugin.lines or 1
            plugin.line_index = old_index
            plugin:moveLine(direction)
            assert.are.equal(old_index, plugin.line_index)
            assert.is_nil(plugin.page_turn_direction)
            -- Nothing changed on screen, so no refresh is requested.
            assert.are.same({}, state.dirty)
            -- A later external forward turn must not inherit a failed backward turn.
            state.page = 5
            plugin:onPageUpdate()
            assert.are.equal(1, plugin.line_index)
        end
    end)

    it("preserves the current line on same-page redraw events", function()
        local plugin = newPlugin()
        plugin.line_index = 2
        plugin:onPageUpdate()
        assert.are.equal(2, plugin.line_index)
    end)

    it("can scroll backward while still on page number one", function()
        local plugin, state = newPlugin{mode="scroll",page=1,position=200}
        plugin:onTyposcopePreviousLine()
        assert.are.equal(0, state.position)
        assert.are.equal(#plugin.lines, plugin.line_index)
        assert.is_nil(plugin.page_turn_direction)
    end)

    it("can advance within the last numbered page in scroll mode", function()
        local plugin, state = newPlugin{mode="scroll",page=10,position=7000}
        plugin.line_index = #plugin.lines
        plugin:onTyposcopeNextLine()
        assert.are.equal(state.max_position, state.position)
        assert.are.equal(1, plugin.line_index)
    end)

    it("keeps the line at both scroll limits", function()
        for _, direction in ipairs({-1, 1}) do
            local plugin, state = newPlugin{mode="scroll",position=direction == 1 and 7200 or 0}
            local old_index = direction == 1 and #plugin.lines or 1
            plugin.line_index = old_index
            plugin:moveLine(direction)
            assert.are.equal(old_index, plugin.line_index)
            assert.is_nil(plugin.page_turn_direction)
        end
    end)

    it("uses internal pages when spreads have shared displayed page numbers", function()
        local plugin, state = newPlugin()
        state.external_page = 1
        plugin.line_index = #plugin.lines
        plugin:onTyposcopeNextLine()
        assert.are.equal(1, plugin.line_index)
        assert.are.equal(3, state.page)
    end)

    it("tolerates closing the document during an end-of-book action", function()
        local plugin, state = newPlugin()
        state.close_on_turn = true
        plugin.line_index = #plugin.lines
        assert.is_true(plugin:onTyposcopeNextLine())
        assert.is_false(plugin.is_enabled)
        assert.is_nil(plugin.page_turn_direction)
        assert.are.same({}, state.dirty)
    end)
end)

describe("two-page EPUB spreads", function()
    local boxes = {
        {x=20,y=100,w=240,h=20}, {x=320,y=100,w=240,h=20},
        {x=20,y=130,w=240,h=20}, {x=320,y=130,w=240,h=20},
    }

    it("reads all left-page lines before the right page and can step back across the gutter", function()
        local plugin, state = newPlugin{visible_pages=2,boxes=boxes}
        assert.are.equal(4, #plugin.lines)
        assert.are.same({20,20,320,320}, {plugin.lines[1].x,plugin.lines[2].x,plugin.lines[3].x,plugin.lines[4].x})
        plugin:onTyposcopeNextLine()
        state.dirty = {}
        plugin:onTyposcopeNextLine()
        assert.are.same({x=300,y=97,w=300,h=26}, plugin:getSlot(plugin:getViewport()))
        assert.are.same({}, state.events)
        assert.are.same({
            {widget=plugin.view.dialog,mode="flashui",region={x=300,y=97,w=300,h=26}},
            {widget=plugin.view.dialog,mode="flashui",region={x=0,y=127,w=300,h=26}},
        }, state.dirty)
        plugin:onTyposcopePreviousLine()
        assert.are.same({x=0,y=127,w=300,h=26}, plugin:getSlot(plugin:getViewport()))
    end)

    it("covers the other page at the active line's height", function()
        local plugin = newPlugin{visible_pages=2,boxes=boxes}
        assert.are.same({
            {x=0,y=0,w=600,h=97}, {x=0,y=123,w=600,h=677},
            {x=300,y=97,w=300,h=26},
        }, paint(plugin))
    end)

    it("waits until the last right-page line before turning the spread", function()
        local plugin, state = newPlugin{visible_pages=2,boxes=boxes}
        for _ = 1, 3 do plugin:onTyposcopeNextLine() end
        assert.are.same({}, state.events)
        plugin:onTyposcopeNextLine()
        assert.are.equal(4, state.page)
        assert.are.equal(1, plugin.line_index)
        plugin:onTyposcopePreviousLine()
        assert.are.equal(2, state.page)
        assert.are.equal(4, plugin.line_index)
    end)

    it("keeps the last line when a final spread cannot advance", function()
        local plugin, state = newPlugin{visible_pages=2,boxes=boxes}
        plugin.line_index = #plugin.lines
        plugin.ui.handleEvent = function() plugin:onPageUpdate() end
        plugin:onTyposcopeNextLine()
        assert.are.equal(4, plugin.line_index)
        assert.is_nil(plugin.page_turn_direction)
    end)

    it("keeps masking and stepping through a final spread with no right page", function()
        local plugin, state = newPlugin{visible_pages=2,page=5,page_count=5,boxes={boxes[1],boxes[3]}}
        assert.are.equal(2, #plugin.lines)
        assert.is_true(#paint(plugin) > 0)
        assert.are.equal(300, plugin:getSlot(plugin:getViewport()).w)
        plugin:onTyposcopeNextLine()
        assert.are.equal(2, plugin.line_index)
        assert.are.same({}, state.events)
        plugin:onTyposcopeNextLine()
        assert.are.equal(5, state.page)
        assert.are.equal(2, plugin.line_index)
    end)

    it("keeps both pages of a complete final spread using internal page counts", function()
        local plugin = newPlugin{visible_pages=2,page=3,page_count=4,boxes=boxes}
        assert.are.equal(4, #plugin.lines)
        plugin.line_index = 3
        assert.are.equal(300, plugin:getSlot(plugin:getViewport()).x)
    end)

    it("rebuilds column widths after resizing", function()
        local plugin, state = newPlugin{visible_pages=2,boxes=boxes}
        state.width = 601
        plugin:onScreenResize()
        plugin.line_index = 3
        assert.are.equal(301, plugin:getSlot(plugin:getViewport()).w)
    end)
end)

describe("tap controls", function()
    it("moves lines while enabled and falls through while disabled", function()
        local plugin, state = newPlugin()
        assert.is_true(state.zones.typoscope_tap_forward.handler())
        assert.are.equal(2, plugin.line_index)
        assert.is_true(state.zones.typoscope_tap_backward.handler())
        assert.are.equal(1, plugin.line_index)
        plugin.is_enabled = false
        assert.is_nil(state.zones.typoscope_tap_forward.handler())
        assert.is_nil(state.zones.typoscope_tap_backward.handler())
    end)

    it("respects KOReader's setting to disable page-turn taps", function()
        local plugin, state = newPlugin()
        state.disable_taps = true
        assert.is_nil(state.zones.typoscope_tap_forward.handler())
        assert.are.equal(1, plugin.line_index)
        assert.is_true(plugin:onTyposcopeNextLine()) -- explicitly assigned action still works
    end)

    it("follows reading-order and zone-layout changes through the core setup path", function()
        local plugin, state = newPlugin()
        state.forward_zone = {ratio_x=0,ratio_y=0,ratio_w=.25,ratio_h=1}
        state.backward_zone = {ratio_x=.25,ratio_y=0,ratio_w=.75,ratio_h=1}
        plugin.view:setupTouchZones()
        assert.are.same(state.zones.tap_forward.screen_zone,state.zones.typoscope_tap_forward.screen_zone)
        assert.are.same(state.zones.tap_backward.screen_zone,state.zones.typoscope_tap_backward.screen_zone)
        state.forward_zone = {ratio_x=0,ratio_y=.3,ratio_w=1,ratio_h=.7}
        plugin.view:setupTouchZones()
        assert.are.same(state.zones.tap_forward.screen_zone,state.zones.typoscope_tap_forward.screen_zone)
        assert.are.equal(2, state.core_setups)
        assert.is_true(state.zones.typoscope_tap_forward.handler())
        assert.are.equal(2, plugin.line_index)
    end)

    it("does not stack hooks on repeated initialization and restores core setup at close", function()
        local plugin, state = newPlugin()
        local original = plugin.original_touch_setup
        plugin:onReaderReady()
        plugin.view:setupTouchZones()
        assert.are.equal(1, state.core_setups)
        plugin:onCloseDocument()
        assert.are.equal(original, plugin.ui.rolling.setupTouchZones)
        assert.is_nil(state.zones.typoscope_tap_forward)
        assert.is_nil(state.zones.typoscope_tap_backward)
        assert.is_true(state.settings.enabled)
    end)

    it("does not install touch controls on non-touch devices", function()
        local plugin, state = newPlugin{touch=false}
        assert.are.same({}, state.zones)
        assert.is_nil(plugin.touch_setup_wrapper)
        plugin:onCloseDocument()
    end)
end)
