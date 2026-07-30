# Lune Luau Test Runner

A testing framework for Luau (Roblox's scripting language) with a real-time web dashboard and headless/CI mode. Includes shared mock libraries for Roblox datatypes and services. Built on the [Lune](https://github.com/filiptibell/lune) runtime.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Getting started (as a git submodule)](#getting-started-as-a-git-submodule)
- [Project structure](#project-structure)
- [Configuration](#configuration)
- [CLI reference](#cli-reference)
- [Writing tests](#writing-tests)
  - [TestEZ syntax](#testez-syntax)
  - [Test file conventions](#test-file-conventions)
  - [Matchers](#matchers)
  - [Hooks](#hooks)
  - [Skipping tests](#skipping-tests)
- [Property-based testing](#property-based-testing)
  - [Basic usage](#basic-usage)
  - [Strategy reference](#strategy-reference)
  - [Combinators](#combinators)
  - [Example patterns](#example-patterns)
  - [Shrinking](#shrinking)
  - [Reproducing failures](#reproducing-failures)
  - [How it works](#how-it-works)
- [Mock libraries](#mock-libraries)
- [How the pipeline works](#how-the-pipeline-works)
  - [Preprocessing in detail](#preprocessing-in-detail)
- [Server mode](#server-mode)
- [Error handling](#error-handling)
- [Rojo integration](#rojo-integration)
- [Development notes](#development-notes)
- [License](#license)

## Features

- **Real-time Dashboard**: Live WebSocket-based test updates in the browser.
- **Dual Mode**: Server mode (interactive web UI) or headless mode (terminal/CI).
- **Shared Mocks**: Built-in Roblox datatype and service mocks (Vector2/3, Color3, BrickColor, etc.).
- **Project Overrides**: Project-specific mocks in `src/Mock_Roblox_Libs/` override built-in ones by filename.
- **TestEZ Syntax**: `describe`/`it`/`expect` blocks with matchers like `.equal()`, `.be.ok()`, `.throw()`.
- **Property-based Testing**: Random input generation with automatic shrinking to minimal failures.
- **Test Filtering**: Filter by status (All, Passed, Failed, Skipped) in the web UI.
- **Error Details**: Click to expand error messages for failed tests.
- **One-click Execution**: Run all tests from the web interface.
- **Detailed Statistics**: Summary cards showing test counts and statuses.

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| [Lune](https://lune-org.github.io/docs) | 0.8 | Runs `.luau` scripts outside Roblox |
| Python | 3.8+ | Source-rewriting pipeline |

## Getting started (as a git submodule)

```bash
# Add to your project (from project root)
git submodule add <repo-url> test-runner

# Create a config file
cp test-runner/config/example.config.luau test-runner.config.luau
# Edit test-runner.config.luau to match your project layout

# Run tests (from project root)
lune run test-runner/run

# Headless / CI mode
lune run test-runner/run -- --headless
```

## Project structure (after adding submodule)

```
your-project/
├── src/                              # Your Luau source
│   └── Mock_Roblox_Libs/             # Project-specific mocks (optional)
│       └── game.luau                 # Overrides built-in game mock if needed
├── tests/                            # Your test files
├── test-runner/                      # This submodule
│   ├── run.luau                      # Entry point
│   ├── Constants.luau                # Reads test-runner.config.luau
│   ├── generators/                   # Property-based testing strategies
│   │   └── init.luau                 # g.integer, g.string, g.list, etc.
│   ├── testez_compat.luau            # TestEZ + given() implementation
│   ├── mocks/                        # Shared Roblox mock libraries
│   │   ├── Vector2.luau
│   │   ├── Vector3.luau
│   │   ├── Color3.luau
│   │   ├── BrickColor.luau
│   │   ├── Safe_Memory_Store_Hashmap.luau
│   │   ├── Packets_List.luau
│   │   └── game.luau
│   └── ...                           # Test runner source modules
├── test-runner.config.luau           # Your project configuration
└── default.project.json              # Rojo project file
```

### Submodule source modules

| File | Purpose |
|---|---|
| `Constants.luau` | Configuration — merges parent `test-runner.config.luau` with defaults |
| `Test_Runner.luau` | Core test execution logic, state management, pass/fail/skip tracking |
| `Test_Loader.luau` | Scans test directory, loads and compiles test functions |
| `sandbox.luau` | Sandboxed environment for test execution |
| `testez_compat.luau` | TestEZ compatibility layer (`describe`/`it`/`expect`) + `given()` property testing |
| `generators/init.luau` | All strategy factories (`g.integer`, `g.list`, `g.map`, etc.) |
| `Server.luau` | HTTP + WebSocket server implementation using Lune's `net` module |
| `Frontend.luau` | Web dashboard route handlers |
| `WebSocketManager.luau` | WebSocket connection management |
| `HttpRouter.luau` | HTTP route matching |
| `Logger.luau` | Structured logging |
| `EventBus.luau` | Internal pub/sub event system |
| `Types.luau` | Type definitions for strict mode |
| `Parse_Scripts_For_Tests.py` | Python source-rewriting pipeline |
| `run.luau` | CLI entry point |

## Configuration

Create `test-runner.config.luau` at your project root. All keys are optional — missing keys fall back to defaults.

```luau
return {
    SOURCE_FOLDER    = "./src",
    TEST_FOLDER      = "./tests",
    OUTPUT_FOLDER    = "./tests/Scripts_Copies_With_String_Requires",
    MOCK_LIBS_FOLDER = "./src/Mock_Roblox_Libs",
    PLACE_PATH_CANDIDATES = {
        "./Clash of Empires - Game.rbxlx",
    },
    PORT = 8080,
}
```

| Key | Default | Description |
|---|---|---|
| `SOURCE_FOLDER` | `"./src"` | Luau source directory (copied and rewritten during preprocessing) |
| `TEST_FOLDER` | `"./tests"` | Directory containing test files |
| `OUTPUT_FOLDER` | `"./tests/Scripts_Copies_With_String_Requires"` | Where the Python pipeline writes rewritten source |
| `MOCK_LIBS_FOLDER` | `"./src/Mock_Roblox_Libs"` | Project-specific mocks directory |
| `PLACE_PATH_CANDIDATES` | `{}` | `.rbxlx` file paths for `game.luau` mock to read |
| `PORT` | `8080` | HTTP server port |
| `SEED` | auto-generated | Deterministic seed for property-based test reproducibility |
| `EXAMPLES` | `100` | Number of generated examples per `given()` block |

## CLI reference

```
lune run test-runner/run [-- <flags>]
```

| Flag | Default | Description |
|---|---|---|
| *(no flags)* | — | Server mode: starts HTTP + WebSocket server at :8080 |
| `--headless`, `--ci` | off | Terminal mode: print results, exit with code |
| `--port <N>` | 8080 | Override HTTP port (server mode only) |
| `--json` | off | Write `results.json` after the run (headless only) |
| `--no-preprocess` | off | Skip the Python source-rewriting step |
| `--seed <N>` | auto | Deterministic seed for property-based tests |
| `--examples <N>` | 100 | Examples per `given()` block |
| `--help`, `-h` | — | Print usage and exit |

### Exit codes (headless mode)

| Code | Meaning |
|---|---|
| 0 | All tests passed (or no tests found) |
| 1 | One or more tests failed |

## Writing tests

Place test files in your `tests/` directory. Files can use `.luau` or `.lua` extensions.

### TestEZ syntax

The runner supports TestEZ-compatible `describe`/`it`/`expect` syntax:

```luau
describe("Arithmetic", function()
    it("adds numbers correctly", function()
        expect(1 + 1).to.equal(2)
    end)

    it("handles errors", function()
        expect(function()
            error("boom")
        end).to.throw()
    end)

    it("checks truthiness", function()
        expect(true).to.be.ok()
        expect(nil).to.never.be.ok()
    end)
end)
```

### Test file conventions

- Files ending in `.spec.luau` (e.g. `math.spec.luau`) are treated as test suites using the `describe`/`it` syntax above. The sandbox injects `describe`, `it`, `expect`, `given`, and `g` as globals.
- Other `.luau` / `.lua` files in the tests directory are also discovered. If they return a function, they are treated as legacy "return function" style tests (Style A).
- Test files can `require()` other modules from the project. The sandbox resolves relative paths from the test file's directory.

### Matchers

| Matcher | Description |
|---|---|
| `.equal(value)` | Deep equality |
| `.be.ok()` | Truthy (non-nil) |
| `.be.NaN()` | `NaN` |
| `.be.nil()` | `nil` |
| `.be.truthy()` | Non-nil and non-false |
| `.be.falsy()` | `nil` or `false` |
| `.be.a(type)` | Type check (e.g. `"string"`, `"number"`) |
| `.be.above(n)` | Numeric greater-than |
| `.be.below(n)` | Numeric less-than |
| `.be.near(n, delta?)` | Approximate equality |
| `.contain(item)` | Substring or table membership |
| `.throw(pattern?)` | Function throws (optionally matching pattern) |
| `.never` | Negates the next matcher |

### Hooks

TestEZ-compatible lifecycle hooks run before/after tests within a `describe` block:

```luau
describe("MyFeature", function()
    beforeAll(function()
        -- runs once before all tests in this describe
    end)

    afterAll(function()
        -- runs once after all tests in this describe
    end)

    beforeEach(function()
        -- runs before each it() block
    end)

    afterEach(function()
        -- runs after each it() block (even on failure)
    end)

    it("example", function()
        -- ...
    end)
end)
```

### Skipping tests

Use `xdescribe` or `xit` to skip tests without deleting them:

```luau
xdescribe("WIP feature", function()
    -- none of this will run
end)

describe("Stable feature", function()
    xit("known bug", function()
        -- this specific test is skipped
    end)
end)
```

Aliases: `SKIP` = `xit`, `test` = `it`.

## Property-based testing

The test runner supports **property-based testing** through the `given()` function, inspired by Python's Hypothesis library. Instead of writing individual examples, you define **strategies** that generate random inputs, and the runner automatically finds minimal failing examples.

### Basic usage

```luau
it("addition is commutative", function()
    given({
        a = g.integer(-100, 100),
        b = g.integer(-100, 100),
    }, function(args)
        expect(args.a + args.b).to.equal(args.b + args.a)
    end)
end)
```

This generates 100 random pairs of integers and tests the property. If any example fails, the runner **shrinks** the input to find the minimal failing case and reports it with the seed for reproduction.

The `given()` function takes two arguments:
1. A table of **named strategies** — each key becomes a field in the `args` table passed to the test body.
2. A **test body function** that receives the generated `args` table.

### Strategy reference

**Base strategies:**

| Factory | Description |
|---|---|
| `g.integer(min, max)` | Uniform random integer in `[min, max]` |
| `g.float(min, max)` | Uniform random float in `[min, max]` |
| `g.boolean()` | `true` or `false` |
| `g.character()` | Single printable ASCII character (code 32–126) |
| `g.string(min_len, max_len, char_strat?)` | String of random characters |
| `g.list(strat, min_size, max_size)` | List of values from a sub-strategy |
| `g.sampled({a, b, ...})` | Pick uniformly from a fixed set |
| `g.tuple({s1, s2, ...})` | Fixed-size tuple from multiple strategies |
| `g.dictionary(key_s, val_s, max_pairs?)` | Table with generated keys/values |

**Combinators:**

| Factory | Description |
|---|---|
| `g.map(strat, fn)` | Transform generated values with a function |
| `g.filter(strat, pred, max_attempts?)` | Keep only values matching a predicate |
| `g.one_of({s1, s2, ...})` | Uniform choice among strategies |
| `g.frequency({{weight, s}, ...})` | Weighted choice among strategies |

### Example patterns

**Filtering generated values:**

```luau
it("even numbers are divisible by 2", function()
    given({
        n = g.filter(g.integer(-100, 100), function(v)
            return v % 2 == 0
        end),
    }, function(args)
        expect(args.n % 2).to.equal(0)
    end)
end)
```

**Transforming generated values:**

```luau
it("doubled values are always positive", function()
    given({
        x = g.map(g.integer(1, 50), function(n)
            return n * 2
        end),
    }, function(args)
        expect(args.x % 2).to.equal(0)
    end)
end)
```

**Choosing among strategies:**

```luau
it("one_of picks from mixed strategies", function()
    given({
        v = g.one_of({
            g.sampled({"hello", "world"}),
            g.integer(1, 10),
        }),
    }, function(args)
        expect(type(args.v) == "string" or type(args.v) == "number").to.be.ok()
    end)
end)
```

**Weighted strategies:**

```luau
it("frequency prefers heavier weights", function()
    given({
        v = g.frequency({
            { weight = 9, strategy = g.sampled({"common"}) },
            { weight = 1, strategy = g.sampled({"rare"}) },
        }),
    }, function(args)
        expect(args.v).to.be.ok()
    end)
end)
```

**Fixed-size tuples:**

```luau
it("tuple generates structured data", function()
    given({
        entry = g.tuple({
            g.integer(1, 100),    -- id
            g.boolean(),           -- active
            g.string(0, 10),       -- name
        }),
    }, function(args)
        expect(#args.entry).to.equal(3)
        expect(type(args.entry[1])).to.equal("number")
        expect(type(args.entry[2])).to.equal("boolean")
    end)
end)
```

**Lists and data structures:**

```luau
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
```

**Dictionaries:**

```luau
it("dictionary keys are unique", function()
    given({
        d = g.dictionary(g.string(1, 5), g.integer(0, 100), 10),
    }, function(args)
        local keys = {}
        for k, _ in pairs(args.d) do
            table.insert(keys, k)
        end
        for i = 1, #keys do
            for j = i + 1, #keys do
                expect(keys[i]).never.to.equal(keys[j])
            end
        end
    end)
end)
```

**Stack invariant (LIFO):**

```luau
it("stack push-pop follows LIFO order", function()
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
```

### Shrinking

When a property test fails, the runner automatically **shrinks** the input toward simpler values:

- **Integers** → 0, ±1, then halve toward 0
- **Floats** → 0, then halve, then ±1 steps
- **Strings** → empty string, then shorter strings (removing from start and end)
- **Lists** → empty list, then remove elements one at a time
- **Booleans** → shrink toward `false`
- **Characters** → shrink toward `"a"`
- **Dictionaries** → empty table, then remove keys
- **Sampled** → earlier elements in the sample list
- **Tuples** → each element shrinks independently

Shrinking continues until stable — no simpler failing input can be found. The final result is the **minimal failing example**.

### Reproducing failures

When a property test fails, the runner prints the seed:

```
FAIL  addition is commutative
  Falsifying example: { a = 7, b = -7 }
  (seed: 483192)
```

Re-run with the same seed to reproduce:

```bash
lune run test-runner/run -- --headless --seed 483192
```

You can also set a fixed seed in your config:

```luau
-- test-runner.config.luau
return {
    SEED     = 42,
    EXAMPLES = 200,
}
```

### How it works

1. **Generate**: Each example seeds `math.random` with a deterministic value derived from the test seed and example index, then calls each strategy's `generate()` to produce inputs.
2. **Test**: Runs the test body with the generated inputs.
3. **Shrink**: On failure, tries each strategy's `shrink()` candidates for each field. If a candidate still fails, recurses on it. Continues until no field can be shrunk further.

The `given()` function is injected as a global alongside `describe`, `it`, and `expect` into every `.spec.luau` file's sandbox. The `g` global is a table of all strategy factories from `generators/init.luau`.

## Mock libraries: built-in vs project-specific

The submodule ships with shared mocks in `test-runner/mocks/`:

- **Vector2**, **Vector3**, **Color3**, **BrickColor** — Roblox datatype mocks
- **Safe_Memory_Store_Hashmap** — MemoryStore HashMap wrapper
- **Packets_List** — Packet communication stubs
- **game** — Core Roblox game mock with RunService, Players, MemoryStore shims; reads the actual `.rbxlx` file if a path is configured

Project-specific mocks in `src/Mock_Roblox_Libs/` override built-in mocks with the same filename. This lets you replace `game.luau` with a version that points to a different `.rbxlx` file, or add mocks like `Match_Results.luau` that are specific to your game logic.

## How the pipeline works

```
lune run test-runner/run -- --headless
         │
         ├─[1/2] Python: Parse_Scripts_For_Tests.py
         │         • Copies built-in mocks + project mocks → output/
         │         • Copies src/ → tests/Scripts_Copies_With_String_Requires/
         │         • Rewrites require() to flat "./Module" form
         │         • Injects mock-library requires
         │         • Removes Roblox folder-routing variables
         │
         └─[2/2] Lune: Test_Runner.Run_Tests()
                   • Discovers *.luau / *.spec.luau in tests/
                   • Loads each file through sandbox.luau
                   • Runs describe/it blocks via testez_compat.luau
                   • Aggregates pass/fail/skip counts
                   • Prints summary; exits 0 or 1
```

### Preprocessing in detail

The Python script (`Parse_Scripts_For_Tests.py`) prepares project source code so it can be loaded by Lune outside of Roblox. This is necessary because:

1. **Flat module resolution**: Roblox uses hierarchical `require(path.to.Module)` style requires. Lune needs flat `require("./Module")` style. The script rewrites all `require()` calls to extract the final path segment, so `require(game.RS.Modules.MyModule)` becomes `require("./MyModule")`. String-based requires like `require("../deep/path/Module")` are also flattened to `require("./Module")`.

2. **Mock injection**: Luau code often references Roblox types like `Vector3`, `Color3`, or `game` without explicit `require()` calls. The script scans each file for global name references, then prepends `local Vector3 = require("./Vector3")` lines if the file uses those names and the mock library exists.

3. **Folder variable removal**: Many Roblox Luau files define folder variables like `local RS = game.ReplicatedStorage` purely for building require paths. After require rewriting, these variables become unused dead code. The script detects and removes them.

4. **Output structure**: All processed source files and mock libraries are copied into a single flat output directory. Since filenames must be unique in a flat directory, duplicate filenames across subdirectories are warned about.

The pipeline can be skipped with `--no-preprocess` if you are running tests that do not depend on project source code (e.g., pure unit tests of standalone modules).

## Server mode

Starts an HTTP + WebSocket server. Open `http://localhost:<port>` in a browser to view the live dashboard.

### Dashboard interface

1. **Header**: Title and control buttons — **Run Tests** (executes all tests), **Refresh** (manual refresh)
2. **Statistics cards**: Total / Passed / Failed / Skipped
3. **Filter buttons**: Filter the test list by status
4. **Test list**: Each test shows name, file path, status badge, and clickable error details

### API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Serves the web dashboard HTML |
| `GET` | `/results` | Returns current test results (JSON) |
| `POST` | `/run` | Triggers test execution (async, returns 202 immediately) |
| `WS` | `/stream` | WebSocket live event stream |

## Error handling

| Scenario | Behavior |
|---|---|
| Test folder missing | Adds a pseudo-test with the error message |
| No test files | Shows a single "No Tests Found" skipped test |
| Syntax error in test | Captures and displays the compilation error |
| Runtime error during test | Shows error details in the dashboard / terminal output |
| Module did not return a function (legacy format) | Reports with a descriptive failure message |

## Rojo integration

The test runner is designed to work alongside [Rojo](https://rojo.space/) for Roblox project synchronization. Your `default.project.json` maps the source directories to Roblox service instances, while the test runner reads the same source files directly from disk.

Below is an example `default.project.json` for a Roblox project that uses this testing framework:

```json
{
    "name": "Clash Of Empires - Game",
    "tree": {
        "$className": "DataModel",
        "ReplicatedFirst": {
            "$path": "src/ReplicatedFirst"
        },
        "ReplicatedStorage": {
            "$path": "src/ReplicatedStorage"
        },
        "ServerScriptService": {
            "$path": "src/ServerScriptService"
        },
        "ServerStorage": {
            "$path": "src/ServerStorage"
        },
        "StarterGui": {
            "$path": "src/StarterGUI"
        },
        "StarterPlayer": {
            "StarterCharacterScripts": {
                "$path": "src/StarterPlayer/StarterCharacterScripts"
            },
            "StarterPlayerScripts": {
                "$path": "src/StarterPlayer/StarterPlayerScripts"
            }
        },
        "Workspace": {
            "$properties": {
                "FilteringEnabled": true
            },
            "Camera": {
                "$className": "Camera",
                "$properties": {
                    "CFrame": [-18.2177, 7.3471, -130.6763, 0.2095, -0.3409, 0.9165, 0, 0.9373, 0.3486, -0.9778, -0.073, 0.1963],
                    "Focus": [-20.0507, 6.6499, -131.0689, 1, 0, 0, 0, 1, 0, 0, 0, 1]
                }
            }
        }
    }
}
```

The test runner's config (`test-runner.config.luau`) points `SOURCE_FOLDER` to the same `./src` directory that Rojo syncs, so tests always run against the same source files.

## Development notes

- Uses **Luau's strict mode** (`--!strict`) for type safety throughout.
- Lune's built-in modules are used for filesystem, networking, and serialization.
- Test execution is **synchronous** — tests run sequentially within a single file.
- The dashboard uses **vanilla JavaScript** with no external dependencies.
- The source code is documented for readability.
- Property-based tests are seeded deterministically from the base seed + the `given()` call index within each test file.

## License

Licensed under the GNU Lesser General Public License v2.1. See [LICENSE](./LICENSE) for details.
