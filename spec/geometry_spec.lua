local spec_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local Geometry = dofile(spec_dir .. "../geometry.lua")

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

    it("extends the visible slot to the unmasked edge while preserving padding", function()
        local line = { x = 50, y = 120, w = 200, h = 30 }
        assert.are.same({ x = 10, y = 117, w = 600, h = 703 },
            Geometry.slotForLine(viewport, line, 3, "top"))
        assert.are.same({ x = 10, y = 20, w = 600, h = 133 },
            Geometry.slotForLine(viewport, line, 3, "bottom"))
        assert.are.same({ x = 10, y = 117, w = 600, h = 36 },
            Geometry.slotForLine(viewport, line, 3, "both"))
    end)

    it("clips one-sided slots at page edges, including fully visible pages", function()
        for _, mode in ipairs({"top", "bottom"}) do
            assert.are.same(viewport,
                Geometry.slotForLine(viewport, { y = 18, h = 802 }, 3, mode))
            assert.are.same({}, Geometry.masks(viewport,
                Geometry.slotForLine(viewport, { y = 18, h = 802 }, 3, mode)))
        end
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

    it("masks and refreshes exactly the changed pixels for rectangular slots", function()
        local area = { x = 0, y = 0, w = 6, h = 8 }
        local slots = {
            {x=0,y=0,w=6,h=8}, {x=0,y=1,w=3,h=2}, {x=3,y=1,w=3,h=2},
            {x=1,y=2,w=4,h=4}, {x=2,y=3,w=1,h=2}, {x=-2,y=-1,w=5,h=4},
            {x=4,y=6,w=4,h=5}, {x=9,y=10,w=3,h=2}, {x=2,y=2,w=0,h=3},
        }
        local function contains(rect, x, y)
            return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
        end
        local function countAt(rects, x, y)
            local count = 0
            for _, rect in ipairs(rects) do
                assert.is_true(rect.x >= 0 and rect.x + rect.w <= area.w)
                assert.is_true(rect.y >= 0 and rect.y + rect.h <= area.h)
                if contains(rect, x, y) then count = count + 1 end
            end
            return count
        end
        for _, old_slot in ipairs(slots) do
            local masks = Geometry.masks(area, old_slot)
            for _, new_slot in ipairs(slots) do
                local changes = Geometry.slotChanges(area, old_slot, new_slot)
                for y = 0, area.h - 1 do
                    for x = 0, area.w - 1 do
                        local old_visible, new_visible = contains(old_slot, x, y), contains(new_slot, x, y)
                        assert.are.equal(old_visible and 0 or 1, countAt(masks, x, y))
                        assert.are.equal(old_visible ~= new_visible and 1 or 0, countAt(changes, x, y))
                    end
                end
            end
        end
    end)

    it("does not merge or duplicate lines across page areas", function()
        local boxes = {
            {x=20,y=100,w=240,h=20}, {x=320,y=100,w=240,h=20},
            {x=20,y=130,w=240,h=20}, {x=320,y=130,w=240,h=20},
        }
        local left = Geometry.normaliseLines(boxes, {x=0,y=0,w=300,h=800})
        local right = Geometry.normaliseLines(boxes, {x=300,y=0,w=300,h=800})
        assert.are.same({boxes[1], boxes[3]}, left)
        assert.are.same({boxes[2], boxes[4]}, right)
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

    it("merges drop caps with line 1 without swallowing subsequent lines", function()
        local lines = Geometry.normaliseLines({
            { x = 20, y = 100, w = 40, h = 60 },
            { x = 70, y = 100, w = 300, h = 20 },
            { x = 70, y = 120, w = 300, h = 20 },
            { x = 70, y = 140, w = 300, h = 20 },
            { x = 20, y = 160, w = 350, h = 20 },
        }, viewport)
        assert.are.equal(4, #lines)
        assert.are.same({ x = 20, y = 100, w = 350, h = 60 }, lines[1])
        assert.are.equal(120, lines[2].y)
        assert.are.equal(140, lines[3].y)
        assert.are.equal(160, lines[4].y)
    end)
end)
