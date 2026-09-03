package.path = "./?.lua;" .. package.path

package.preload["ffi/blitbuffer"] = function()
    return { COLOR_BLACK = 0 }
end
package.preload.datastorage = function()
    return { getSettingsDir = function() return "/tmp" end }
end
package.preload.dispatcher = function()
    return { registerAction = function() end }
end
package.preload.luasettings = function()
    return { open = function()
        return {
            isTrue = function() return false end,
            nilOrTrue = function() return true end,
            readSetting = function() end,
            saveSetting = function() end,
        }
    end }
end
package.preload.device = function()
    return {
        isTouchDevice = function() return true end,
        screen = {
            getWidth = function() return 600 end,
            getHeight = function() return 800 end,
            scaleBySize = function(_, sz) return sz end,
        },
    }
end
package.preload["ui/uimanager"] = function()
    return { show = function() end }
end
package.preload["ui/geometry"] = function()
    return { new = function(_, region) return region end }
end
package.preload["ui/event"] = function()
    return { new = function(_, name, direction) return { name = name, direction = direction } end }
end
package.preload["ui/widget/widget"] = function()
    return { extend = function(_, definition) return definition end }
end
package.preload["ui/widget/spinwidget"] = function()
    return { new = function(_, definition) return definition end }
end
package.preload.gettext = function()
    return function(text) return text end
end

local Typoscope = dofile("main.lua")

