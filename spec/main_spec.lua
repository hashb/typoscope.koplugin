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
            for _, dirty in ipairs(state.dirty) do assert.are.equal("partial", dirty.mode) end
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
