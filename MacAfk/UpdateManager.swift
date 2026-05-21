import Foundation
import SwiftUI
import Combine
import os

/// GitHub Release 信息
struct GitHubRelease: Codable, Equatable {
    let tagName: String
    let name: String
    let body: String?
    let htmlUrl: String
    let assets: [GitHubAsset]
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
        case publishedAt = "published_at"
    }
}

struct GitHubAsset: Codable, Equatable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(GitHubRelease)
    case upToDate
    case downloading(Double)
    case installing
    case error(String)

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.checking, .checking),
             (.upToDate, .upToDate),
             (.installing, .installing):
            return true
        case (.available(let lRelease), .available(let rRelease)):
            return lRelease.tagName == rRelease.tagName
        case (.downloading(let lProgress), .downloading(let rProgress)):
            return lProgress == rProgress
        case (.error(let lMsg), .error(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var updateStatus: UpdateStatus = .idle
    @Published var showUpdateAlert = false

    private let githubOwner = "jiayuqi7813"
    private let githubRepo = "macAFK-Pro"
    private let currentVersion: String

    private lazy var urlSession: URLSession = {
        URLSession(configuration: .default)
    }()

    private lazy var downloadSession: URLSession = {
        URLSession(configuration: .default, delegate: DownloadDelegate(updateManager: self), delegateQueue: nil)
    }()

    private var downloadTask: URLSessionDownloadTask?

    init() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = version
        } else {
            self.currentVersion = "1.0.0"
        }
    }

    func checkForUpdates(silent: Bool = false) {
        updateStatus = .checking

        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            updateStatus = .error("update.error.invalid_url".localized)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    self.updateStatus = .error("update.error.network".localized + ": \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    self.updateStatus = .error("update.error.no_data".localized)
                    return
                }

                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

                    if self.isNewerVersion(release.tagName, than: self.currentVersion) {
                        self.updateStatus = .available(release)
                        self.showUpdateAlert = true
                        NotificationCenter.default.post(name: .updateStatusChanged, object: nil)
                    } else {
                        self.updateStatus = .upToDate
                        if !silent {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                self.updateStatus = .idle
                            }
                        }
                    }
                } catch {
                    self.updateStatus = .error("update.error.parse".localized + ": \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    func downloadAndInstall(release: GitHubRelease) {
        let architecture = getCurrentArchitecture()

        guard let asset = selectAsset(from: release.assets, for: architecture) else {
            updateStatus = .error("update.error.no_compatible_asset".localized)
            return
        }

        guard let url = URL(string: asset.browserDownloadUrl) else {
            updateStatus = .error("update.error.invalid_download_url".localized)
            return
        }

        updateStatus = .downloading(0)
        downloadTask = downloadSession.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        updateStatus = .idle
    }

    func openGitHubRelease(url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    private func isNewerVersion(_ newVersion: String, than currentVersion: String) -> Bool {
        let new = newVersion.replacingOccurrences(of: "v", with: "").split(separator: ".").compactMap { Int($0) }
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(new.count, current.count) {
            let newPart = i < new.count ? new[i] : 0
            let currentPart = i < current.count ? current[i] : 0

            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }

        return false
    }

    private func getCurrentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "universal"
        #endif
    }

    private func selectAsset(from assets: [GitHubAsset], for architecture: String) -> GitHubAsset? {
        if let asset = assets.first(where: { $0.name.contains(architecture) && $0.name.hasSuffix(".dmg") }) {
            return asset
        }

        if let asset = assets.first(where: { $0.name.contains("Universal") && $0.name.hasSuffix(".dmg") }) {
            return asset
        }

        return assets.first(where: { $0.name.hasSuffix(".dmg") })
    }

    fileprivate func installDMG(at localURL: URL) {
        updateStatus = .installing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try AppUpdateInstaller.installFromDMG(at: localURL)
                DispatchQueue.main.async {
                    debugLog("Update staged, terminating for in-place install", logger: AppLog.updates)
                    NSApp.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.updateStatus = .error(error.localizedDescription)
                    AppLog.updates.error("In-place update failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var updateManager: UpdateManager?

    init(updateManager: UpdateManager) {
        self.updateManager = updateManager
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let downloadsURL = fileManager.temporaryDirectory
        let fileName = downloadTask.response?.suggestedFilename ?? "MacAfk-Pro.dmg"
        let destinationURL = downloadsURL.appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.updateManager?.installDMG(at: destinationURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.updateManager?.updateStatus = .error("update.error.save_file".localized + ": \(error.localizedDescription)")
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        DispatchQueue.main.async {
            self.updateManager?.updateStatus = .downloading(progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.updateManager?.updateStatus = .error("update.error.download".localized + ": \(error.localizedDescription)")
            }
        }
    }
}
