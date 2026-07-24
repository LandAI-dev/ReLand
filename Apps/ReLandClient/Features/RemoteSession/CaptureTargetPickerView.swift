import ReLandCore
import SwiftUI

struct CaptureTargetPickerView: View {
    @Bindable var model: ClientAppModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let displays = model.captureTargets.filter {
                    $0.kind == .display
                }
                let windows = model.captureTargets.filter {
                    $0.kind == .window
                }

                if !displays.isEmpty {
                    Section("Displays") {
                        ForEach(displays) { target in
                            targetButton(target)
                        }
                    }
                }

                Section("Open app windows") {
                    if windows.isEmpty {
                        ContentUnavailableView(
                            "No app windows",
                            systemImage: "macwindow",
                            description: Text(
                                "Open a Mac app window, then refresh."
                            )
                        )
                    } else {
                        ForEach(windows) { target in
                            targetButton(target)
                        }
                    }
                }
            }
            .navigationTitle("Mac Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.requestCaptureTargets()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier(
                        "refreshCaptureTargetsButton"
                    )
                }
            }
        }
        .task {
            model.requestCaptureTargets()
        }
    }

    private func targetButton(
        _ target: RemoteCaptureTargetInfo
    ) -> some View {
        Button {
            model.selectCaptureTarget(target)
        } label: {
            HStack(spacing: 14) {
                Image(
                    systemName:
                        target.kind == .window
                        ? "macwindow"
                        : "display"
                )
                .font(.title2)
                .foregroundStyle(ReLandTheme.accent)
                .frame(width: 44, height: 44)
                .background(
                    ReLandTheme.controlBackground,
                    in: RoundedRectangle(cornerRadius: 12)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.title)
                        .font(.headline)
                        .foregroundStyle(ReLandTheme.strongText)
                        .lineLimit(2)
                    Text(
                        target.applicationName
                            + " · \(target.width)×\(target.height)"
                    )
                    .font(.caption)
                    .foregroundStyle(ReLandTheme.mutedText)
                }

                Spacer()
                if model.selectedCaptureTarget?.id == target.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ReLandTheme.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ReLandTheme.mutedText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "captureTarget-\(target.id)"
        )
    }
}
