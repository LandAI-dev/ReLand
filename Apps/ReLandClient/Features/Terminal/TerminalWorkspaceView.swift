import ReLandCore
import SwiftUI

@MainActor
struct TerminalWorkspaceView: View {
    @Bindable var model: ClientAppModel

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @State private var terminalController = RemoteTerminalController()
    @State private var viewportState = TerminalViewportState.initial
    @State private var usesWideColumns = true
    @State private var allowsMouseReporting = false
    @State private var isArtifactsPresented = false
    @State private var isMacFilesPresented = false
    @State private var isCreateTerminalPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if let attachedID = model.attachedTerminalSessionID,
                   let session = model.terminalSessions.first(
                       where: { $0.id == attachedID }
                   )
                {
                    attachedTerminal(session)
                } else {
                    sessionList
                }
            }
            .navigationTitle("Terminal sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        model.closeTerminalWorkspace()
                    }
                }
                if model.attachedTerminalSessionID == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isCreateTerminalPresented = true
                        } label: {
                            Label("New terminal", systemImage: "plus")
                        }
                        .accessibilityIdentifier(
                            "createTerminalButton"
                        )
                    }
                }
            }
        }
        .task {
            model.requestTerminalSessions()
        }
        .onDisappear {
            model.detachTerminal()
        }
        .sheet(isPresented: $isCreateTerminalPresented) {
            TerminalCreateView(model: model)
        }
        .alert(
            "Open external link?",
            isPresented: Binding(
                get: { model.pendingTerminalExternalURL != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelOpenTerminalLink()
                    }
                }
            ),
            presenting: model.pendingTerminalExternalURL
        ) { _ in
            Button("Cancel", role: .cancel) {
                model.cancelOpenTerminalLink()
            }
            Button("Open") {
                model.confirmOpenTerminalLink()
            }
        } message: { url in
            Text(
                "The terminal requested \(url.scheme ?? "web")://"
                    + "\(url.host ?? "unknown host")."
            )
        }
        .alert(
            "Terminal security",
            isPresented: Binding(
                get: { model.terminalSecurityNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        model.terminalSecurityNotice = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.terminalSecurityNotice = nil
            }
        } message: {
            Text(model.terminalSecurityNotice ?? "")
        }
    }

    private var sessionList: some View {
        Group {
            if model.terminalSessions.isEmpty {
                ContentUnavailableView {
                    Label("No terminals", systemImage: "terminal")
                } description: {
                    Text(
                        "Create a persistent shell that can also open "
                            + "in Terminal.app on your Mac."
                    )
                } actions: {
                    Button("Create terminal") {
                        isCreateTerminalPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(model.terminalSessions) { session in
                        HStack(spacing: 12) {
                            Button {
                                model.attachTerminal(session)
                            } label: {
                                TerminalSessionRow(session: session)
                            }
                            .buttonStyle(.plain)

                            Button {
                                model.openTerminalOnMac(session)
                            } label: {
                                Image(
                                    systemName:
                                        "macwindow.on.rectangle"
                                )
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Open \(session.name) on Mac"
                            )
                        }
                        .swipeActions {
                            Button("Stop", role: .destructive) {
                                model.killTerminal(session)
                            }
                        }
                    }
                }
                .refreshable {
                    model.requestTerminalSessions()
                }
            }
        }
    }

    private func attachedTerminal(
        _ session: TerminalSessionInfo
    ) -> some View {
        VStack(spacing: 0) {
            terminalHeader(session)

            ZStack(alignment: .bottomTrailing) {
                RemoteTerminalView(
                    model: model,
                    minimumColumns: usesWideColumns ? 80 : 0,
                    allowsMouseReporting: allowsMouseReporting,
                    controller: terminalController,
                    onViewportChange: { viewportState = $0 }
                )
                .id(session.id)

                if model.isE2EMode {
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("Remote terminal")
                        .accessibilityValue(
                            "horizontal "
                                + "\(Int(viewportState.horizontalProgress * 100)), "
                                + "vertical "
                                + "\(Int(viewportState.verticalProgress * 100))"
                        )
                        .accessibilityIdentifier("terminalView")
                }

                VStack(alignment: .trailing, spacing: 8) {
                    if viewportState.canScrollVertically,
                       !viewportState.isAtBottom
                    {
                        Button {
                            terminalController.scrollToLiveEdge()
                        } label: {
                            Label(
                                "Live",
                                systemImage:
                                    "arrow.down.to.line.compact"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityHint(
                            "Returns to the latest terminal output"
                        )
                        .accessibilityIdentifier(
                            "terminalLiveButton"
                        )
                    }

                    if viewportState.canScrollHorizontally {
                        horizontalViewportControls
                    }
                }
                .padding(12)

                if model.isE2EMode {
                    VStack(spacing: 0) {
                        Text(model.terminalOutputPreview)
                            .accessibilityLabel(
                                model.terminalOutputPreview
                            )
                            .accessibilityIdentifier(
                                "terminalOutputStatus"
                            )
                        Text(
                            "vertical "
                                + "\(Int(viewportState.verticalProgress * 100))"
                        )
                        .accessibilityIdentifier(
                            "terminalVerticalScrollStatus"
                        )
                        Text(
                            "horizontal "
                                + "\(Int(viewportState.horizontalProgress * 100))"
                        )
                        .accessibilityIdentifier(
                            "terminalHorizontalScrollStatus"
                        )
                    }
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                }
            }
            .background(.black)

            terminalAccessoryBar
        }
        .background(.black)
        .navigationBarHidden(true)
        .sheet(isPresented: $isArtifactsPresented) {
            TerminalArtifactsView(
                model: model,
                session: session
            )
        }
        .sheet(isPresented: $isMacFilesPresented) {
            RemoteFilesView(model: model)
        }
    }

    private var horizontalViewportControls: some View {
        HStack(spacing: 2) {
            Button {
                terminalController.scrollViewportLeft()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(viewportState.horizontalProgress <= 0.01)
            .accessibilityLabel("Move terminal view left")
            .accessibilityIdentifier(
                "terminalViewportLeftButton"
            )

            Text(
                "View "
                    + "\(Int(viewportState.horizontalProgress * 100))%"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 62)
            .accessibilityLabel(
                "Horizontal position "
                    + "\(Int(viewportState.horizontalProgress * 100)) percent"
            )

            Button {
                terminalController.scrollViewportRight()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(viewportState.horizontalProgress >= 0.99)
            .accessibilityLabel("Move terminal view right")
            .accessibilityIdentifier(
                "terminalViewportRightButton"
            )
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2)
        .background(ReLandTheme.terminalOverlay, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func terminalHeader(
        _ session: TerminalSessionInfo
    ) -> some View {
        HStack(spacing: 8) {
            sessionsButton(
                compact: horizontalSizeClass != .regular
            )
            terminalIdentity(session, alignment: .leading)
                .layoutPriority(1)

            Spacer(minLength: 0)

            interactionModeButton(compact: true)
            widthModeButton(compact: true)
            keyboardButton(compact: true)
            terminalOptionsMenu(session)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(ReLandTheme.chromeBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func terminalOptionsMenu(
        _ session: TerminalSessionInfo
    ) -> some View {
        Menu {
            Button {
                isArtifactsPresented = true
            } label: {
                Label("Artifacts", systemImage: "folder")
            }
            Button {
                isMacFilesPresented = true
            } label: {
                Label("Mac Files", systemImage: "externaldrive")
            }
            Button {
                model.openTerminalOnMac(session)
            } label: {
                Label(
                    "Open on Mac",
                    systemImage: "macwindow.on.rectangle"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
                .background(
                    ReLandTheme.controlBackground,
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(
                            ReLandTheme.accent.opacity(0.45),
                            lineWidth: 1
                        )
                }
        }
        .foregroundStyle(ReLandTheme.accent)
        .accessibilityLabel("Terminal options")
        .accessibilityIdentifier("terminalOptionsButton")
    }

    private func terminalIdentity(
        _ session: TerminalSessionInfo,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(session.name)
                .font(.headline)
                .lineLimit(1)

            Text(terminalGuidance)
                .font(.caption2)
                .foregroundStyle(ReLandTheme.mutedText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var terminalGuidance: String {
        if allowsMouseReporting {
            return "Touches control app"
        }
        if viewportState.usesAlternateBuffer {
            return "Swipe or use page keys"
        }
        return usesWideColumns
            ? "Swipe both ways"
            : "Swipe for history"
    }

    @ViewBuilder
    private func sessionsButton(compact: Bool) -> some View {
        if compact {
            Button {
                leaveTerminal()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(
                TerminalCompactControlStyle(
                    tint: ReLandTheme.accent
                )
            )
            .accessibilityLabel("Sessions")
            .accessibilityIdentifier("terminalSessionsButton")
        } else {
            Button {
                leaveTerminal()
            } label: {
                Label(
                    "Sessions",
                    systemImage: "chevron.left"
                )
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Sessions")
            .accessibilityIdentifier("terminalSessionsButton")
        }
    }

    private func leaveTerminal() {
        model.detachTerminal()
        model.requestTerminalSessions()
        viewportState = .initial
    }

    @ViewBuilder
    private func interactionModeButton(
        compact: Bool
    ) -> some View {
        let icon = allowsMouseReporting
            ? "cursorarrow"
            : "hand.draw"
        let tint: Color = allowsMouseReporting
            ? .orange
            : ReLandTheme.accent

        if compact {
            Button {
                allowsMouseReporting.toggle()
            } label: {
                Image(systemName: icon)
            }
            .buttonStyle(
                TerminalCompactControlStyle(tint: tint)
            )
            .accessibilityLabel(
                allowsMouseReporting
                    ? "Interaction mode: Mouse"
                    : "Interaction mode: Browse"
            )
            .accessibilityHint(interactionModeHint)
            .accessibilityIdentifier(
                "terminalInteractionModeButton"
            )
        } else {
            Button {
                allowsMouseReporting.toggle()
            } label: {
                Label(
                    allowsMouseReporting ? "Mouse" : "Browse",
                    systemImage: icon
                )
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(tint)
            .accessibilityLabel(
                allowsMouseReporting
                    ? "Interaction mode: Mouse"
                    : "Interaction mode: Browse"
            )
            .accessibilityHint(interactionModeHint)
            .accessibilityIdentifier(
                "terminalInteractionModeButton"
            )
        }
    }

    private var interactionModeHint: String {
        allowsMouseReporting
            ? "Switches touches back to terminal scrolling"
            : "Sends taps and drags to mouse-aware terminal apps"
    }

    @ViewBuilder
    private func widthModeButton(compact: Bool) -> some View {
        if compact {
            Button {
                toggleWidthMode()
            } label: {
                Text(usesWideColumns ? "80" : "Fit")
                    .font(.caption.bold())
            }
            .buttonStyle(
                TerminalCompactControlStyle(
                    tint: usesWideColumns
                        ? ReLandTheme.accent
                        : ReLandTheme.strongText
                )
            )
            .accessibilityLabel(widthModeLabel)
            .accessibilityHint(widthModeHint)
            .accessibilityIdentifier("terminalWidthModeButton")
        } else {
            Button {
                toggleWidthMode()
            } label: {
                Label(
                    usesWideColumns ? "80 cols" : "Fit",
                    systemImage: "arrow.left.and.right"
                )
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(
                usesWideColumns
                    ? ReLandTheme.accent
                    : .secondary
            )
            .accessibilityLabel(widthModeLabel)
            .accessibilityHint(widthModeHint)
            .accessibilityIdentifier("terminalWidthModeButton")
        }
    }

    private func toggleWidthMode() {
        usesWideColumns.toggle()
        viewportState = .initial
    }

    private var widthModeLabel: String {
        usesWideColumns
            ? "Terminal width: 80 columns"
            : "Terminal width: Fit screen"
    }

    private var widthModeHint: String {
        usesWideColumns
            ? "Fits terminal output to the screen width"
            : "Keeps at least 80 columns and enables horizontal scrolling"
    }

    @ViewBuilder
    private func keyboardButton(compact: Bool) -> some View {
        if compact {
            Button {
                terminalController.toggleKeyboard()
            } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(
                TerminalCompactControlStyle(
                    tint: ReLandTheme.accent
                )
            )
            .accessibilityLabel("Show or hide keyboard")
            .accessibilityIdentifier("terminalKeyboardButton")
        } else {
            Button {
                terminalController.toggleKeyboard()
            } label: {
                Label("Keyboard", systemImage: "keyboard")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Show or hide keyboard")
            .accessibilityIdentifier("terminalKeyboardButton")
        }
    }

    private func openOnMacButton(
        _ session: TerminalSessionInfo,
        compact: Bool
    ) -> some View {
        Button {
            model.openTerminalOnMac(session)
        } label: {
            if compact {
                Image(systemName: "macwindow.on.rectangle")
                    .frame(width: 44, height: 44)
            } else {
                Label(
                    "Open on Mac",
                    systemImage: "macwindow.on.rectangle"
                )
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Open on Mac")
        .accessibilityIdentifier("terminalOpenOnMacButton")
    }

    private var terminalAccessoryBar: some View {
        ViewThatFits(in: .horizontal) {
            terminalKeyRow

            ScrollView(.horizontal) {
                terminalKeyRow
            }
            .scrollIndicators(.visible)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity)
        .background(ReLandTheme.chromeBackground)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var terminalKeyRow: some View {
        HStack(spacing: 8) {
            terminalActionKey(
                "Files",
                systemImage: "folder"
            ) {
                isArtifactsPresented = true
            }
            .accessibilityIdentifier(
                "terminalArtifactsButton"
            )
            terminalActionKey(
                "Mac",
                systemImage: "externaldrive"
            ) {
                isMacFilesPresented = true
            }
            .accessibilityIdentifier("terminalMacFilesButton")
            terminalKey("Esc", bytes: [0x1B])
            terminalKey("Tab", bytes: [0x09])
            terminalKey("Ctrl-C", bytes: [0x03])
            terminalKey("Ctrl-D", bytes: [0x04])
            terminalActionKey("PgUp") {
                terminalController.pageUp()
            }
            terminalActionKey("PgDn") {
                terminalController.pageDown()
            }
            terminalKey(
                "Home",
                bytes: [0x1B, 0x5B, 0x48]
            )
            terminalKey(
                "End",
                bytes: [0x1B, 0x5B, 0x46]
            )
            terminalKey(
                "Left",
                systemImage: "arrow.left",
                bytes: [0x1B, 0x5B, 0x44]
            )
            terminalKey(
                "Down",
                systemImage: "arrow.down",
                bytes: [0x1B, 0x5B, 0x42]
            )
            terminalKey(
                "Up",
                systemImage: "arrow.up",
                bytes: [0x1B, 0x5B, 0x41]
            )
            terminalKey(
                "Right",
                systemImage: "arrow.right",
                bytes: [0x1B, 0x5B, 0x43]
            )
        }
    }

    private func terminalKey(
        _ title: String,
        systemImage: String? = nil,
        bytes: [UInt8]
    ) -> some View {
        terminalActionKey(title, systemImage: systemImage) {
            model.sendTerminalInput(Data(bytes))
        }
    }

    private func terminalActionKey(
        _ title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(minWidth: 24)
                } else {
                    Text(title)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(TerminalKeyButtonStyle())
        .font(.caption.bold())
        .accessibilityLabel(title)
        .accessibilityIdentifier(
            "terminalKey-\(title)"
        )
    }
}

private struct TerminalCompactControlStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(
                configuration.isPressed
                    ? tint.opacity(0.24)
                    : ReLandTheme.controlBackground,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        tint.opacity(0.5),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
    }
}

private struct TerminalKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ReLandTheme.accent)
            .background(
                configuration.isPressed
                    ? ReLandTheme.accent.opacity(0.24)
                    : ReLandTheme.controlBackground,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        ReLandTheme.accent.opacity(0.4),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
    }
}

private struct TerminalSessionRow: View {
    let session: TerminalSessionInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(
                    .tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(
                    "\(session.windowCount) windows • "
                        + "\(session.attachedClientCount) attached"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Attach to this terminal session")
    }
}
