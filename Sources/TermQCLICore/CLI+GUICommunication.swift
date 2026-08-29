import AppKit
import ArgumentParser
import Foundation
import MCPServerLib
import TermQShared

// MARK: - GUI Communication Helpers (URL Schemes)

/// Where to re-read the board when confirming a GUI-routed command.
struct BoardContext {
    let dataDirectory: URL?
    let profile: AppProfile.Variant
    let boardFilename: String

    func load() throws -> Board {
        try BoardLoader.loadBoard(
            dataDirectory: dataDirectory, profile: profile, boardFilename: boardFilename)
    }
}

/// Poll the board until `condition` holds, or the retry budget runs out.
///
/// `NSWorkspace.open` reports only that a URL was dispatched, never that the app acted on it, so
/// a GUI-routed command has to be read back off the board before it can be called done. The budget
/// mirrors `URLOpener.waitForCondition` on the MCP side so both front ends agree on when a command
/// has been dropped; the CLI is synchronous, so this sleeps rather than awaits.
func waitForBoardCondition(
    maxAttempts: Int = 4,
    initialDelayMs: UInt32 = 100,
    condition: () throws -> Bool
) -> Bool {
    var delayMs = initialDelayMs

    for attempt in 1...maxAttempts {
        Thread.sleep(forTimeInterval: Double(delayMs) / 1000)
        if (try? condition()) == true {
            return true
        }
        if attempt < maxAttempts {
            delayMs *= 2
        }
    }

    return false
}

/// Fail a GUI-routed command that never showed up on the board.
///
/// The board write behind these commands is synchronous, so a change still missing after the full
/// retry budget was not applied — reporting success here is what let a dropped command pass for a
/// completed one.
func reportUnconfirmed(_ action: String, hint: String? = nil) -> Error {
    var message =
        "TermQ accepted the \(action) request but the board never changed, so it was not applied."
    if let hint {
        message += " \(hint)"
    }
    JSONHelper.printErrorJSON(message)
    return ExitCode.failure
}

func deleteViaGUI(cardId: UUID, permanent: Bool, context: BoardContext) throws {
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
    guard workspace.open(url) else {
        JSONHelper.printErrorJSON("Failed to send delete command to TermQ. Is it running?")
        throw ExitCode.failure
    }

    let cardIdStr = cardId.uuidString
    let confirmed = waitForBoardCondition {
        GUIConfirmation.cardIsAbsent(try context.load(), cardId: cardIdStr)
    }
    guard confirmed else {
        throw reportUnconfirmed("delete")
    }

    JSONHelper.printJSON(DeleteResponse(id: cardIdStr, permanent: permanent))
}

func moveViaGUI(cardId: UUID, toColumn: String, context: BoardContext) throws {
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
    guard workspace.open(url) else {
        JSONHelper.printErrorJSON("Failed to send move command to TermQ. Is it running?")
        throw ExitCode.failure
    }

    let cardIdStr = cardId.uuidString
    let confirmed = waitForBoardCondition {
        GUIConfirmation.cardIsInColumn(try context.load(), cardId: cardIdStr, column: toColumn)
    }
    guard confirmed else {
        throw reportUnconfirmed("move")
    }

    JSONHelper.printJSON(MoveResponse(success: true, id: cardIdStr, column: toColumn))
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

func setViaGUI(_ options: SetOptions, context: BoardContext) throws {
    var components = URLComponents()
    components.scheme = AppProfile.Current.urlScheme
    components.host = "update"

    var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "id", value: options.cardId.uuidString)
    ]

    if let name = options.name { queryItems.append(URLQueryItem(name: "name", value: name)) }
    if let description = options.description {
        queryItems.append(URLQueryItem(name: "description", value: description))
    }
    if let column = options.column { queryItems.append(URLQueryItem(name: "column", value: column)) }
    if let badge = options.badge { queryItems.append(URLQueryItem(name: "badge", value: badge)) }
    if let llmPrompt = options.llmPrompt { queryItems.append(URLQueryItem(name: "llmPrompt", value: llmPrompt)) }
    if let llmNextAction = options.llmNextAction {
        queryItems.append(URLQueryItem(name: "llmNextAction", value: llmNextAction))
    }
    for tagStr in options.tags { queryItems.append(URLQueryItem(name: "tag", value: tagStr)) }
    if options.replaceTags { queryItems.append(URLQueryItem(name: "replaceTags", value: "true")) }
    if let initCommand = options.initCommand {
        queryItems.append(URLQueryItem(name: "initCommand", value: initCommand))
    }
    if options.favourite { queryItems.append(URLQueryItem(name: "favourite", value: "true")) }
    if options.unfavourite { queryItems.append(URLQueryItem(name: "favourite", value: "false")) }

    components.queryItems = queryItems

    guard let url = components.url else {
        JSONHelper.printErrorJSON("Failed to construct URL")
        throw ExitCode.failure
    }

    let workspace = NSWorkspace.shared
    guard workspace.open(url) else {
        JSONHelper.printErrorJSON("Failed to send update to TermQ. Is it running?")
        throw ExitCode.failure
    }

    let cardIdStr = options.cardId.uuidString
    let parsedTags = parseTags(options.tags).map { Tag(key: $0.key, value: $0.value) }
    let favouriteValue: Bool? = options.favourite ? true : (options.unfavourite ? false : nil)
    let expected = GUIConfirmation.ExpectedUpdate(
        title: options.name,
        description: options.description,
        badge: options.badge,
        llmPrompt: options.llmPrompt,
        llmNextAction: options.llmNextAction,
        isFavourite: favouriteValue,
        column: options.column,
        requiredTags: options.replaceTags ? nil : (parsedTags.isEmpty ? nil : parsedTags),
        exactTags: options.replaceTags ? parsedTags : nil
    )

    let confirmed = waitForBoardCondition {
        let board = try context.load()
        // `initCommand` is the one field `set` accepts that never reaches board.json, so a request
        // carrying only that can be confirmed no further than the card surviving.
        guard expected.hasObservableFields else {
            return !GUIConfirmation.cardIsAbsent(board, cardId: cardIdStr)
        }
        return GUIConfirmation.cardMatches(board, cardId: cardIdStr, expected: expected)
    }
    guard confirmed else {
        let touchesLLMFields = options.llmPrompt != nil || options.llmNextAction != nil
        throw reportUnconfirmed(
            "update",
            hint: touchesLLMFields
                ? "TermQ can be set to confirm external LLM changes — a prompt may still be open."
                : nil)
    }

    JSONHelper.printJSON(SetResponse(success: true, id: cardIdStr))
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
