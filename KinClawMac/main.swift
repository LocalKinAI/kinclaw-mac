// Two jobs, one binary.
//
// Normally this is the app: a menubar-only panel, started by launchd or the
// Dock. With `--mcp-stdio` it is instead the MCP server the kinclaw kernel
// spawns for the panel's browser and terminal tools — a process that carries
// JSON-RPC lines to the running app and never touches AppKit. Same binary
// because the kernel's MCP client spawns a command, and this is the command
// that is always exactly as new as the app it talks to.
//
// This file is why there is no `@main` on KinClawMacApp: top-level code in
// main.swift and @main are the same slot, and only one of them can have it.

if CommandLine.arguments.contains("--mcp-stdio") {
    PanelMCPStdio.run()
} else {
    KinClawMacApp.main()
}
