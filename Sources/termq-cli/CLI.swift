import AppKit
import ArgumentParser
import Foundation

@main
struct TermQCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "termq",
        abstract: "Command-line interface for TermQ - Terminal Queue Manager",
        version: "1.0.0",
        subcommands: [Open.self, Launch.self],
        defaultSubcommand: Open.self
    )
}

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a new terminal in TermQ at the current directory"
    )

    @Option(name: [.short, .long], help: "Name/title for the terminal")
    var name: String?

    @Option(name: [.short, .long], help: "Description for the terminal")
    var description: String?

    @Option(name: [.short, .long], help: "Column to place the terminal in (e.g., 'To Do', 'In Progress')")
    var column: String?

    @Option(name: [.short, .long], parsing: .upToNextOption, help: "Tags in key=value format")
    var tag: [String] = []

    @Option(name: [.short, .long], help: "Working directory (defaults to current directory)")
    var path: String?

    func run() throws {
        let cwd = path ?? FileManager.default.currentDirectoryPath

        // Build URL with parameters
        var components = URLComponents()
        components.scheme = "termq"
        components.host = "open"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "path", value: cwd)
        ]

        if let name = name {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }

        if let description = description {
            queryItems.append(URLQueryItem(name: "description", value: description))
        }

        if let column = column {
            queryItems.append(URLQueryItem(name: "column", value: column))
        }

        for tagStr in tag {
            queryItems.append(URLQueryItem(name: "tag", value: tagStr))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            print("Error: Failed to construct URL")
            throw ExitCode.failure
        }

        // First, ensure TermQ is running
        let workspace = NSWorkspace.shared
        let bundleId = "com.termq.app"

        // Check if TermQ is running
        let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

        if runningApps.isEmpty {
            // Try to launch TermQ
            print("TermQ is not running. Launching...")

            // Try common locations
            let possiblePaths = [
                "/Applications/TermQ.app",
                "\(NSHomeDirectory())/Applications/TermQ.app",
                "\(FileManager.default.currentDirectoryPath)/TermQ.app",
                // Also check the build directory relative to the CLI
                URL(fileURLWithPath: #file)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("TermQ.app")
                    .path,
            ]

            var launched = false
            for appPath in possiblePaths {
                if FileManager.default.fileExists(atPath: appPath) {
                    // Use Process with /usr/bin/open to avoid deadlock with
                    // DispatchSemaphore + NSWorkspace.openApplication async callback
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = ["-a", appPath, "--wait-apps"]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice

                    do {
                        try process.run()
                        // Wait briefly for app to initialize
                        Thread.sleep(forTimeInterval: 1.0)
                        launched = true
                        break
                    } catch {
                        continue
                    }
                }
            }

            if !launched {
                print("Error: Could not find or launch TermQ.app")
                print("Please ensure TermQ.app is in /Applications or current directory")
                throw ExitCode.failure
            }
        }

        // Open the URL
        let success = workspace.open(url)

        if success {
            print("Opening terminal in TermQ: \(cwd)")
            if let name = name {
                print("  Name: \(name)")
            }
            if let description = description {
                print("  Description: \(description)")
            }
            if let column = column {
                print("  Column: \(column)")
            }
        } else {
            print("Error: Failed to communicate with TermQ")
            print("Make sure TermQ is running")
            throw ExitCode.failure
        }
    }
}

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch the TermQ application"
    )

    func run() throws {
        let possiblePaths = [
            "/Applications/TermQ.app",
            "\(NSHomeDirectory())/Applications/TermQ.app",
            "\(FileManager.default.currentDirectoryPath)/TermQ.app",
        ]

        for appPath in possiblePaths {
            if FileManager.default.fileExists(atPath: appPath) {
                // Use Process with /usr/bin/open to avoid deadlock with
                // DispatchSemaphore + NSWorkspace.openApplication async callback
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", appPath]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        print("Launched TermQ from: \(appPath)")
                        return
                    }
                } catch {
                    continue
                }
            }
        }

        print("Error: Could not find TermQ.app")
        print("Please ensure TermQ.app is in /Applications or current directory")
        throw ExitCode.failure
    }
}
