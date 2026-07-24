import ReLandCore
import SwiftUI

struct TerminalCreateView: View {
    @Bindable var model: ClientAppModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var launchProfile = TerminalLaunchProfile.shell
    @State private var bypassPermissions = false
    @State private var additionalArguments = ""
    @State private var workingDirectoryPath: String?
    @State private var workingDirectoryName: String?
    @State private var isWorkingDirectoryPickerPresented = false
    @State private var launchProfileName = ""
    @State private var isSaveProfilePresented = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Optional session name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    if let workingDirectoryName {
                        LabeledContent("Selected") {
                            Text(workingDirectoryName)
                                .accessibilityIdentifier(
                                    "selectedWorkingDirectory"
                                )
                        }
                        Button("Use ReLand session workspace") {
                            workingDirectoryPath = nil
                            self.workingDirectoryName = nil
                        }
                    } else {
                        Text("ReLand session workspace")
                            .foregroundStyle(
                                ReLandTheme.mutedText
                            )
                    }

                    Button {
                        isWorkingDirectoryPickerPresented = true
                    } label: {
                        Label(
                            "Choose Project Folder",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    .accessibilityIdentifier(
                        "chooseProjectFolderButton"
                    )
                } header: {
                    Text("Working Folder")
                } footer: {
                    Text(
                        "Only ReLand storage and folders approved in "
                            + "ReLand Host can be selected."
                    )
                }

                Section {
                    VStack(spacing: 10) {
                        ForEach(
                            TerminalLaunchProfile.allCases,
                            id: \.self
                        ) { profile in
                            Button {
                                launchProfile = profile
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: profile.icon
                                    )
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(
                                        launchProfile == profile
                                            ? ReLandTheme.accent
                                            : ReLandTheme.strongText
                                    )
                                    .frame(width: 32)

                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text(profile.title)
                                            .font(.headline)
                                            .foregroundStyle(
                                                ReLandTheme.strongText
                                            )
                                        Text(profile.shortDetail)
                                            .font(.caption)
                                            .foregroundStyle(
                                                ReLandTheme.mutedText
                                            )
                                            .fixedSize(
                                                horizontal: false,
                                                vertical: true
                                            )
                                    }

                                    Spacer()
                                    Image(
                                        systemName:
                                            launchProfile == profile
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .font(.title3)
                                    .foregroundStyle(
                                        launchProfile == profile
                                            ? ReLandTheme.accent
                                            : ReLandTheme.mutedText
                                    )
                                }
                                .padding(12)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .background(
                                    launchProfile == profile
                                        ? ReLandTheme.controlBackground
                                        : Color(
                                            uiColor:
                                                .secondarySystemBackground
                                        ),
                                    in: RoundedRectangle(
                                        cornerRadius: 12
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            launchProfile == profile
                                                ? ReLandTheme.accent
                                                : Color(
                                                    uiColor: .separator
                                                ),
                                            lineWidth:
                                                launchProfile == profile
                                                ? 2
                                                : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(profile.title)
                            .accessibilityValue(
                                launchProfile == profile
                                    ? "Selected"
                                    : "Not selected"
                            )
                        }
                    }
                } header: {
                    Text("Start with")
                }

                if let permissionOption =
                    launchProfile.permissionOption
                {
                    Section("Permissions") {
                        Toggle(
                            permissionOption.title,
                            isOn: $bypassPermissions
                        )
                        if bypassPermissions {
                            Label(
                                permissionOption.warning,
                                systemImage:
                                    "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .background(
                                Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }

                        if launchProfile != .shell {
                            Section {
                                ForEach(
                                    model.aiLaunchProfiles(
                                        for: launchProfile
                                    )
                                ) { profile in
                                    Button {
                                        additionalArguments =
                                            profile.additionalArguments
                                        bypassPermissions =
                                            profile.bypassPermissions
                                    } label: {
                                        HStack {
                                            VStack(
                                                alignment: .leading,
                                                spacing: 3
                                            ) {
                                                Text(profile.name)
                                                    .font(.headline)
                                                Text(
                                                    profile.isRisky
                                                        ? "Includes permission bypass"
                                                        : "Standard permissions"
                                                )
                                                .font(.caption)
                                                .foregroundStyle(
                                                    profile.isRisky
                                                        ? .orange
                                                        : ReLandTheme.mutedText
                                                )
                                            }
                                            Spacer()
                                            Image(
                                                systemName:
                                                    "arrow.down.circle"
                                            )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(
                                            "Delete Profile",
                                            role: .destructive
                                        ) {
                                            model.deleteAILaunchProfile(
                                                profile
                                            )
                                        }
                                    }
                                    .accessibilityIdentifier(
                                        "aiLaunchProfile-\(profile.id)"
                                    )
                                }

                                Button {
                                    launchProfileName =
                                        "\(launchProfile.rawValue.capitalized) Profile"
                                    isSaveProfilePresented = true
                                } label: {
                                    Label(
                                        "Save Current Options as Profile",
                                        systemImage: "bookmark"
                                    )
                                }
                                .accessibilityIdentifier(
                                    "saveAILaunchProfileButton"
                                )
                            } header: {
                                Text("Saved Launch Profiles")
                            } footer: {
                                Text(
                                    "Profiles that bypass permissions are only "
                                        + "enabled when you explicitly select them."
                                )
                            }
                        }
                    }
                }

                if launchProfile != .shell {
                    Section {
                        TextField(
                            "--model ...",
                            text: $additionalArguments,
                            axis: .vertical
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...5)
                    } header: {
                        Text("Additional arguments")
                    } footer: {
                        Text(
                            "Arguments are saved separately for "
                                + "\(launchProfile.title)."
                        )
                    }
                }
            }
            .navigationTitle("New Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSession()
                    }
                    .accessibilityIdentifier(
                        "confirmCreateTerminalButton"
                    )
                }
            }
        }
        .task {
            loadPreferences()
        }
        .onChange(of: launchProfile) { _, _ in
            loadPreferences()
        }
        .sheet(
            isPresented:
                $isWorkingDirectoryPickerPresented
        ) {
            TerminalWorkingDirectoryPickerView(
                model: model
            ) { path, name in
                workingDirectoryPath = path
                workingDirectoryName = name
                isWorkingDirectoryPickerPresented = false
            }
        }
        .alert(
            "Invalid launch arguments",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Save ReLand AI Profile",
            isPresented: $isSaveProfilePresented
        ) {
            TextField("Profile name", text: $launchProfileName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                do {
                    try model.saveAILaunchProfile(
                        name: launchProfileName,
                        tool: launchProfile,
                        additionalArguments:
                            additionalArguments,
                        bypassPermissions:
                            bypassPermissions
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text(
                bypassPermissions
                    ? "This named profile includes a dangerous permission-bypass flag."
                    : "Save these arguments for explicit reuse."
            )
        }
    }

    private func createSession() {
        do {
            var arguments = try ShellArgumentParser.parse(
                additionalArguments
            )
            if
                bypassPermissions,
                let flag = launchProfile.permissionOption?.flag,
                !arguments.contains(flag)
            {
                arguments.insert(flag, at: 0)
            }
            savePreferences()
            let preferredName = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            model.createTerminalSession(
                preferredName: preferredName.isEmpty
                    ? nil
                    : preferredName,
                launchProfile: launchProfile,
                launchArguments: arguments,
                workingDirectoryPath: workingDirectoryPath
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        bypassPermissions = false
        defaults.removeObject(
            forKey: preferenceKey("bypass")
        )
        additionalArguments = defaults.string(
            forKey: preferenceKey("arguments")
        ) ?? ""
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(
            additionalArguments,
            forKey: preferenceKey("arguments")
        )
    }

    private func preferenceKey(_ suffix: String) -> String {
        "reland.terminal.\(launchProfile.rawValue).\(suffix)"
    }
}

private extension TerminalLaunchProfile {
    var title: String {
        switch self {
        case .shell:
            "Shell / manual command"
        case .copilot:
            "ReLand AI · GitHub Copilot"
        case .claude:
            "ReLand AI · Claude Code"
        case .codex:
            "ReLand AI · OpenAI Codex"
        case .gemini:
            "ReLand AI · Gemini CLI"
        }
    }

    var detail: String {
        switch self {
        case .shell:
            "Starts a normal shell. Running copilot, claude, codex, "
                + "or gemini directly does not add ReLand file instructions."
        default:
            "Starts the selected AI through the `reland-ai` wrapper with "
                + "session-specific artifact instructions."
        }
    }

    var shortDetail: String {
        switch self {
        case .shell:
            "Normal shell; AI tools run without ReLand instructions."
        case .copilot:
            "Copilot with session artifact instructions."
        case .claude:
            "Claude Code with session artifact instructions."
        case .codex:
            "Codex with session artifact instructions."
        case .gemini:
            "Gemini CLI with session artifact instructions."
        }
    }

    var icon: String {
        switch self {
        case .shell:
            "terminal"
        case .copilot:
            "chevron.left.forwardslash.chevron.right"
        case .claude:
            "brain"
        case .codex:
            "curlybraces.square"
        case .gemini:
            "sparkles"
        }
    }

    var permissionOption:
        (title: String, flag: String, warning: String)?
    {
        switch self {
        case .shell:
            nil
        case .copilot:
            (
                "Allow all Copilot permissions",
                "--allow-all",
                "Copilot can use tools, paths, and URLs without prompting."
            )
        case .claude:
            (
                "Skip Claude permission prompts",
                "--dangerously-skip-permissions",
                "Claude can execute tools without asking for confirmation."
            )
        case .codex:
            (
                "Bypass Codex approvals and sandbox",
                "--dangerously-bypass-approvals-and-sandbox",
                "Codex receives unrestricted file and command access."
            )
        case .gemini:
            (
                "Auto-approve Gemini actions",
                "--yolo",
                "Gemini can execute tool actions without confirmation."
            )
        }
    }
}

private enum ShellArgumentParser {
    static func parse(_ input: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in input {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }
            if character == "\\" {
                isEscaping = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character.isNewline {
                throw ShellArgumentError.controlCharacter
            } else if character.isWhitespace {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        guard quote == nil, !isEscaping else {
            throw ShellArgumentError.unterminatedQuote
        }
        if !current.isEmpty {
            arguments.append(current)
        }
        return arguments
    }
}

private enum ShellArgumentError: LocalizedError {
    case unterminatedQuote
    case controlCharacter

    var errorDescription: String? {
        switch self {
        case .unterminatedQuote:
            "A launch argument has an unterminated quote or escape."
        case .controlCharacter:
            "Launch arguments cannot contain newlines."
        }
    }
}
