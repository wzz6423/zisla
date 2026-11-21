import Foundation
import ZislaCore

struct ApplicationInstallationCleanup {
    private static let maximumPlistBytes = 1_048_576
    let fileManager: SystemMonitorFileManaging

    private struct Application {
        let url: URL
        let identifier: String
        let version: String?
        let build: String?
        let name: String
    }

    func candidates() -> [DiskCleanupCandidate] {
        guard let executables = fileManager.applicationExecutablePaths() else { return [] }
        let runningPaths = Set(executables.filter { $0.hasPrefix("/") }.map {
            SystemMonitorPathSafety.standardizedPath(URL(fileURLWithPath: $0))
        })
        let home = fileManager.homeDirectoryForCurrentUser()
        let installationRoots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
        let userRoots = [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory]
            .flatMap { fileManager.urls(for: $0, in: .userDomainMask) }
            .filter { SystemMonitorPathSafety.isURL($0, withinAllowedRoots: [home]) }
        var applications: [Application] = []
        var visited = Set<String>()
        for root in installationRoots + userRoots {
            collectApplications(at: root, remainingDepth: 3, visited: &visited, applications: &applications)
        }

        var result: [DiskCleanupCandidate] = []
        for group in Dictionary(grouping: applications, by: \.identifier).values where group.count > 1 {
            guard group.allSatisfy({ $0.version != nil }) else { continue }
            let comparesBuilds = group.allSatisfy { $0.build != nil }
            let ordered = group.sorted { lhs, rhs in
                let versionOrder = lhs.version!.compare(rhs.version!, options: .numeric)
                if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
                if comparesBuilds {
                    let buildOrder = lhs.build!.compare(rhs.build!, options: .numeric)
                    if buildOrder != .orderedSame { return buildOrder == .orderedDescending }
                }
                let leftRunning = isRunning(lhs.url, paths: runningPaths)
                let rightRunning = isRunning(rhs.url, paths: runningPaths)
                if leftRunning != rightRunning { return leftRunning }
                let leftInstalled = SystemMonitorPathSafety.isURL(lhs.url, withinAllowedRoots: installationRoots)
                let rightInstalled = SystemMonitorPathSafety.isURL(rhs.url, withinAllowedRoots: installationRoots)
                if leftInstalled != rightInstalled { return leftInstalled }
                let leftCanonical = lhs.url.deletingPathExtension().lastPathComponent == lhs.name
                let rightCanonical = rhs.url.deletingPathExtension().lastPathComponent == rhs.name
                if leftCanonical != rightCanonical { return leftCanonical }
                return lhs.url.path < rhs.url.path
            }
            let keeper = ordered[0]
            for app in ordered.dropFirst() where !isRunning(app.url, paths: runningPaths) {
                let size = SystemDiskCleanup.allocatedByteSize(of: app.url, fileManager: fileManager)
                guard size > 0 else { continue }
                result.append(DiskCleanupCandidate(
                    url: app.url, kind: .applicationResidual, byteSize: size,
                    displayName: app.url.lastPathComponent,
                    detail: AppLocalization.text("重复安装 · 版本 %@ · %@ · 保留：%@", app.version!, app.url.path, keeper.url.path),
                    source: app.identifier
                ))
            }
        }
        let duplicateURLs = Set(result.map(\.url))
        for app in applications where !duplicateURLs.contains(app.url) {
            var versionRoots = [app.url.appendingPathComponent("Contents/Versions")]
            let frameworks = app.url.appendingPathComponent("Contents/Frameworks")
            for framework in children(of: frameworks) where framework.pathExtension.lowercased() == "framework" && isDirectory(framework) {
                versionRoots.append(framework.appendingPathComponent("Versions"))
            }
            for versions in versionRoots {
                result.append(contentsOf: updateResiduals(in: versions, application: app, runningPaths: runningPaths))
            }
        }
        return result
    }

    private func collectApplications(
        at root: URL,
        remainingDepth: Int,
        visited: inout Set<String>,
        applications: inout [Application]
    ) {
        guard remainingDepth > 0, isDirectory(root), visited.insert(root.standardizedFileURL.path).inserted else { return }
        for child in children(of: root) {
            guard isDirectory(child),
                  SystemMonitorPathSafety.isURL(child, withinAllowedRoots: [root]) else { continue }
            if child.pathExtension.lowercased() == "app" {
                if let app = application(at: child) { applications.append(app) }
            } else {
                collectApplications(at: child, remainingDepth: remainingDepth - 1, visited: &visited, applications: &applications)
            }
        }
    }

