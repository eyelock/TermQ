import Foundation

/// Injectable seam around `CommandRunner.run` for YNH-touching services.
///
/// Production code uses `LiveYNHCommandRunner`, which delegates straight to
/// `CommandRunner.run`. Tests inject a stub that returns canned `Result`
/// values without spawning a real subprocess — letting the success and
/// error branches of `HarnessRepository`, `VendorService`, `SourcesService`,
/// `HarnessSearchService`, and `LiveUpdateAvailabilityService` be exercised
/// without a `ynh` binary on disk.
protocol YNHCommandRunner: Sendable {
    // swiftlint:disable:next function_parameter_count
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result
}

extension YNHCommandRunner {
    /// Convenience for the common case where callers don't need streaming
    /// callbacks or a working-directory override.
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> CommandRunner.Result {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: nil,
            onStdoutLine: nil,
            onStderrLine: nil
        )
    }
}

/// Production runner: thin pass-through to `CommandRunner.run`.
struct LiveYNHCommandRunner: YNHCommandRunner {
    // swiftlint:disable:next function_parameter_count
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: String?,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws -> CommandRunner.Result {
        try await CommandRunner.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            onStdoutLine: onStdoutLine,
            onStderrLine: onStderrLine
        )
    }
}
