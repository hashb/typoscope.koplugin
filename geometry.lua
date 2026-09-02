-- Pure geometry helpers. Kept independent from KOReader so they can be unit tested.
local Geometry = {}

local function clamp(value, low, high)
    return math.max(low, math.min(value, high))
end

function Geometry.slotForLine(viewport, line, padding)
    padding = math.max(0, padding or 0)
    local top = clamp(line.y - padding, viewport.y, viewport.y + viewport.h)
    local bottom = clamp(line.y + line.h + padding, viewport.y, viewport.y + viewport.h)
    return { x = viewport.x, y = top, w = viewport.w, h = math.max(0, bottom - top) }
end

function Geometry.manualSlot(viewport, center_ratio, height)
    height = clamp(height, 1, viewport.h)
    local center = viewport.y + viewport.h * clamp(center_ratio, 0, 1)
    local top = clamp(math.floor(center - height / 2), viewport.y, viewport.y + viewport.h - height)
    return { x = viewport.x, y = top, w = viewport.w, h = height }
end

function Geometry.masks(viewport, slot)
    local top_height = math.max(0, slot.y - viewport.y)
    local bottom_y = math.min(viewport.y + viewport.h, slot.y + slot.h)
    return {
        { x = viewport.x, y = viewport.y, w = viewport.w, h = top_height },
        { x = viewport.x, y = bottom_y, w = viewport.w,
          h = math.max(0, viewport.y + viewport.h - bottom_y) },
    }
end

-- Only the parts belonging to one slot but not the other change on screen.
-- Keep separated strips separate so unchanged text and black gaps are untouched.
function Geometry.slotChanges(viewport, old_slot, new_slot)
    local function bounds(slot)
        return clamp(slot.y, viewport.y, viewport.y + viewport.h),
            clamp(slot.y + slot.h, viewport.y, viewport.y + viewport.h)
    end
    local old_top, old_bottom = bounds(old_slot)
    local new_top, new_bottom = bounds(new_slot)
    local edges = { old_top, old_bottom, new_top, new_bottom }
    table.sort(edges)
    local regions = {}
    for i = 1, #edges - 1 do
        local top, bottom = edges[i], edges[i + 1]
        local in_old = top >= old_top and top < old_bottom
        local in_new = top >= new_top and top < new_bottom
        if bottom > top and in_old ~= in_new then
            -- Round outwards to include every changed pixel.
            top, bottom = math.floor(top), math.ceil(bottom)
            local previous = regions[#regions]
            if previous and top <= previous.y + previous.h then
                previous.h = bottom - previous.y
            else
                regions[#regions + 1] = {
                    x = math.floor(viewport.x), y = top,
                    w = math.ceil(viewport.x + viewport.w) - math.floor(viewport.x),
                    h = bottom - top,
                }
            end
        end
    end
    return regions
end

function Geometry.normaliseLines(lines, viewport)
    local visible = {}
    for _, line in ipairs(lines or {}) do
        if line.h and line.h > 0 and line.y + line.h > viewport.y
                and line.y < viewport.y + viewport.h then
            visible[#visible + 1] = { x = line.x, y = line.y, w = line.w, h = line.h }
        end
    end
    table.sort(visible, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)

    -- Segmented selections (notably bidi text) may return several boxes for
    -- one visual line. Merge boxes whose vertical spans substantially overlap.
    local result = {}
    for _, line in ipairs(visible) do
        local previous = result[#result]
        local overlap = previous and math.min(previous.y + previous.h, line.y + line.h)
            - math.max(previous.y, line.y) or 0
        if previous and overlap >= math.min(previous.h, line.h) / 2 then
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
