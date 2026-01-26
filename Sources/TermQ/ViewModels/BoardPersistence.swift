import Foundation
import TermQCore

/// Non-actor-isolated helper class for file system monitoring
/// This class exists to avoid Swift 6 strict concurrency issues with dispatch sources
/// When a @MainActor class creates a dispatch source handler closure, Swift 6 rejects it
/// because the closure inherits actor isolation but executes on a different queue
final class FileMonitor: @unchecked Sendable {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let onChange: @Sendable () -> Void

    init(path: String, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        startMonitoring(path: path)
    }

    deinit {
        stopMonitoring()
    }

    func restartMonitoring(path: String) {
        stopMonitoring()
        startMonitoring(path: path)
    }

    private func startMonitoring(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            #if DEBUG
                print("[FileMonitor] Failed to open file for monitoring: \(path)")
            #endif
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        let callback = self.onChange
        source.setEventHandler {
            callback()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        self.fileDescriptor = fd
        self.source = source

        #if DEBUG
            print("[FileMonitor] Started monitoring: \(path)")
        #endif
    }

    private func stopMonitoring() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}

/// Handles board persistence (save/load) and file monitoring
/// Extracted from BoardViewModel for single responsibility
@MainActor
public final class BoardPersistence {
    let saveURL: URL
    private var fileMonitor: FileMonitor?
    private var onExternalChange: (() -> Void)?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #if DEBUG
            let termqDir = appSupport.appendingPathComponent("TermQ-Debug", isDirectory: true)
        #else
            let termqDir = appSupport.appendingPathComponent("TermQ", isDirectory: true)
        #endif

        try? FileManager.default.createDirectory(at: termqDir, withIntermediateDirectories: true)
        self.saveURL = termqDir.appendingPathComponent("board.json")
    }

    deinit {
        fileMonitor = nil
    }

    // MARK: - Loading

    /// Load board from disk, or return a new empty board
    func loadBoard() -> Board {
        if let data = try? Data(contentsOf: saveURL),
            let loaded = try? JSONDecoder().decode(Board.self, from: data)
        {
            #if DEBUG
                print("[BoardPersistence] Loaded board from: \(saveURL.path)")
            #endif
            return loaded
        } else {
            #if DEBUG
                print("[BoardPersistence] Created new empty board")
            #endif
            return Board()
        }
    }

    // MARK: - Saving

    /// Save board to disk
    func save(_ board: Board) throws {
        let data = try JSONEncoder().encode(board)
        try data.write(to: saveURL)
    }

    // MARK: - File Monitoring

    /// Start monitoring for external changes
    /// - Parameter onExternalChange: Called when file changes are detected
    func startFileMonitoring(onExternalChange: @escaping () -> Void) {
        self.onExternalChange = onExternalChange
        let path = saveURL.path

        fileMonitor = FileMonitor(path: path) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.onExternalChange?()
                self.fileMonitor?.restartMonitoring(path: self.saveURL.path)
            }
        }
    }

    /// Reload board from disk for external changes
    func reloadForExternalChanges() -> Board? {
        #if DEBUG
            print("[BoardPersistence] File change detected, reloading...")
        #endif

        guard let data = try? Data(contentsOf: saveURL),
            let loaded = try? JSONDecoder().decode(Board.self, from: data)
        else {
            #if DEBUG
                print("[BoardPersistence] Failed to reload board from file")
            #endif
            return nil
        }

        return loaded
    }

    /// Merge external changes into existing board
    /// Preserves session state while updating card properties
    static func mergeExternalChanges(from loaded: Board, into board: Board) {
        for loadedCard in loaded.cards {
            if let existingCard = board.cards.first(where: { $0.id == loadedCard.id }) {
                existingCard.title = loadedCard.title
                existingCard.description = loadedCard.description
                existingCard.workingDirectory = loadedCard.workingDirectory
                existingCard.shellPath = loadedCard.shellPath
                existingCard.columnId = loadedCard.columnId
                existingCard.orderIndex = loadedCard.orderIndex
                existingCard.isFavourite = loadedCard.isFavourite
                existingCard.tags = loadedCard.tags
                existingCard.initCommand = loadedCard.initCommand
                existingCard.llmPrompt = loadedCard.llmPrompt
                existingCard.llmNextAction = loadedCard.llmNextAction
                existingCard.badge = loadedCard.badge
                existingCard.fontName = loadedCard.fontName
                existingCard.fontSize = loadedCard.fontSize
                existingCard.safePasteEnabled = loadedCard.safePasteEnabled
                existingCard.themeId = loadedCard.themeId
                existingCard.allowAutorun = loadedCard.allowAutorun
                existingCard.deletedAt = loadedCard.deletedAt
                existingCard.lastLLMGet = loadedCard.lastLLMGet
            } else {
                board.cards.append(loadedCard)
            }
        }

        board.columns = loaded.columns
        board.favouriteOrder = loaded.favouriteOrder

        #if DEBUG
            print("[BoardPersistence] Merged board with \(board.cards.count) cards")
        #endif
    }
}
