import ReLandCore
import SwiftUI

struct RemoteFilesView: View {
    @Bindable var model: ClientAppModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingRemoteFiles,
                   model.remoteFiles.isEmpty
                {
                    ProgressView("Loading Mac files")
                } else {
                    List {
                        if model.remoteFilePath.isEmpty {
                            Section {
                                Label(
                                    "Read-only access to ReLand storage "
                                        + "and folders approved on the Mac. "
                                        + "Hidden files and symlinks are not shown.",
                                    systemImage: "lock.shield"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            if model.remoteFiles.isEmpty {
                                ContentUnavailableView(
                                    "Empty folder",
                                    systemImage: "folder",
                                    description: Text(
                                        "This Mac folder has no visible files."
                                    )
                                )
                            } else {
                                ForEach(model.remoteFiles) { entry in
                                    Button {
                                        model.openRemoteFile(entry)
                                    } label: {
                                        RemoteFileRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier(
                                        "remoteFile-\(entry.id)"
                                    )
                                }
                            }
                        } header: {
                            Text(displayedPath)
                                .textCase(nil)
                        }
                    }
                    .refreshable {
                        model.requestRemoteFiles(
                            path: model.remoteFilePath
                        )
                    }
                }
            }
            .navigationTitle(folderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        model.closeRemoteFileBrowser()
                        dismiss()
                    }
                }
                if model.remoteFileParentPath != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            model.navigateToParentRemoteFolder()
                        } label: {
                            Label(
                                "Parent folder",
                                systemImage: "arrow.up"
                            )
                        }
                        .accessibilityIdentifier(
                            "remoteFileParentButton"
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.requestRemoteFiles(
                            path: model.remoteFilePath
                        )
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingRemoteFiles)
                    .accessibilityIdentifier(
                        "refreshRemoteFilesButton"
                    )
                }
            }
            .overlay {
                if let progress = model.remoteFileDownloadProgress {
                    VStack(spacing: 12) {
                        ProgressView(value: progress)
                            .frame(width: 180)
                        Text(
                            progress,
                            format: .percent.precision(
                                .fractionLength(0)
                            )
                        )
                        .font(.caption.monospacedDigit())
                    }
                    .padding(20)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Downloading Mac file")
                    .accessibilityValue(
                        Text(progress, format: .percent)
                    )
                }
            }
        }
        .task {
            if model.remoteFiles.isEmpty {
                model.requestRemoteFiles(path: model.remoteFilePath)
            }
        }
        .sheet(item: $model.remoteFilePreview) { preview in
            RemoteQuickLookSheet(
                title: preview.entry.name,
                fileURL: preview.fileURL,
                dismiss: {
                    model.remoteFilePreview = nil
                }
            )
        }
    }

    private var folderTitle: String {
        guard !model.remoteFilePath.isEmpty else {
            return "Mac Files"
        }
        let components = model.remoteFilePath.split(
            separator: "/"
        )
        if components.count == 1 {
            return model.remoteFileRootNames[
                model.remoteFilePath
            ] ?? "Mac Files"
        }
        return String(components.last ?? "Mac Files")
    }

    private var displayedPath: String {
        guard !model.remoteFilePath.isEmpty else {
            return "Locations"
        }
        let components = model.remoteFilePath.split(
            separator: "/"
        )
        let rootKey = components.first.map(String.init) ?? ""
        let rootName = model.remoteFileRootNames[rootKey]
            ?? "Mac Files"
        let relative = components.dropFirst()
            .joined(separator: "/")
        return relative.isEmpty
            ? rootName
            : "\(rootName)/\(relative)"
    }
}

private struct RemoteFileRow: View {
    let entry: RemoteFileEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(
                    .tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            entry.kind == .directory
                ? "Opens this Mac folder"
                : "Downloads and previews this Mac file"
        )
    }

    private var detail: String {
        if
            entry.kind == .directory,
            entry.path.hasPrefix("@"),
            !entry.path.contains("/")
        {
            return "Approved read-only location"
        }
        if let byteCount = entry.byteCount {
            return ByteCountFormatter.string(
                fromByteCount: byteCount,
                countStyle: .file
            )
                + " · "
                + entry.modifiedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
        }
        return entry.modifiedAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private var symbolName: String {
        switch entry.kind {
        case .directory:
            "folder"
        case .image:
            "photo"
        case .video:
            "video"
        case .text:
            "doc.text"
        case .other:
            "doc"
        }
    }
}