describe("typoscope startup", function()
    it("initializes and registers its Tools menu entry when a book is ready", function()
        local menu_items, view_modules = {}, {}
        local touch_zones
        local plugin = setmetatable({
            ui = {
                menu = {
                    registerToMainMenu = function(_, item) item:addToMainMenu(menu_items) end,
                },
                registerTouchZones = function(_, zones) touch_zones = zones end,
            },
            view = {
                registerViewModule = function(_, name, module) view_modules[name] = module end,
                getTapZones = function() return {}, {} end,
            },
        }, { __index = Typoscope })

        plugin:init()
        plugin:onReaderReady()

        assert.are.equal("typoscope", plugin.name)
        assert.is_true(plugin.is_doc_only)
        assert.are.equal(plugin, view_modules.typoscope)
        assert.are.equal("Typoscope reading mask", menu_items.typoscope.text)
        assert.are.equal("more_tools", menu_items.typoscope.sorting_hint)
        assert.are.same({}, plugin.lines)
        assert.are.equal(2, #touch_zones)
        local toggle = menu_items.typoscope.sub_item_table[1]
        assert.is_false(toggle.checked_func())
        toggle.callback()
        assert.is_true(toggle.checked_func())
        toggle.callback()
        assert.is_false(toggle.checked_func())
    end)
end)

describe("typoscope screen refreshes", function()
    local UIManager = require("ui/uimanager")
    local dirty, original_set_dirty

    before_each(function()
        dirty = {}
        original_set_dirty = UIManager.setDirty
        UIManager.setDirty = function(_, widget, mode, region)
            dirty[#dirty + 1] = { widget = widget, mode = mode, region = region }
        end
    end)

    after_each(function()
        UIManager.setDirty = original_set_dirty
    end)

    local function makePlugin()
        return setmetatable({
            is_enabled = true,
            flash_on_line_change = true,
            lines = {
                { x = 20, y = 100, w = 400, h = 20 },
                { x = 20, y = 125, w = 400, h = 20 },
            },
            view = { dialog = {}, visible_area = { x = 10, y = 20, w = 560, h = 760 } },
            ui = { document = {} },
            settings = { saveSetting = function() end },
        }, { __index = Typoscope })
    end

    it("requests a cleaning flash only for changed strips when moving in either direction", function()
        local plugin = makePlugin()
        for _, method in ipairs({ "onTyposcopeNextLine", "onTyposcopePreviousLine" }) do
            dirty = {}
            assert.is_true(plugin[method](plugin))
            assert.are.same({
                { widget = plugin.view.dialog, mode = "flashui",
                    region = { x = 10, y = 97, w = 560, h = 25 } },
                { widget = plugin.view.dialog, mode = "flashui",
                    region = { x = 10, y = 123, w = 560, h = 25 } },
            }, dirty)
        end
    end)

    it("uses partial refresh instead of flashui when flash_on_line_change is disabled", function()
        local plugin = makePlugin()
        plugin.flash_on_line_change = false
        dirty = {}
        assert.is_true(plugin:onTyposcopeNextLine())
        assert.are.same({
            { widget = plugin.view.dialog, mode = "partial",
                region = { x = 10, y = 97, w = 560, h = 25 } },
            { widget = plugin.view.dialog, mode = "partial",
                region = { x = 10, y = 123, w = 560, h = 25 } },
        }, dirty)
    end)

    it("limits cleaning flashes for manual slot movements to the changed band", function()
        for _, method in ipairs({ "onTyposcopeNextLine", "onTyposcopePreviousLine" }) do
            dirty = {}
            local plugin = makePlugin()
            plugin.lines = {}
            plugin.view.visible_area = nil
            plugin.manual_height = 40
            plugin.manual_center = method == "onTyposcopeNextLine" and 0.5 or 0.55
            plugin[method](plugin)
            assert.are.same({
                { widget = plugin.view.dialog, mode = "flashui",
                    region = { x = 0, y = 380, w = 600, h = 80 } },
            }, dirty)
        end
    end)

    it("does not refresh when the slot is unchanged", function()
        local plugin = makePlugin()
        plugin.lines[2] = plugin.lines[1]
        plugin:onTyposcopeNextLine()
        assert.are.same({}, dirty)
    end)

    it("does not refresh pages intentionally left unmasked", function()
        local plugin = makePlugin()
        plugin.leave_image_pages_unmasked = true
        plugin.ui.document.getDrawnImagesStatistics = function() return 1 end
        plugin:onTyposcopeNextLine()
        assert.are.equal(2, plugin.line_index)
        assert.are.same({}, dirty)
    end)

    it("does not refresh when the mask is disabled", function()
        local plugin = makePlugin()
        plugin.is_enabled = false
        assert.is_false(plugin:onTyposcopeNextLine())
        assert.is_false(plugin:onTyposcopePreviousLine())
        assert.are.same({}, dirty)
    end)

    it("keeps normal refreshes for page turns in either direction", function()
        for _, manual in ipairs({ false, true }) do
            for _, direction in ipairs({ -1, 1 }) do
                dirty = {}
                local plugin = makePlugin()
                plugin.line_index = direction == 1 and #plugin.lines or 1
                if manual then
                    plugin.lines = {}
                    plugin.manual_height = 40
                    plugin.manual_center = direction == 1 and 0.98 or 0.02
                end
                local events = {}
                plugin.ui.handleEvent = function(_, event) events[#events + 1] = event end
                if direction == 1 then
                    plugin:onTyposcopeNextLine()
                else
                    plugin:onTyposcopePreviousLine()
                end
                assert.are.same({ { name = "GotoViewRel", direction = direction } }, events)
                assert.are.same({ { widget = plugin.view.dialog, mode = "partial" } }, dirty)
            end
        end
    end)

    it("does not leak show_last_line_after_page_turn when previous line is called on page 1", function()
        local plugin = makePlugin()
        plugin.line_index = 1
        plugin.ui.document.getCurrentPage = function() return 1 end
        plugin.ui.document.getPageCount = function() return 10 end
        local events = {}
        plugin.ui.handleEvent = function(_, event) events[#events + 1] = event end
        assert.is_true(plugin:onTyposcopePreviousLine())
        assert.are.same({}, events)
        assert.is_nil(plugin.show_last_line_after_page_turn)
    end)

    it("does not wrap to line 1 when next line is called on the last page", function()
        local plugin = makePlugin()
        plugin.line_index = #plugin.lines
        plugin.ui.document.getCurrentPage = function() return 10 end
        plugin.ui.document.getPageCount = function() return 10 end
        local events = {}
        plugin.ui.handleEvent = function(_, event) events[#events + 1] = event end
        assert.is_true(plugin:onTyposcopeNextLine())
        assert.are.same({}, events)
        assert.are.equal(#plugin.lines, plugin.line_index)
    end)

    it("resets manual slot to top on normal page turns and bottom on backward page turns", function()
        local plugin = makePlugin()
        plugin.lines = {}
        plugin.manual_height = 40
        plugin.manual_center = 0.5
        plugin.view.visible_area = { x = 0, y = 0, w = 600, h = 800 }

        -- Forward / external page update
        plugin:onPageUpdate()
        assert.are.equal(0.025, plugin.manual_center)

        -- Backward page update
        plugin.show_last_line_after_page_turn = true
        plugin:onPageUpdate()
        assert.are.equal(0.975, plugin.manual_center)
        assert.is_nil(plugin.show_last_line_after_page_turn)
    end)
end)

describe("typoscope tap zones", function()
    local function makePlugin(enabled)
        local registered
        local plugin = setmetatable({
            is_enabled = enabled,
            view = {
                getTapZones = function()
                    return { ratio_x = 0.25, ratio_y = 0, ratio_w = 0.75, ratio_h = 1 },
                        { ratio_x = 0, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 }
                end,
            },
            ui = {
                registerTouchZones = function(_, zones) registered = zones end,
            },
        }, { __index = Typoscope })
        plugin:setupTouchZones()
        return plugin, registered
    end

    it("moves the slit instead of turning the page while enabled", function()
        local plugin, zones = makePlugin(true)
        local next_calls, previous_calls = 0, 0
        plugin.onTyposcopeNextLine = function() next_calls = next_calls + 1 return true end
        plugin.onTyposcopePreviousLine = function() previous_calls = previous_calls + 1 return true end

        assert.is_true(zones[1].handler())
        assert.is_true(zones[2].handler())
        assert.are.equal(1, next_calls)
        assert.are.equal(1, previous_calls)
        assert.are.same({ "tap_forward" }, zones[1].overrides)
        assert.are.same({ "tap_backward" }, zones[2].overrides)
    end)

    it("falls through to normal page turns while disabled", function()
        local _, zones = makePlugin(false)
        assert.is_nil(zones[1].handler())
        assert.is_nil(zones[2].handler())
    end)

    it("does not register tap zones on devices without touch", function()
        local Device = require("device")
        local original = Device.isTouchDevice
        Device.isTouchDevice = function() return false end
        local ok, plugin, zones = pcall(makePlugin, true)
        Device.isTouchDevice = original
        assert.is_true(ok)
        assert.is_nil(zones)
    end)

    it("re-registers touch zones on resetLayout and onScreenResize", function()
        local plugin, zones = makePlugin(true)
        local registered_count = 0
        plugin.ui.registerTouchZones = function(_, z)
            registered_count = registered_count + 1
        end
        plugin.refreshLines = function() end
        plugin.redraw = function() end

        plugin:resetLayout()
        assert.are.equal(1, registered_count)

        plugin:onScreenResize()
        assert.are.equal(2, registered_count)
    end)
end)
