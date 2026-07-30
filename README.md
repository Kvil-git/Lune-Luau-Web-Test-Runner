# Lune Luau Test Runner

A testing framework for Luau (Roblox's scripting language) with a real-time web dashboard and headless/CI mode. Includes shared mock libraries for Roblox datatypes and services. Built on the [Lune](https://github.com/filiptibell/lune) runtime.

## Features

- **Real-time Dashboard**: Live WebSocket-based test updates in the browser.
- **Dual Mode**: Server mode (interactive web UI) or headless mode (terminal/CI).
- **Shared Mocks**: Built-in Roblox datatype and service mocks (Vector2/3, Color3, BrickColor, etc.).
- **Project Overrides**: Project-specific mocks in `src/Mock_Roblox_Libs/` override built-in ones by filename.
- **TestEZ Syntax**: `describe`/`it`/`expect` blocks with matchers like `.equal()`, `.be.ok()`, `.throw()`.
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
| `testez_compat.luau` | TestEZ compatibility layer (`describe`/`it`/`expect` implementation) |
| `Server.luau` | HTTP + WebSocket server implementation using Lune's `net` module |
| `Frontend.luau` | Web dashboard route handlers |
| `WebSocketManager.luau` | WebSocket connection management |
| `HttpRouter.luau` | HTTP route matching |
| `Logger.luau` | Structured logging |
| `EventBus.luau` | Internal pub/sub event system |
| `Types.luau` | Type definitions for strict mode |
| `Parse_Scripts_For_Tests.py` | Python source-rewriting pipeline |
| `run.luau` | CLI entry point |

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
| `--help`, `-h` | — | Print usage and exit |

### Exit codes (headless mode)

| Code | Meaning |
|---|---|
| 0 | All tests passed (or no tests found) |
| 1 | One or more tests failed |

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

## Mock libraries: built-in vs project-specific

The submodule ships with shared mocks in `test-runner/mocks/`:

- **Vector2**, **Vector3**, **Color3**, **BrickColor** — Roblox datatype mocks
- **Safe_Memory_Store_Hashmap** — MemoryStore HashMap wrapper
- **Packets_List** — Packet communication stubs
- **game** — Core Roblox game mock with RunService, Players, MemoryStore shims; reads the actual `.rbxlx` file if a path is configured

Project-specific mocks in `src/Mock_Roblox_Libs/` override built-in mocks with the same filename. This lets you replace `game.luau` with a version that points to a different `.rbxlx` file, or add mocks like `Match_Results.luau` that are specific to your game logic.

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

## Writing tests

Place test files in your `tests/` directory. Files can use `.luau` or `.lua` extension. The runner supports TestEZ-compatible `describe`/`it`/`expect` syntax:

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

### Matchers

| Matcher | Description |
|---|---|
| `.equal(value)` | Deep equality |
| `.be.ok()` | Truthy |
| `.be.NaN()` | `NaN` |
| `.be.nil()` | `nil` |
| `.throw()` | Function throws an error |
| `.never` | Negates the next matcher |

### Test file conventions

- Files ending in `.spec.luau` (e.g. `math.spec.luau`) are treated as test suites using the `describe`/`it` syntax above.
- Other `.luau` / `.lua` files in the tests directory are also discovered.

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

## Error handling

| Scenario | Behavior |
|---|---|
| Test folder missing | Adds a pseudo-test with the error message |
| No test files | Shows a single "No Tests Found" skipped test |
| Syntax error in test | Captures and displays the compilation error |
| Runtime error during test | Shows error details in the dashboard / terminal output |
| Module did not return a function (legacy format) | Reports with a descriptive failure message |

## Development notes

- Uses **Luau's strict mode** (`--!strict`) for type safety throughout.
- Lune's built-in modules are used for filesystem, networking, and serialization.
- Test execution is **synchronous** — tests run sequentially within a single file.
- The dashboard uses **vanilla JavaScript** with no external dependencies.
- The source code is documented for readability.

## License

Provided as-is for educational and practical use with Luau testing.