    private func application(at url: URL) -> Application? {
        guard isDirectory(url.appendingPathComponent("Contents")),
              isDirectory(url.appendingPathComponent("Contents/MacOS")),
              let info = plist(at: url.appendingPathComponent("Contents/Info.plist")),
              info["CFBundlePackageType"] as? String == "APPL",
              let identifier = info["CFBundleIdentifier"] as? String, !identifier.isEmpty,
              !identifier.lowercased().hasPrefix("com.apple."),
              let executable = info["CFBundleExecutable"] as? String,
              (try? fileManager.attributesOfItem(atPath: url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path)[.type]) as? FileAttributeType == .typeRegular
        else { return nil }
        return Application(
            url: url.standardizedFileURL, identifier: identifier.lowercased(),
            version: numericVersion(info["CFBundleShortVersionString"] as? String),
            build: numericVersion(info["CFBundleVersion"] as? String),
            name: info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        )
    }

    private func updateResiduals(in versions: URL, application app: Application, runningPaths: Set<String>) -> [DiskCleanupCandidate] {
        guard isDirectory(versions), SystemMonitorPathSafety.isURL(versions, withinAllowedRoots: [app.url]) else { return [] }
        let current = versions.appendingPathComponent("Current")
        let active: URL
        if (try? fileManager.attributesOfItem(atPath: current.path)) != nil {
            active = current.resolvingSymlinksInPath().standardizedFileURL
        } else if versions == app.url.appendingPathComponent("Contents/Versions"), let version = app.version {
            active = versions.appendingPathComponent(version).standardizedFileURL
        } else {
            return []
        }
        guard active.deletingLastPathComponent() == versions.standardizedFileURL,
              isDirectory(active), let activeVersion = numericVersion(active.lastPathComponent) else { return [] }
        if versions.deletingLastPathComponent().pathExtension.lowercased() == "framework" {
            guard let info = plist(at: active.appendingPathComponent("Resources/Info.plist")),
                  numericVersion(info["CFBundleShortVersionString"] as? String) == activeVersion else { return [] }
        } else {
            guard app.version == activeVersion else { return [] }
        }
        let contents = app.url.appendingPathComponent("Contents")
        let seal = contents.appendingPathComponent("_CodeSignature/CodeResources")
        var sealedPaths: [String] = []
        if fileManager.fileExists(atPath: seal.path) {
            guard let info = plist(at: seal) else { return [] }
            for key in ["files", "files2"] {
                guard let files = info[key] as? [String: Any] else { continue }
                sealedPaths.append(contentsOf: files.keys.map { contents.appendingPathComponent($0).standardizedFileURL.path })
            }
        }
        return children(of: versions).compactMap { version in
            guard isDirectory(version), let number = numericVersion(version.lastPathComponent),
                  number.compare(activeVersion, options: .numeric) == .orderedAscending,
                  !isRunning(version, paths: runningPaths),
                  version.deletingLastPathComponent().standardizedFileURL == versions.standardizedFileURL,
                  !sealedPaths.contains(where: { $0 == version.path || $0.hasPrefix(version.path + "/") }) else { return nil }
            let size = SystemDiskCleanup.allocatedByteSize(of: version, fileManager: fileManager)
            guard size > 0 else { return nil }
            return DiskCleanupCandidate(
                url: version.standardizedFileURL, kind: .applicationResidual, byteSize: size,
                displayName: "\(app.url.lastPathComponent) · \(number)",
                detail: AppLocalization.text("更新残留 · 旧版本 %@ · %@ · 当前版本：%@", number, version.path, activeVersion),
                source: app.identifier
            )
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeDirectory
    }

    private func children(of url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
    }

    private func plist(at url: URL) -> [String: Any]? {
        guard (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular,
              let data = fileManager.readPrefix(at: url, maximumBytes: Self.maximumPlistBytes) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private func numericVersion(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 128,
              value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
              }) else { return nil }
        return value
    }

    private func isRunning(_ url: URL, paths: Set<String>) -> Bool {
        let path = SystemMonitorPathSafety.standardizedPath(url)
        return paths.contains { $0 == path || $0.hasPrefix(path + "/") }
    }
}
