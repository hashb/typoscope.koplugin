local Helpers = {}
local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "../"

function Helpers.newPlugin(options)
    options = options or {}
    local state = {
        page = options.page or 2, position = options.position or 800,
        page_count = options.page_count or 10, max_position = 7200,
        visible_pages = options.visible_pages or 1,
        width = 600, height = 800, image_count = 0,
        boxes = options.boxes or {
            { x = 20, y = 100, w = 400, h = 20 },
            { x = 20, y = 125, w = 400, h = 20 },
        },
        settings = { enabled = options.enabled ~= false },
        dirty = {}, events = {}, zones = {}, menu = {}, modules = {},
        touch = options.touch ~= false,
    }
    local settings = {
        isTrue = function(_, key) return state.settings[key] == true end,
        nilOrTrue = function(_, key) return state.settings[key] ~= false end,
        readSetting = function(_, key) return state.settings[key] end,
        saveSetting = function(_, key, value) state.settings[key] = value end,
        flush = function() state.flushed = true end,
    }
    local stubs = {
        ["ffi/blitbuffer"] = {
            COLOR_BLACK = 0, COLOR_WHITE = 255,
            Color8A = function(value, alpha) return { value = value, alpha = alpha } end,
        },
        datastorage = { getSettingsDir = function() return "/tmp" end },
        dispatcher = { registerAction = function() end },
        luasettings = { open = function() return settings end },
        device = {
            isTouchDevice = function() return state.touch end,
            hasKeys = function() return state.keys end,
            input = { group = { Back = "Back" } },
            screen = {
                getWidth = function() return state.width end,
                getHeight = function() return state.height end,
                scaleBySize = function(_, value) return value end,
            },
        },
        ["ui/uimanager"] = {
            show = function(_, widget, _, _, x, y) state.shown, state.shown_at = widget, { x = x, y = y } end,
            close = function(_, widget) state.closed = widget; widget:onCloseWidget() end,
            setDirty = function(_, widget, mode, region)
                state.dirty[#state.dirty + 1] = { widget = widget, mode = mode, region = region }
            end,
        },
        ["ui/geometry"] = { new = function(_, region) return region end },
        ["ui/event"] = { new = function(_, name, direction) return { name = name, direction = direction } end },
        ["ui/widget/widget"] = { extend = function(_, definition) return definition end },
        -- Slider panel widgets: record definitions and the calls the panel makes.
        ["ui/widget/buttonprogresswidget"] = { new = function(_, definition)
            function definition:setPosition(position, default) self.position, self.default_position = position, default end
            function definition.getSize() return { w = 400, h = 40 } end
            return definition
        end },
        ["ui/widget/button"] = { new = function(_, definition) return definition end },
        ["ui/widget/horizontalgroup"] = { new = function(_, definition)
            function definition:clear() for i = #self, 1, -1 do self[i] = nil end end
            function definition.getSize() return { w = 400, h = 40 } end
            return definition
        end },
        ["ui/widget/container/leftcontainer"] = { new = function(_, definition) return definition end },
        ["ui/widget/focusmanager"] = { extend = function(_, class)
            class.__index = class
            function class:new(object)
                object = setmetatable(object or {}, self)
                object.key_events, object.ges_events = {}, {}
                function object:mergeLayoutInVertical(child) self.layout[#self.layout + 1] = { child } end
            function object.refocusWidget() end
                object:init()
                return object
            end
            return class
        end },
        ["ui/widget/container/framecontainer"] = { new = function(_, definition)
            function definition.getSize() return { w = 570, h = 300 } end
            return definition
        end },
        ["ui/widget/textwidget"] = { new = function(_, definition)
            function definition:setText(text) self.text = text end
            return definition
        end },
        ["ui/widget/verticalgroup"] = { new = function(_, definition) return definition end },
        ["ui/widget/verticalspan"] = { new = function(_, definition) return definition end },
        ["ui/gesturerange"] = { new = function(_, definition) return definition end },
        ["ui/font"] = { getFace = function() return "face" end },
        ["ui/size"] = {
            padding = { default = 5, small = 2 }, margin = { default = 5, tiny = 1 }, radius = { window = 7 },
            border = { window = 2 }, span = { vertical_large = 5, vertical_default = 2 },
        },
        gettext = function(text) return text end,
    }
    local environment
    local function loadWithStubs(path)
        local chunk
        if setfenv then
            chunk = assert(loadfile(path))
            setfenv(chunk, environment)
        else
            chunk = assert(loadfile(path, "t", environment))
        end
        return chunk
    end
    environment = setmetatable({
        -- Load only this plugin against stubs. Do not replace package.preload or
        -- package.loaded in the surrounding KOReader/Busted process.
        require = function(name) assert(stubs[name], name); return stubs[name] end,
        G_reader_settings = { nilOrFalse = function() return not state.disable_taps end },
        -- The plugin loads its helper files with dofile; give them the same stubs.
        dofile = function(path) return loadWithStubs(path)() end,
    }, { __index = _G })
    local Typoscope = loadWithStubs(plugin_dir .. "main.lua")()
    local plugin
    local ui = {
        document = {
            file = options.file or "book.epub",
            getCurrentPage = function(_, internal)
                return internal and state.page or (state.external_page or state.page)
            end,
            getCurrentPos = function() return state.position end,
            getVisiblePageCount = function() return state.visible_pages end,
            getPageCount = function(_, internal)
                return internal and state.page_count or math.ceil(state.page_count / state.visible_pages)
            end,
            getDrawnImagesStatistics = function() return state.image_count end,
            getTextFromPositions = function(_, from, to, no_highlight)
                state.extraction = { from, to, no_highlight }
                if state.extraction_error then error("text extraction failed") end
                -- CRe keeps a two-page layout at EOF, but an endpoint on the
                -- missing right-hand page invalidates the whole selection.
                if state.visible_pages == 2 and state.page == state.page_count
                        and (from.x > state.width / 2 or to.x > state.width / 2) then
                    return nil
                end
                return { pos0 = "start", pos1 = "end", sboxes = state.boxes }
            end,
        },
        menu = { registerToMainMenu = function(_, item) item:addToMainMenu(state.menu) end },
        registerTouchZones = function(_, zones)
            for _, zone in ipairs(zones) do state.zones[zone.id] = zone end
        end,
        unRegisterTouchZones = function(_, zones)
            for _, zone in ipairs(zones) do state.zones[zone.id] = nil end
        end,
    }
    local view = {
        view_mode = options.mode or "page", dialog = {},
        footer = { getHeight = function() return 40 end },
        registerViewModule = function(_, name, module) state.modules[name] = module end,
        getTapZones = function()
            return state.forward_zone or { ratio_x = .25, ratio_y = 0, ratio_w = .75, ratio_h = 1 },
                state.backward_zone or { ratio_x = 0, ratio_y = 0, ratio_w = .25, ratio_h = 1 }
        end,
    }
    local rolling = {}
    function rolling:setupTouchZones()
        state.core_setups = (state.core_setups or 0) + 1
        local forward, backward = view:getTapZones()
        ui:registerTouchZones({
            { id = "tap_forward", screen_zone = forward },
            { id = "tap_backward", screen_zone = backward },
        })
    end
    -- KOReader's tap-zone menu and reading-order action both use this path.
    function view:setupTouchZones() ui.rolling:setupTouchZones() end
    if not options.paging then ui.rolling = rolling end
    if options.missing_document_method then ui.document[options.missing_document_method] = nil end
    plugin = setmetatable({ ui = ui, view = view }, { __index = Typoscope })
    function ui:handleEvent(event)
        state.events[#state.events + 1] = event
        if event.name ~= "GotoViewRel" then return end
        if state.close_on_turn then plugin:onCloseDocument(); ui.document = nil; return end
        if view.view_mode == "scroll" then
            state.position = math.max(0, math.min(state.max_position, state.position + event.direction * state.height))
            plugin:onPosUpdate()
        else
            state.page = math.max(1, math.min(state.page_count, state.page + event.direction * state.visible_pages))
            plugin:onPageUpdate()
        end
    end
    plugin:init()
    plugin:onReaderReady()
    return plugin, state
end

return Helpers
