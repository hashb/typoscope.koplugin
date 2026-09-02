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
    return { open = function() return {} end }
end
package.preload.device = function()
    return { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end } }
end
package.preload["ui/uimanager"] = function()
    return {}
end
package.preload["ui/widget/widget"] = function()
    return { extend = function(_, definition) return definition end }
end
package.preload.gettext = function()
    return function(text) return text end
end

local Typoscope = dofile("main.lua")

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
end)
