import SwiftUI

// swiftui-navigation: sheet + NavigationStack；swiftui-layout-components: Form + ContentUnavailableView
extension GitHubRelease: Identifiable {
    var id: String { tagName }
}

struct UpdateAlertView: View {
    @ObservedObject var updateManager: UpdateManager
    let release: GitHubRelease
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("update.available.title".localized, value: release.tagName)
                }

                Section("update.release_notes".localized) {
                    if let body = release.body, !body.isEmpty {
                        Text(body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        ContentUnavailableView(
                            "update.release_notes".localized,
                            systemImage: "doc.text",
                            description: Text("update.up_to_date".localized)
                        )
                    }
                }

                downloadStatusSection
            }
            .formStyle(.grouped)
            .navigationTitle("update.available.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        updateManager.openGitHubRelease(url: release.htmlUrl)
                    } label: {
                        Label("update.open_github".localized, systemImage: "link")
                    }

                    primaryDownloadButton
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    @ViewBuilder
    private var downloadStatusSection: some View {
        if case .downloading(let progress) = updateManager.updateStatus {
            Section("update.downloading".localized) {
                ProgressView(value: progress)
                LabeledContent {
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } label: {
                    EmptyView()
                }
            }
        }

        if case .error(let message) = updateManager.updateStatus {
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var primaryDownloadButton: some View {
        if case .downloading = updateManager.updateStatus {
            Button {
                updateManager.cancelDownload()
            } label: {
                Text("update.cancel_download".localized)
            }
            .tint(.red)
        } else if case .error = updateManager.updateStatus {
            Button {
                updateManager.downloadAndInstall(release: release)
            } label: {
                Label("update.retry".localized, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                updateManager.downloadAndInstall(release: release)
            } label: {
                Label("update.download_install".localized, systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
