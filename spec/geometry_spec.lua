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
