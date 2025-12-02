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
struct SourceCodeIntegration {
    private let originURLPattern = #"\[remote "origin"\][^\[]*?url\s*=\s*([^\n\r]+)"#

    /// Creates build commands with collected git information.
    ///
    /// - Parameters:
    ///   - path: The directory path to search for git information
    ///   - outputDirectory: The directory where output files should be created
    /// - Returns: Array of build commands configured with repository URL and commit SHA
    /// - Throws: If command generation fails or git information cannot be collected
    func command(from path: PackagePlugin.Path, outputDirectory: PackagePlugin.Path) throws -> [Command] {
        // Try environment variables first
        if
            let repo = ProcessInfo.processInfo.environment["DD_GIT_REPOSITORY_URL"],
            let commit = ProcessInfo.processInfo.environment["DD_GIT_COMMIT_SHA"]
        {
            return try commands(repo: repo, commit: commit, outputDirectory: outputDirectory)
        }

        // Else, try reading from .git
        if
            let repo = try repositoryURL(from: path),
            let commit = try commitSHA(from: path)
        {
            return try commands(repo: repo, commit: commit, outputDirectory: outputDirectory)
        }

        Diagnostics.warning("""
            DatadogSCI: No git context found. Either:
            1. Set DD_GIT_REPOSITORY_URL and DD_GIT_COMMIT_SHA environment variables, or
            2. Ensure the project is in a git repository with a remote origin configured
            """
        )

        return []
    }

    /// Generates build commands to create DatadogSCI.plist with git information.
    ///
    /// Creates a new plist file with repository URL and commit SHA using three separate commands.
    ///
    /// - Parameters:
    ///   - repo: The git repository URL
    ///   - commit: The git commit SHA
    ///   - outputDirectory: The directory where the plist should be created
    /// - Returns: Array of build commands to create DatadogSCI.plist
    /// - Throws: If command creation fails
    func commands(repo: String, commit: String, outputDirectory: PackagePlugin.Path) throws -> [Command]  {
        Diagnostics.remark("""
            DatadogSCI: 
                Repository: \(repo)
                Commit: \(commit)
            """)

        let outputFile = outputDirectory.appending("DatadogSCI.plist")

        return [
            .buildCommand(
                displayName: "Initialize DatadogSCI.plist",
                executable: Path("/usr/libexec/PlistBuddy"),
                arguments: ["-c", "Clear dict", outputFile.string],
                outputFiles: [outputFile]
            ),
            .buildCommand(
                displayName: "Add Repository URL",
                executable: Path("/usr/libexec/PlistBuddy"),
                arguments: ["-c", "Add :RepositoryURL string \(repo)", outputFile.string]
            ),
            .buildCommand(
                displayName: "Add Commit SHA",
                executable: Path("/usr/libexec/PlistBuddy"),
                arguments: ["-c", "Add :CommitSHA string \(commit)", outputFile.string]
            )
        ]
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

        guard let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        // Case 1: Detached HEAD (direct SHA)
        if !content.hasPrefix("ref:") {
            return content
        }

        // Case 2: Branch reference
        let ref = content.dropFirst(4).trimmingCharacters(in: .whitespaces)
        let refURL = URL(fileURLWithPath: path.appending(".git/\(ref)").string)
        let refData = try Data(contentsOf: refURL)

        guard let sha = String(data: refData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return sha
    }
}

extension SourceCodeIntegration: BuildToolPlugin {
    /// Creates build commands for SPM builds.
    ///
    /// This method is invoked by SwiftPM when building packages from the command line.
    /// It attempts to collect git information from environment variables only, as
    /// `context.package.directory` points to the dd-sdk-ios package, not the consuming app.
    ///
    /// - Parameters:
    ///   - context: Plugin context containing package and build information
    ///   - target: The target being built
    /// - Returns: Array of build commands to create DatadogSCI.plist, or empty array on failure
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        do {
            return try command(from: context.package.directory, outputDirectory: context.pluginWorkDirectory)
        } catch {
            Diagnostics.warning("DatadogSCI: Failed to collect git information - \(error.localizedDescription)")
            return []
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SourceCodeIntegration: XcodeBuildToolPlugin {
    /// Creates build commands for Xcode builds.
    ///
    /// This method is invoked by Xcode when building projects that depend on DatadogCore.
    /// It has access to `context.xcodeProject.directory` which points to the consuming app's
    /// project directory, enabling git information collection from `.git` files.
    ///
    /// - Parameters:
    ///   - context: Xcode plugin context containing project and build information
    ///   - target: The Xcode target being built
    /// - Returns: Array of build commands to create DatadogSCI.plist, or empty array on failure
    /// - Throws: Does not throw; catches errors and returns empty array with warning
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        do {
            return try command(from: context.xcodeProject.directory, outputDirectory: context.pluginWorkDirectory)
        } catch {
            Diagnostics.warning("DatadogSCI: Failed to collect git information - \(error.localizedDescription)")
            return []
        }
    }
}
#endif
