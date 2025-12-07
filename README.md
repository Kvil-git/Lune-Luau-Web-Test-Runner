# Lune Test Runner

## Overview

Test Runner is a testing framework for Luau (Roblox's scripting  language) that provides a modern, real-time dashboard for executing and monitoring test results. It consists of a backend web server written in Luau using the [Lune](https://github.com/filiptibell/lune) runtime and a responsive frontend web interface.

<img width="1920" height="1034" alt="изображение" src="https://github.com/user-attachments/assets/eb29bc3f-14a0-4da6-8934-b4e3ea8271fb" />


## Features

- **Real-time Test Results**: Live updates of test execution status.
- **Web-based Dashboard**: Clean, modern interface for viewing test results.
- **Test Filtering**: Filter tests by status (All, Passed, Failed, Skipped).
- **Error Details**: Click to expand error messages for failed tests.
- **Automatic Refresh**: Periodic updates every 5 seconds.
- **One-click Execution**: Run all tests from the web interface.
- **Detailed Statistics**: Summary cards showing test counts and statuses.
- **Good code:** The source code is well documented and written for maximum readability.

## Project Structure

Below is a diagram made with [code2prompt](https://code2prompt.dev/docs/welcome/):

```
Test_Runner/
├── src/
│   ├── Constants.luau      # Configuration and constants
│   ├── Front_End.html      # Web dashboard interface
│   ├── Server.luau         # HTTP server implementation
│   ├── Test_Loader.luau    # Test file loading utilities
│   ├── Test_Runner.luau    # Core test execution logic
│   ├── Types.luau          # Type definitions
│   └── main.luau           # Application entry point
└── tests/
    ├── error_example.luau  # Example test that fails
    └── passed_example.luau # Example test that passes
```

And here's a vscode's explorer screenshot:

<img width="220" height="263" alt="изображение" src="https://github.com/user-attachments/assets/c1018f12-3b41-435d-a45f-54159ed0c2d2" />




## Requirements

- [Lune](https://github.com/filiptibell/lune) runtime environment
- Basic understanding of Luau programming

## Installation & Setup

1. **Clone or download the project** to your local machine.

2. **Install Lune** if not already installed.

3. **Navigate to the project directory.**

4. **Add your test files** to the `tests/` directory. Test files should:

   - Have `.luau` or `.lua` extension

   - Return a function

   - The function should return one of three strings: `"Passed"`, `"Failed"`, or `"Skipped"`

   - To error out of the test module, you can use

     ```luau
     error("Message")
     ```

     This will be displayed as an actual error message in the web interface:
     
     <img width="418" height="146" alt="изображение" src="https://github.com/user-attachments/assets/45f12943-b69b-410d-91dd-ccb6f6ebfb43" />
     
     <img width="1208" height="92" alt="изображение" src="https://github.com/user-attachments/assets/805b1d17-9f06-493d-a641-7a55942b2e30" />


## Usage

### Starting the Server

Run the following command from the project root:

```bash
cd src
lune run main.luau
```

After that you will see a debug message in your console, and the local web-server will become accessible.


<img width="672" height="290" alt="изображение" src="https://github.com/user-attachments/assets/8c275618-f277-4793-a674-3f9f5b56705c" />


### Accessing the Dashboard

Open your web browser and navigate to:

```
http://localhost:8080
```
<img width="1920" height="1034" alt="изображение" src="https://github.com/user-attachments/assets/1d6cf93b-3fee-4723-bf9c-b6de4c90fb8d" />



### Dashboard Interface

The dashboard consists of:

1. **Header**: Contains the title and control buttons
   - **Run Tests**: Executes all tests
   - **Refresh**: Manually refreshes test results
2. **Statistics Cards**:
   - **Total Tests**: Total number of tests found
   - **Passed**: Number of tests that returned `"Passed"`
   - **Failed**: Number of tests that failed or errored
   - **Skipped**: Number of tests that returned `"Skipped"`
3. **Filter Buttons**: Filter the test list by status
4. **Test List**: Detailed view of each test with:
   - Test name and file path
   - Status badge (Passed/Failed/Skipped)
   - Clickable error details for failed tests

## API Endpoints

The server exposes the following endpoints:

| Endpoint   | Method | Description                  | Response                 |
| ---------- | ------ | ---------------------------- | ------------------------ |
| `/`        | GET    | Serves the web dashboard     | HTML page                |
| `/results` | GET    | Returns current test results | JSON                     |
| `/run`     | POST   | Triggers test execution      | JSON with success status |

## Writing Tests

### Basic Test Structure

Create a `.luau` file in the `tests/` directory with the following format:

```luau
return function()
    -- Your test logic here
    
    if condition_met then
        return "Passed"
    elseif should_skip then
        return "Skipped"
    else
        return "Failed"
    end
end
```



### Test Examples

**Passing Test:**

```luau
return function()
    -- Simulate test logic
    local result = 2 + 2
    assert(result == 4, "Math is broken!")
    return "Passed"
end
```



**Failing Test:**

```luau
return function()
    error("Test case failed: Expected value not found")
    return "Failed"
end
```



**Skipped Test:**

```luau
return function()
    -- Skip test if certain conditions aren't met
    if not should_run_test then
        return "Skipped"
    end
    
    -- Regular test logic
    return "Passed"
end
```



## Configuration

Modify `src/Constants.luau` to adjust settings:

| Constant        | Description                                                  | Default                         |
| --------------- | ------------------------------------------------------------ | ------------------------------- |
| `TEST_FOLDER`   | Directory containing test files                              | `"../tests"`                    |
| `FRONTEND_HTML` | The frontend html file stored as a big string of characters.<br />`Adjust the argument to fs.readFile(...) to change the path to the html file, e.g. fs.readFile("./Hi.html").` | fs.readFile("./Front_End.html") |
| `PORT`          | HTTP server port                                             | `(8080)`                        |

## Module Details

### Constants.luau

Contains application-wide constants and reads the frontend HTML file.

### Front_End.html

Responsive web interface with real-time updates, filtering, and error display. (Vibecoded)

### Server.luau

HTTP server implementation using Lune's `net` module. Handles routing and request processing.

### Test_Loader.luau

Utility functions for:

- Scanning the test directory for `.luau` / `.lua` files
- Loading and compiling test functions from files

### Test_Runner.luau

Core test execution logic:

- Manages test execution state
- Evaluates test results
- Tracks execution times
- Handles test failures and errors

### Types.luau

Type definitions for type-safe development with Luau's strict mode.

### main.luau

Application entry point that starts the server.

## Error Handling

The test runner handles various error scenarios:

1. **Missing test folder**: Adds a pseudo-test showing the error.
2. **No test files**: Shows a single "No Tests Found" skipped test.
3. **Syntax errors in test files**: Captures and displays compilation errors.
4. **Runtime errors during test execution**: Shows error details in the dashboard.

## Development Notes

- The project uses **Luau's strict mode** (`--!strict`) for type safety.
- **Lune modules** are used for filesystem operations, networking, and serialization.
- Test execution is **synchronous** - tests run in a sequence.
- The dashboard uses **vanilla JavaScript** with no external dependencies.
- The front-end part of the page was **vibecoded in one go** with no additional adjustments =)

## Troubleshooting

### Common Issues

1. **"Folder not found" error**: Ensure the `tests/` directory exists relative to the executable
2. **Port already in use**: Change the `PORT` constant in `Constants.luau`
3. **Tests not showing up**: Verify test files have `.luau` or `.lua` extension
4. **"Module did not return a function"**: Ensure test files return a function, not a value

### Debug Tips

- Check the console where you started the server for startup messages
- Use browser developer tools to inspect network requests
- Verify test file permissions and paths

## License

This project is provided as-is for educational and practical use with Luau testing.

Would be nice if you mentioned using it with a link to this page though =)
