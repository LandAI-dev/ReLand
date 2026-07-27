import ReLandCore
import SwiftUI

struct TerminalArtifactsView: View {
    @Bindable var model: ClientAppModel
    let session: TerminalSessionInfo

    @Environment(\.dismiss) private var dismiss

    private var artifacts: [TerminalArtifactInfo] {
        model.terminalArtifactSessionID == session.id
            ? model.terminalArtifacts
            : []
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingTerminalArtifacts,
                   artifacts.isEmpty
                {
                    ProgressView("Loading artifacts")
                } else if artifacts.isEmpty {
                    ContentUnavailableView {
                        Label("No artifacts", systemImage: "folder")
                    } description: {
                        Text(
                            "Tell your AI tool to save files in this "
                                + "session's ReLand Artifacts folder."
                        )
                    } actions: {
                        if
                            model.attachedTerminalSessionID
                                == session.id
                        {
                            Button("Send to AI") {
                                model.sendArtifactStorageInstruction()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier(
                                "sendArtifactInstructionButton"
                            )
                        }

                        Button("Copy prompt") {
                            model.copyArtifactStorageInstruction()
                        }
                        .accessibilityIdentifier(
                            "copyArtifactInstructionButton"
                        )
                    }
                } else {
                    List(artifacts) { artifact in
                        Button {
                            model.downloadTerminalArtifact(artifact)
                        } label: {
                            TerminalArtifactRow(artifact: artifact)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "terminalArtifact-\(artifact.id)"
                        )
                    }
                    .refreshable {
                        model.requestTerminalArtifacts(
                            sessionID: session.id
                        )
                    }
                }
            }
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.requestTerminalArtifacts(
                            sessionID: session.id
                        )
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingTerminalArtifacts)
                    .accessibilityIdentifier(
                        "refreshTerminalArtifactsButton"
                    )
                }
            }
            .overlay {
                if let progress =
                    model.terminalArtifactDownloadProgress
                {
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
                    .accessibilityLabel("Downloading artifact")
                    .accessibilityValue(
                        Text(progress, format: .percent)
                    )
                }
            }
        }
        .task {
            model.requestTerminalArtifacts(sessionID: session.id)
        }
        .sheet(item: $model.terminalArtifactPreview) { preview in
            RemoteQuickLookSheet(
                title: preview.info.name,
                fileURL: preview.fileURL,
                dismiss: {
                    model.terminalArtifactPreview = nil
                }
            )
        }
    }
}

private struct TerminalArtifactRow: View {
    let artifact: TerminalArtifactInfo

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
                Text(artifact.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(
                    ByteCountFormatter.string(
                        fromByteCount: artifact.byteCount,
                        countStyle: .file
                    )
                        + " · "
                        + artifact.modifiedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
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
        .accessibilityHint("Downloads and previews this artifact")
    }

    private var symbolName: String {
        switch artifact.kind {
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
