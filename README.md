# Lune Luau Test Runner

A Lune-based test runner for Luau source code with a browser dashboard (server mode) and headless/CI mode. Includes shared mock libraries for Roblox datatypes and services.

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| [Lune](https://lune-org.github.io/docs) | 0.8 | Runs `.luau` scripts outside Roblox |
| Python | 3.8+ | Source-rewriting pipeline |

## Getting started (as a git submodule)

```bash
# Add to your project
git submodule add <repo-url> test-runner

# Create a config file at your project root
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
│   └── ...                           # Test runner source
├── test-runner.config.luau           # Your project configuration
└── default.project.json              # Rojo project file
```

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

Create `test-runner.config.luau` at your project root. Example:

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

All keys are optional. Missing keys fall back to defaults.

## Mock libraries: built-in vs project-specific

The submodule ships with shared mocks in `test-runner/mocks/`:
- **Vector2**, **Vector3**, **Color3**, **BrickColor** — Roblox datatype mocks
- **Safe_Memory_Store_Hashmap** — MemoryStore HashMap wrapper
- **Packets_List** — Packet communication stubs
- **game** — Core Roblox game mock with RunService, Players, MemoryStore shims

Project-specific mocks in `src/Mock_Roblox_Libs/` override built-in mocks with the same filename. This lets you replace `game.luau` with a version that points to your project's `.rbxlx` file, or add mocks like `Match_Results.luau` that are specific to your game logic.

## Server mode

Starts an HTTP + WebSocket server. Open `http://localhost:<port>` in a browser to view the live dashboard.

### Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | HTML dashboard |
| `GET` | `/results` | Current results snapshot (JSON) |
| `POST` | `/run` | Trigger a test run (async; returns 202 immediately) |
| `WS` | `/stream` | WebSocket live event stream |

## Adding tests

Place test files in your `tests/` directory. Any `.luau` or `.lua` file is discovered automatically. The runner supports TestEZ-compatible `describe`/`it`/`expect` syntax:

```luau
describe("Group name", function()
    it("does something", function()
        expect(1 + 1).to.equal(2)
        expect(someTable).to.be.ok()
        expect(badFn).to.throw()
    end)
end)
```

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
