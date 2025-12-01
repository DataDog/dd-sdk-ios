import PackagePlugin
import Foundation

/// Build tool plugin that collects git repository information (URL and commit SHA) for source code integration.
///
/// This plugin supports two collection strategies:
/// 1. Environment variables: `DD_GIT_REPOSITORY_URL` and `DD_GIT_COMMIT_SHA` (works in all contexts)
/// 2. Local `.git` files: Reads from `.git/config` and `.git/HEAD` (Xcode builds only)
///
/// The plugin implements both `BuildToolPlugin` and `XcodeBuildToolPlugin` to support different build environments.
@main
struct SourceCodeIntegrationPlugin {
    private let originURLPattern = #"\[remote "origin"\][^\[]*?url\s*=\s*(.+)"#

    /// Creates build commands with collected git information.
    ///
    /// - Parameter path: The directory path to search for git information
    /// - Returns: Array of build commands configured with repository URL and commit SHA
    /// - Throws: If command generation fails or git information cannot be collected
    func command(from path: PackagePlugin.Path) throws -> [Command] {
        // Try environment variables first
        if
            let repo = ProcessInfo.processInfo.environment["DD_GIT_REPOSITORY_URL"],
            let commit = ProcessInfo.processInfo.environment["DD_GIT_COMMIT_SHA"]
        {
            return try [command(repo: repo, commit: commit)]
        }

        print("[SourceCodeIntegrationPlugin] path:", path)

        // Else, try reading from .git
        if
            let repo = try repositoryURL(from: path),
            let commit = try commitSHA(from: path)
        {
            return try [command(repo: repo, commit: commit)]
        }

        return []
    }

    /// Generates a build command using the provided git repository information.
    ///
    /// - Parameters:
    ///   - repo: The git repository URL
    ///   - commit: The git commit SHA
    /// - Returns: A configured build command
    /// - Throws: If command creation fails
    func command(repo: String, commit: String) throws -> Command  {
        print("📦 DatadogSCI: Repository: \(repo)")
        print("📦 DatadogSCI: Commit: \(commit)")
        throw PluginDeserializationError.internalError("Not implemented")
    }

    /// Reads the repository URL from `.git/config` file.
    ///
    /// Parses the git config file using regex to extract the URL from the `[remote "origin"]` section.
    /// Falls back to `nil` if the file doesn't exist or doesn't contain an origin remote.
    ///
    /// - Parameter path: The root directory containing `.git` folder
    /// - Returns: The remote origin URL if found, `nil` otherwise
    /// - Throws: If regex compilation fails
    private func repositoryURL(from path: PackagePlugin.Path) throws -> String? {
        let url = URL(fileURLWithPath: path.appending(".git/config").string)
        let data = try Data(contentsOf: url)

        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        print("[SourceCodeIntegrationPlugin] config:", content)

        let regex = try NSRegularExpression(pattern: originURLPattern, options: [.dotMatchesLineSeparators])
        guard
            let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
            let range = Range(match.range(at: 1), in: content)
        else {
            return nil
        }

        return String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads the commit SHA from `.git/HEAD` file.
    ///
    /// Handles two cases:
    /// 1. Detached HEAD: Returns the SHA directly from `.git/HEAD`
    /// 2. Branch reference: Follows the ref path (e.g., `refs/heads/main`) to read the SHA
    ///
    /// - Parameter path: The root directory containing `.git` folder
    /// - Returns: The commit SHA if found, `nil` otherwise
    /// - Throws: If file reading fails
    private func commitSHA(from path: PackagePlugin.Path) throws -> String? {
        let url = URL(fileURLWithPath: path.appending(".git/HEAD").string)
        let data = try Data(contentsOf: url)

        guard
            let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        print("[SourceCodeIntegrationPlugin] HEAD:", content)

        // Case 1: Detached HEAD (direct SHA)
        if !content.hasPrefix("ref:") {
            return content
        }

        // Case 2: Branch reference
        let ref = content.dropFirst(4).trimmingCharacters(in: .whitespaces)
        let refURL = URL(fileURLWithPath: path.appending(".git/\(ref)").string)
        let refData = try Data(contentsOf: refURL)

        guard
            let sha = String(data: refData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        return sha
    }
}

extension SourceCodeIntegrationPlugin: BuildToolPlugin {
    /// Invoked by SwiftPM to create build commands for a particular target.
    /// The context parameter contains information about the package and its
    /// dependencies, as well as other environmental inputs.
    ///
    /// This function should create and return build commands or prebuild
    /// commands, configured based on the information in the context. Note
    /// that it does not directly run those commands.
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        return try command(from: context.package.directory)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SourceCodeIntegrationPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        // For Xcode builds, we have access to the project directory
        return try command(from: context.xcodeProject.directory)
    }
}
#endif
