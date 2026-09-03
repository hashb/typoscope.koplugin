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
        ["ffi/blitbuffer"] = { COLOR_BLACK = 0, COLOR_WHITE = 255 },
        datastorage = { getSettingsDir = function() return "/tmp" end },
        dispatcher = { registerAction = function() end },
        luasettings = { open = function() return settings end },
        device = {
            isTouchDevice = function() return state.touch end,
            screen = {
                getWidth = function() return state.width end,
                getHeight = function() return state.height end,
                scaleBySize = function(_, value) return value end,
            },
        },
        ["ui/uimanager"] = {
            show = function(_, widget) state.shown = widget end,
            setDirty = function(_, widget, mode, region)
                state.dirty[#state.dirty + 1] = { widget = widget, mode = mode, region = region }
            end,
        },
        ["ui/geometry"] = { new = function(_, region) return region end },
        ["ui/event"] = { new = function(_, name, direction) return { name = name, direction = direction } end },
        ["ui/widget/widget"] = { extend = function(_, definition) return definition end },
        ["ui/widget/spinwidget"] = { new = function(_, definition) return definition end },
        gettext = function(text) return text end,
    }
    local environment = setmetatable({
        -- Load only this plugin against stubs. Do not replace package.preload or
        -- package.loaded in the surrounding KOReader/Busted process.
        require = function(name) assert(stubs[name], name); return stubs[name] end,
        G_reader_settings = { nilOrFalse = function() return not state.disable_taps end },
    }, { __index = _G })
    local chunk
    if setfenv then
        chunk = assert(loadfile(plugin_dir .. "main.lua"))
        setfenv(chunk, environment)
    else
        chunk = assert(loadfile(plugin_dir .. "main.lua", "t", environment))
    end
    local Typoscope = chunk()
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
