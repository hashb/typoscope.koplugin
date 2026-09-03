-- Pure geometry helpers. Kept independent from KOReader so they can be unit tested.
local Geometry = {}

local function clamp(value, low, high)
    return math.max(low, math.min(value, high))
end

function Geometry.slotForLine(viewport, line, padding, mask_mode)
    padding = math.max(0, padding or 0)
    local top = clamp(line.y - padding, viewport.y, viewport.y + viewport.h)
    local bottom = clamp(line.y + line.h + padding, viewport.y, viewport.y + viewport.h)
    -- Extend the visible slot to the unmasked edge of the active page. Painting
    -- and refresh calculations then share the same geometry in every mode.
    if mask_mode == "bottom" then top = viewport.y end
    if mask_mode == "top" then bottom = viewport.y + viewport.h end
    return { x = viewport.x, y = top, w = viewport.w, h = math.max(0, bottom - top) }
end

local function clipped(viewport, rect)
    local x, w = rect.x or viewport.x, rect.w or viewport.w
    local left = clamp(x, viewport.x, viewport.x + viewport.w)
    local right = clamp(x + w, viewport.x, viewport.x + viewport.w)
    local top = clamp(rect.y, viewport.y, viewport.y + viewport.h)
    local bottom = clamp(rect.y + rect.h, viewport.y, viewport.y + viewport.h)
    return { x = left, y = top, w = math.max(0, right - left), h = math.max(0, bottom - top) }
end

-- Append the parts of a rectangle outside another rectangle, without overlap.
local function subtract(rect, other, regions)
    local function add(x, y, w, h)
        if w > 0 and h > 0 then regions[#regions + 1] = { x = x, y = y, w = w, h = h } end
    end
    local left = math.max(rect.x, other.x)
    local right = math.min(rect.x + rect.w, other.x + other.w)
    local top = math.max(rect.y, other.y)
    local bottom = math.min(rect.y + rect.h, other.y + other.h)
    if right <= left or bottom <= top then
        add(rect.x, rect.y, rect.w, rect.h)
        return
    end
    add(rect.x, rect.y, rect.w, top - rect.y)
    add(rect.x, bottom, rect.w, rect.y + rect.h - bottom)
    add(rect.x, top, left - rect.x, bottom - top)
    add(right, top, rect.x + rect.w - right, bottom - top)
end

function Geometry.masks(viewport, slot)
    local masks = {}
    subtract(viewport, clipped(viewport, slot), masks)
    return masks
end

-- Refresh only pixels whose mask state changes, including a move between the
-- two pages of a spread. Regions never span unchanged text or black gaps.
function Geometry.slotChanges(viewport, old_slot, new_slot)
    local old = clipped(viewport, old_slot)
    local new = clipped(viewport, new_slot)
    local regions = {}
    subtract(old, new, regions)
    subtract(new, old, regions)
    for _, region in ipairs(regions) do
        local right, bottom = math.ceil(region.x + region.w), math.ceil(region.y + region.h)
        region.x, region.y = math.floor(region.x), math.floor(region.y)
        region.w, region.h = right - region.x, bottom - region.y
    end
    table.sort(regions, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)
    -- Coalesce vertically adjacent strips of the same width.
    local result = {}
    for _, region in ipairs(regions) do
        local previous = result[#result]
        if previous and previous.x == region.x and previous.w == region.w
                and region.y <= previous.y + previous.h then
            previous.h = math.max(previous.h, region.y + region.h - previous.y)
        else
            result[#result + 1] = region
        end
    end
    return result
end

function Geometry.normaliseLines(lines, viewport)
    local visible = {}
    for _, line in ipairs(lines or {}) do
        -- Assign segments by their horizontal center, so a glyph extending into
        -- the gutter cannot duplicate the same line on both pages of a spread.
        local center = line.x + line.w / 2
        if line.h and line.h > 0 and line.w > 0
                and center >= viewport.x and center < viewport.x + viewport.w
                and line.y + line.h > viewport.y and line.y < viewport.y + viewport.h then
            visible[#visible + 1] = { x = line.x, y = line.y, w = line.w, h = line.h }
        end
    end
    table.sort(visible, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)

    -- Segmented selections (notably bidi text) may return several boxes for
    -- one visual line. Merge boxes whose vertical spans substantially overlap
    -- or align at the top (e.g. drop caps), but avoid cascading into subsequent lines.
    local result = {}
    for _, line in ipairs(visible) do
        local previous = result[#result]
        local overlap = previous and math.min(previous.y + previous.h, line.y + line.h)
            - math.max(previous.y, line.y) or 0
        local same_line = false
        if previous and overlap > 0 then
            if math.abs(previous.y - line.y) <= 4 then
                same_line = true
            elseif overlap >= math.max(previous.h, line.h) * 0.5 then
                same_line = true
            end
        end
        if previous and same_line then
            local right = math.max(previous.x + previous.w, line.x + line.w)
            local bottom = math.max(previous.y + previous.h, line.y + line.h)
            previous.x = math.min(previous.x, line.x)
            previous.y = math.min(previous.y, line.y)
            previous.w = right - previous.x
            previous.h = bottom - previous.y
        else
            result[#result + 1] = line
        end
    end
    return result
end

return Geometry
