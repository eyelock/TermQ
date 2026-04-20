import AppKit
import ArgumentParser
import Foundation
import MCPServerLib
import TermQShared

// MARK: - GUI Communication Helpers (URL Schemes)

func deleteViaGUI(cardId: UUID, permanent: Bool) throws {
    var components = URLComponents()
    components.scheme = AppProfile.Current.urlScheme
    components.host = "delete"

    components.queryItems = [
        URLQueryItem(name: "id", value: cardId.uuidString),
        URLQueryItem(name: "permanent", value: permanent ? "true" : "false"),
    ]

    guard let url = components.url else {
        JSONHelper.printErrorJSON("Failed to construct URL")
        throw ExitCode.failure
    }

    let workspace = NSWorkspace.shared
    let success = workspace.open(url)

    if success {
        JSONHelper.printJSON(DeleteResponse(id: cardId.uuidString, permanent: permanent))
    } else {
        JSONHelper.printErrorJSON("Failed to send delete command to TermQ. Is it running?")
        throw ExitCode.failure
    }
}

func moveViaGUI(cardId: UUID, toColumn: String) throws {
    var components = URLComponents()
    components.scheme = AppProfile.Current.urlScheme
    components.host = "move"

    components.queryItems = [
        URLQueryItem(name: "id", value: cardId.uuidString),
        URLQueryItem(name: "column", value: toColumn),
    ]

    guard let url = components.url else {
        JSONHelper.printErrorJSON("Failed to construct URL")
        throw ExitCode.failure
    }

    let workspace = NSWorkspace.shared
    let success = workspace.open(url)

    if success {
        JSONHelper.printJSON(MoveResponse(success: true, id: cardId.uuidString, column: toColumn))
    } else {
        JSONHelper.printErrorJSON("Failed to send move command to TermQ. Is it running?")
        throw ExitCode.failure
    }
}

struct SetOptions {
    let cardId: UUID
    let name: String?
    let description: String?
    let column: String?
    let badge: String?
    let llmPrompt: String?
    let llmNextAction: String?
    let tags: [String]
    let replaceTags: Bool
    let initCommand: String?
    let favourite: Bool
    let unfavourite: Bool
}

func setViaGUI(_ options: SetOptions) throws {
    var components = URLComponents()
    components.scheme = AppProfile.Current.urlScheme
    components.host = "update"

    var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "id", value: options.cardId.uuidString)
    ]

    if let name = options.name { queryItems.append(URLQueryItem(name: "name", value: name)) }
    if let description = options.description { queryItems.append(URLQueryItem(name: "description", value: description)) }
    if let column = options.column { queryItems.append(URLQueryItem(name: "column", value: column)) }
    if let badge = options.badge { queryItems.append(URLQueryItem(name: "badge", value: badge)) }
    if let llmPrompt = options.llmPrompt { queryItems.append(URLQueryItem(name: "llmPrompt", value: llmPrompt)) }
    if let llmNextAction = options.llmNextAction { queryItems.append(URLQueryItem(name: "llmNextAction", value: llmNextAction)) }
    for tagStr in options.tags { queryItems.append(URLQueryItem(name: "tag", value: tagStr)) }
    if options.replaceTags { queryItems.append(URLQueryItem(name: "replaceTags", value: "true")) }
    if let initCommand = options.initCommand { queryItems.append(URLQueryItem(name: "initCommand", value: initCommand)) }
    if options.favourite { queryItems.append(URLQueryItem(name: "favourite", value: "true")) }
    if options.unfavourite { queryItems.append(URLQueryItem(name: "favourite", value: "false")) }

    components.queryItems = queryItems

    guard let url = components.url else {
        JSONHelper.printErrorJSON("Failed to construct URL")
        throw ExitCode.failure
    }

    let workspace = NSWorkspace.shared
    let success = workspace.open(url)

    if success {
        JSONHelper.printJSON(SetResponse(success: true, id: options.cardId.uuidString))
    } else {
        JSONHelper.printErrorJSON("Failed to send update to TermQ. Is it running?")
        throw ExitCode.failure
    }
}

func createViaGUI(
    name: String?,
    description: String?,
    column: String?,
    tags: [String],
    workingDirectory: String
) throws {
    var components = URLComponents()
    components.scheme = AppProfile.Current.urlScheme
    components.host = "open"

    var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "path", value: workingDirectory)
    ]

    if let name = name { queryItems.append(URLQueryItem(name: "name", value: name)) }
    if let description = description { queryItems.append(URLQueryItem(name: "description", value: description)) }
    if let column = column { queryItems.append(URLQueryItem(name: "column", value: column)) }
    for tagStr in tags { queryItems.append(URLQueryItem(name: "tag", value: tagStr)) }

    components.queryItems = queryItems

    guard let url = components.url else {
        JSONHelper.printErrorJSON("Failed to construct URL")
        throw ExitCode.failure
    }

    let workspace = NSWorkspace.shared
    let bundleId = termqBundleIdentifier()
    let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

    if runningApps.isEmpty {
        print("TermQ is not running. Launching...")
        if !launchTermQ() {
            let appName = AppProfile.Current.appBundleName
            JSONHelper.printErrorJSON(
                "Could not find or launch \(appName). Please ensure \(appName) is in /Applications or current directory"
            )
            throw ExitCode.failure
        }
    }

    let success = workspace.open(url)

    if success {
        print("Creating terminal in TermQ: \(workingDirectory)")
        if let name = name { print("  Name: \(name)") }
        if let description = description { print("  Description: \(description)") }
        if let column = column { print("  Column: \(column)") }
    } else {
        JSONHelper.printErrorJSON("Failed to communicate with TermQ. Make sure TermQ is running")
        throw ExitCode.failure
    }
}

func newViaGUI(name: String, column: String?, workingDirectory: String) throws {
    var components = URLComponents()
    components.scheme = AppProfile.Current.urlScheme
    components.host = "open"

    let cardId = UUID()

    var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "id", value: cardId.uuidString),
        URLQueryItem(name: "path", value: workingDirectory),
        URLQueryItem(name: "name", value: name),
    ]

    if let column = column { queryItems.append(URLQueryItem(name: "column", value: column)) }

    components.queryItems = queryItems

    guard let url = components.url else {
        JSONHelper.printErrorJSON("Failed to construct URL")
        throw ExitCode.failure
    }

    let workspace = NSWorkspace.shared
    let bundleId = termqBundleIdentifier()
    let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleId }

    if runningApps.isEmpty {
        if !launchTermQ() {
            let appName = AppProfile.Current.appBundleName
            JSONHelper.printErrorJSON(
                "Could not find or launch \(appName). Please ensure \(appName) is in /Applications or current directory"
            )
            throw ExitCode.failure
        }
    }

    let success = workspace.open(url)

    if success {
        let output = PendingCreateResponse(
            id: cardId.uuidString,
            status: "created",
            message: "Terminal created at: \(workingDirectory)"
        )
        JSONHelper.printJSON(output)
    } else {
        JSONHelper.printErrorJSON("Failed to communicate with TermQ")
        throw ExitCode.failure
    }
}
