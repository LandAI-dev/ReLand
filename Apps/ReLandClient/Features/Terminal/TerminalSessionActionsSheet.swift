import ReLandCore
import SwiftUI

@MainActor
struct TerminalSessionActionsSheet: View {
    @Bindable var model: ClientAppModel
    let initialSession: TerminalSessionInfo

    @Environment(\.dismiss) private var dismiss

    @State private var isArtifactsPresented = false
    @State private var isMacFilesPresented = false
    @State private var isRenamePresented = false
    @State private var isStopConfirmationPresented = false

    private var session: TerminalSessionInfo {
        model.terminalSessions.first {
            $0.id == initialSession.id
        } ?? initialSession
    }

    private var actionsEnabled: Bool {
        model.canPerformTerminalActions
    }

    var body: some View {
        NavigationStack {
            List {
                if !actionsEnabled {
                    Section {
                        Label(
                            "Reconnect to use terminal actions.",
                            systemImage: "wifi.exclamationmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Open") {
                    actionButton(
                        title: "Open Terminal",
                        detail: "Attach and continue this session",
                        systemImage: "terminal"
                    ) {
                        if model.attachTerminal(session) {
                            dismiss()
                        }
                    }
                    .disabled(!actionsEnabled)
                    .accessibilityIdentifier(
                        "terminalActionOpenButton"
                    )

                    actionButton(
                        title: "Open on Mac",
                        detail: "Attach in Terminal.app",
                        systemImage: "macwindow.on.rectangle"
                    ) {
                        if model.openTerminalOnMac(session) {
                            dismiss()
                        }
                    }
                    .disabled(!actionsEnabled)
                    .accessibilityIdentifier(
                        "terminalActionOpenOnMacButton"
                    )
                }

                Section("Files") {
                    actionButton(
                        title: "Session Files",
                        detail: "Artifacts saved by terminal tools",
                        systemImage: "folder"
                    ) {
                        model.prepareTerminalArtifacts(
                            sessionID: session.id
                        )
                        isArtifactsPresented = true
                    }
                    .disabled(!actionsEnabled)
                    .accessibilityIdentifier(
                        "terminalActionSessionFilesButton"
                    )

                    actionButton(
                        title: "Mac Files",
                        detail: "Browse approved read-only folders",
                        systemImage: "externaldrive"
                    ) {
                        if model.requestRemoteFiles(path: "") {
                            isMacFilesPresented = true
                        }
                    }
                    .disabled(!actionsEnabled)
                    .accessibilityIdentifier(
                        "terminalActionMacFilesButton"
                    )
                }

                Section("Manage") {
                    if model.supportsTerminalRename {
                        actionButton(
                            title: "Rename",
                            detail: "Change the display name only",
                            systemImage: "pencil"
                        ) {
                            isRenamePresented = true
                        }
                        .disabled(!actionsEnabled)
                        .accessibilityIdentifier(
                            "terminalActionRenameButton"
                        )
                    }

                    actionButton(
                        title: "Stop Terminal",
                        detail: "End the session; keep its files",
                        systemImage: "stop.circle",
                        tint: .red,
                        showsDisclosure: false
                    ) {
                        isStopConfirmationPresented = true
                    }
                    .disabled(!actionsEnabled)
                    .accessibilityIdentifier(
                        "terminalActionStopButton"
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(ReLandTheme.canvas)
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                ReLandTheme.canvas,
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ReLandTheme.canvas)
        .sheet(isPresented: $isRenamePresented) {
            TerminalRenameView(
                model: model,
                session: session
            )
        }
        .sheet(isPresented: $isArtifactsPresented) {
            TerminalArtifactsView(
                model: model,
                session: session
            )
        }
        .sheet(isPresented: $isMacFilesPresented) {
            RemoteFilesView(model: model)
        }
        .confirmationDialog(
            "Stop \(session.name)?",
            isPresented: $isStopConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Stop Terminal", role: .destructive) {
                if model.killTerminal(session) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The tmux session will end. Its ReLand session files "
                    + "will remain on the Mac."
            )
        }
    }

    private func actionButton(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color = .accentColor,
        showsDisclosure: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            tint == .red ? .red : .primary
                        )
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct TerminalRenameView: View {
    @Bindable var model: ClientAppModel
    let session: TerminalSessionInfo

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String

    init(
        model: ClientAppModel,
        session: TerminalSessionInfo
    ) {
        self.model = model
        self.session = session
        _name = State(initialValue: session.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && trimmedName.count
                <= ReLandConstants.maximumTerminalNameLength
            && trimmedName != session.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Terminal name", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier(
                            "terminalNameField"
                        )
                } footer: {
                    Text(
                        "\(name.count)/"
                            + "\(ReLandConstants.maximumTerminalNameLength)"
                            + " characters. The stable session ID and "
                            + "files do not change."
                    )
                }
            }
            .navigationTitle("Rename Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier(
                        "saveTerminalNameButton"
                    )
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isNameFocused = true
        }
    }

    private func save() {
        guard canSave else {
            return
        }
        model.renameTerminal(session, name: trimmedName)
        dismiss()
    }
}
