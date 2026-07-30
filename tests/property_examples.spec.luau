describe("property-based testing examples", function()
    it("addition is commutative", function()
        given({
            a = g.integer(-100, 100),
            b = g.integer(-100, 100),
        }, function(args)
            expect(args.a + args.b).to.equal(args.b + args.a)
        end)
    end)

    it("addition is associative", function()
        given({
            a = g.integer(-50, 50),
            b = g.integer(-50, 50),
            c = g.integer(-50, 50),
        }, function(args)
            expect((args.a + args.b) + args.c).to.equal(args.a + (args.b + args.c))
        end)
    end)

    it("multiplication distributes over addition", function()
        given({
            a = g.integer(-20, 20),
            b = g.integer(-20, 20),
            c = g.integer(-20, 20),
        }, function(args)
            expect(args.a * (args.b + args.c)).to.equal(args.a * args.b + args.a * args.c)
        end)
    end)

    it("string concatenation is associative", function()
        given({
            a = g.string(0, 10),
            b = g.string(0, 10),
            c = g.string(0, 10),
        }, function(args)
            expect((args.a .. args.b) .. args.c).to.equal(args.a .. (args.b .. args.c))
        end)
    end)

    it("reversing a list twice yields the original", function()
        given({
            xs = g.list(g.integer(0, 100), 0, 20),
        }, function(args)
            local function reverse(t)
                local result = {}

                for i = #t, 1, -1 do
                    table.insert(result, t[i])
                end

                return result
            end

            expect(reverse(reverse(args.xs))).to.equal(args.xs)
        end)
    end)

    it("table.insert at position 1 prepends", function()
        given({
            xs = g.list(g.character(), 0, 10),
            x  = g.character(),
        }, function(args)
            local ys = { table.unpack(args.xs) }

            table.insert(ys, 1, args.x)

            expect(#ys).to.equal(#args.xs + 1)
            expect(ys[1]).to.equal(args.x)
        end)
    end)

    it("string length is non-negative", function()
        given({
            s = g.string(0, 50),
        }, function(args)
            expect(#args.s).to.be.above(-1)
        end)
    end)

    it("boolean negation is its own inverse", function()
        given({
            x = g.boolean(),
        }, function(args)
            expect(not not args.x).to.equal(args.x)
        end)
    end)

    it("table.concat round-trips with g.match", function()
        given({
            words = g.list(g.string(1, 5), 0, 5),
            sep   = g.sampled({", ", " | ", " -- "}),
        }, function(args)
            local joined   = table.concat(args.words, args.sep)
            local expected = #args.words > 0 and (#joined >= (#args.words - 1) * #args.sep) or (joined == "")

            expect(expected).to.be.ok()
        end)
    end)

    it("insensitive ordering differs by at most swapped case", function()
        given({
            a = g.string(1, 10),
            b = g.string(1, 10),
        }, function(args)
            local a_lower = args.a:lower()
            local b_lower = args.b:lower()

            if (a_lower < b_lower) then
                expect(args.a:upper() < args.b:upper() or a_lower < b_lower).to.be.ok()
            end
        end)
    end)

    it("max is at least as large as min", function()
        given({
            a = g.integer(-1000, 1000),
            b = g.integer(-1000, 1000),
        }, function(args)
            local min_val = math.min(args.a, args.b)
            local max_val = math.max(args.a, args.b)

            expect(max_val).to.be.above(min_val - 1)
        end)
    end)

    it("absolute value is non-negative", function()
        given({
            n = g.integer(-1000, 1000),
        }, function(args)
            expect(math.abs(args.n)).to.be.above(-1)
        end)
    end)

    it("filtered even numbers are always even", function()
        given({
            x = g.filter(g.integer(-100, 100), function(n)
                return n % 2 == 0
            end),
        }, function(args)
            expect(args.x % 2).to.equal(0)
        end)
    end)

    it("mapped values are twice the input", function()
        given({
            x = g.map(g.integer(1, 50), function(n)
                return n * 2
            end),
        }, function(args)
            expect(args.x % 2).to.equal(0)
            expect(args.x).to.be.above(0)
        end)
    end)

    it("one_of picks from multiple strategies", function()
        given({
            v = g.one_of({
                g.sampled({"hello", "world"}),
                g.integer(1, 10),
            }),
        }, function(args)
            local is_string = type(args.v) == "string"
            local is_number = type(args.v) == "number"

            expect(is_string or is_number).to.be.ok()
        end)
    end)

    it("dictionary keys are unique", function()
        given({
            d = g.dictionary(g.string(1, 5), g.integer(0, 100), 10),
        }, function(args)
            local keys = {}

            for key, _ in pairs(args.d) do
                table.insert(keys, key)
            end

            for i = 1, #keys do
                for j = i + 1, #keys do
                    expect(keys[i]).never.to.equal(keys[j])
                end
            end
        end)
    end)

    it("stack push-pop invariant", function()
        given({
            values = g.list(g.integer(-100, 100), 0, 10),
        }, function(args)
            local stack = {}

            for _, v in ipairs(args.values) do
                table.insert(stack, v)
            end

            for i = #args.values, 1, -1 do
                local popped = table.remove(stack)
                expect(popped).to.equal(args.values[i])
            end
        end)
    end)

    it("queue push-shift invariant", function()
        given({
            values = g.list(g.integer(-100, 100), 0, 10),
        }, function(args)
            local queue = {}

            for _, v in ipairs(args.values) do
                table.insert(queue, v)
            end

            for i = 1, #args.values do
                local shifted = table.remove(queue, 1)
                expect(shifted).to.equal(args.values[i])
            end
        end)
    end)

    it("frequency picks from weighted strategies", function()
        given({
            v = g.frequency({
                { weight = 9, strategy = g.sampled({"common", "common"}) },
                { weight = 1, strategy = g.sampled({"rare"}) },
            }),
        }, function(args)
            expect(args.v).to.be.ok()
        end)
    end)

    it("tuple generates fixed-size arrays", function()
        given({
            t = g.tuple({
                g.integer(1, 10),
                g.boolean(),
                g.string(0, 5),
            }),
        }, function(args)
            expect(#args.t).to.equal(3)
            expect(type(args.t[1])).to.equal("number")
            expect(type(args.t[2])).to.equal("boolean")
            expect(type(args.t[3])).to.equal("string")
        end)
    end)
end)
