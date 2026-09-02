package.path = "./?.lua;" .. package.path

local Geometry = require("geometry")

describe("typoscope geometry", function()
    local viewport = { x = 10, y = 20, w = 600, h = 800 }

    it("makes opaque masks above and below the reading slot", function()
        local masks = Geometry.masks(viewport, { x = 10, y = 120, w = 600, h = 30 })
        assert.are.same({ x = 10, y = 20, w = 600, h = 100 }, masks[1])
        assert.are.same({ x = 10, y = 150, w = 600, h = 670 }, masks[2])
    end)

    it("adds padding to a detected line and clips it", function()
        assert.are.same({ x = 10, y = 20, w = 600, h = 15 },
            Geometry.slotForLine(viewport, { x = 50, y = 18, w = 200, h = 14 }, 3))
    end)

    it("clamps a manual slot to the viewport", function()
        assert.are.same({ x = 10, y = 20, w = 600, h = 50 },
            Geometry.manualSlot(viewport, 0, 50))
        assert.are.same({ x = 10, y = 770, w = 600, h = 50 },
            Geometry.manualSlot(viewport, 1, 50))
    end)

    it("leaves the gap between separated slots out of refresh regions", function()
        assert.are.same({
            { x = 10, y = 100, w = 600, h = 20 },
            { x = 10, y = 200, w = 600, h = 30 },
        }, Geometry.slotChanges(viewport, { y = 100, h = 20 }, { y = 200, h = 30 }))
    end)

    it("refreshes exactly the changed pixels for clipped, nested and overlapping slots", function()
        local area = { x = 10, y = 20, w = 5, h = 10 }
        local slots = {
            { y = 15, h = 8 }, { y = 20, h = 0 }, { y = 20, h = 5 },
            { y = 22, h = 3 }, { y = 23, h = 5 }, { y = 25, h = 5 },
            { y = 27, h = 8 }, { y = 35, h = 5 }, { y = 15, h = 20 },
        }
        for _, old_slot in ipairs(slots) do
            for _, new_slot in ipairs(slots) do
                local regions = Geometry.slotChanges(area, old_slot, new_slot)
                for _, region in ipairs(regions) do
                    assert.are.equal(area.x, region.x)
                    assert.are.equal(area.w, region.w)
                    assert.is_true(region.h > 0)
                    assert.is_true(region.y >= area.y and region.y + region.h <= area.y + area.h)
                end
                for y = area.y, area.y + area.h - 1 do
                    local in_old = y >= old_slot.y and y < old_slot.y + old_slot.h
                    local in_new = y >= new_slot.y and y < new_slot.y + new_slot.h
                    local count = 0
                    for _, region in ipairs(regions) do
                        if y >= region.y and y < region.y + region.h then count = count + 1 end
                    end
                    assert.are.equal(in_old ~= in_new and 1 or 0, count)
                end
            end
        end
    end)

    it("rounds fractional refresh edges outwards to whole pixels", function()
        assert.are.same({
            { x = 10, y = 100, w = 600, h = 6 },
            { x = 10, y = 120, w = 600, h = 6 },
        }, Geometry.slotChanges(viewport, { y = 100.5, h = 20 }, { y = 105.5, h = 20 }))
    end)

    it("sorts and removes offscreen or empty lines", function()
        local lines = Geometry.normaliseLines({
            { x = 5, y = 200, w = 10, h = 10 },
            { x = 5, y = -30, w = 10, h = 10 },
            { x = 5, y = 100, w = 10, h = 0 },
            { x = 5, y = 100, w = 10, h = 10 },
        }, viewport)
        assert.are.equal(2, #lines)
        assert.are.equal(100, lines[1].y)
        assert.are.equal(200, lines[2].y)
    end)

    it("merges selection segments on the same visual line", function()
        local lines = Geometry.normaliseLines({
            { x = 200, y = 100, w = 80, h = 20 },
            { x = 20, y = 102, w = 150, h = 18 },
            { x = 20, y = 140, w = 260, h = 20 },
        }, viewport)
        assert.are.equal(2, #lines)
        assert.are.same({ x = 20, y = 100, w = 260, h = 20 }, lines[1])
    end)
end)
