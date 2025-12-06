#!/bin/bash
# setup-test-runner.sh

echo "Setting up TestEz GUI Runner..."

# Create project structure
mkdir -p tests

# Create main runner file
cat > test-runner.lua << 'EOF'
-- Simple console-based GUI with ASCII
local TestEZ = require("TestEZ")

local function clearScreen()
    print("\033[2J\033[H")  -- Clear screen and move to home
end

local function drawProgressBar(percentage, width)
    local filled = math.floor(percentage * width / 100)
    local bar = "["
    for i = 1, width do
        if i <= filled then
            bar = bar .. "="
        else
            bar = bar .. " "
        end
    end
    bar = bar .. "] " .. math.floor(percentage) .. "%"
    return bar
end

local function runTests()
    clearScreen()
    print("╔══════════════════════════════════════╗")
    print("║         TestEz Runner v1.0          ║")
    print("╚══════════════════════════════════════╝")
    print()
    
    -- Load and run tests
    local testFiles = {}
    for file in io.popen('find tests -name "*.spec.lua" -o -name "*.test.lua"'):lines() do
        table.insert(testFiles, file)
    end
    
    local results = {
        passed = 0,
        failed = 0,
        skipped = 0,
        total = #testFiles
    }
    
    for i, file in ipairs(testFiles) do
        local progress = (i / #testFiles) * 100
        clearScreen()
        
        print("╔══════════════════════════════════════╗")
        print("║         TestEz Runner v1.0          ║")
        print("╚══════════════════════════════════════╝")
        print()
        print("Progress: " .. drawProgressBar(progress, 30))
        print()
        print("Running: " .. file)
        
        local success, testPlan = pcall(require, file:gsub("^tests/", ""):gsub("%.lua$", ""))
        
        if success then
            local testResults = TestEZ.TestBootstrap.run(testPlan)
            
            if testResults.failureCount == 0 then
                print("\033[32m✓ Passed\033[0m")
                results.passed = results.passed + 1
            else
                print("\033[31m✗ Failed\033[0m")
                results.failed = results.failed + 1
            end
        else
            print("\033[33m⚠ Error loading\033[0m")
        end
        
        os.execute("sleep 0.5")  -- Pause for visibility
    end
    
    -- Show final results
    clearScreen()
    print("╔══════════════════════════════════════╗")
    print("║            Test Results             ║")
    print("╚══════════════════════════════════════╝")
    print()
    print("\033[32mPassed: " .. results.passed .. "\033[0m")
    print("\033[31mFailed: " .. results.failed .. "\033[0m")
    print("\033[33mSkipped: " .. results.skipped .. "\033[0m")
    print("Total: " .. results.total)
    print()
    
    if results.failed == 0 then
        print("\033[42m\033[30m ALL TESTS PASSED \033[0m")
    else
        print("\033[41m\033[30m TESTS FAILED: " .. results.failed .. " \033[0m")
    end
end

-- Start the runner
runTests()
EOF

echo "Creating example test..."
cat > tests/example.spec.lua << 'EOF'
local expect = require(TestEZ.Expectation).new

return {
    ["Basic Math"] = {
        ["addition works"] = function()
            expect(1 + 1).to.equal(2)
        end,
        
        ["subtraction works"] = function()
            expect(5 - 3).to.equal(2)
        end
    },
    
    ["String Operations"] = {
        ["concatenation works"] = function()
            expect("Hello" .. " " .. "World").to.equal("Hello World")
        end
    }
}
EOF

echo "Installing TestEZ..."
luau-lsp require TestEZ

echo "Setup complete!"
echo "Run tests with: lune test-runner.lua"
