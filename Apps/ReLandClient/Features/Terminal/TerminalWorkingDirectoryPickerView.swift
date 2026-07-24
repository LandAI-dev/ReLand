import ReLandCore
import SwiftUI

struct TerminalWorkingDirectoryPickerView: View {
    @Bindable var model: ClientAppModel
    let onSelect: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.remoteFilePath.isEmpty {
                    Section {
                        Button {
                            onSelect(
                                model.remoteFilePath,
                                currentFolderName
                            )
                        } label: {
                            Label(
                                "Use This Folder",
                                systemImage:
                                    "checkmark.circle.fill"
                            )
                        }
                        .accessibilityIdentifier(
                            "useWorkingDirectoryButton"
                        )
                    } footer: {
                        Text(model.remoteFilePath)
                    }
                }

                Section(
                    model.remoteFilePath.isEmpty
                        ? "Approved locations"
                        : "Folders"
                ) {
                    let directories = model.remoteFiles.filter {
                        $0.kind == .directory
                    }
                    if
                        !model.isLoadingRemoteFiles,
                        directories.isEmpty
                    {
                        ContentUnavailableView(
                            "No folders",
                            systemImage: "folder",
                            description: Text(
                                "Approve a project folder in "
                                    + "ReLand Host on the Mac."
                            )
                        )
                    } else {
                        ForEach(directories) { entry in
                            Button {
                                model.requestRemoteFiles(
                                    path: entry.path
                                )
                            } label: {
                                Label(
                                    entry.name,
                                    systemImage: "folder"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "workingDirectory-\(entry.path)"
                            )
                        }
                    }
                }
            }
            .overlay {
                if model.isLoadingRemoteFiles {
                    ProgressView("Loading folders")
                }
            }
            .navigationTitle("Project Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if model.remoteFileParentPath != nil {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            model.navigateToParentRemoteFolder()
                        } label: {
                            Label(
                                "Parent Folder",
                                systemImage: "chevron.up"
                            )
                        }
                    }
                }
            }
        }
        .task {
            model.requestRemoteFiles(path: "")
        }
    }

    private var currentFolderName: String {
        if
            let rootName = model.remoteFileRootNames[
                model.remoteFilePath
            ]
        {
            return rootName
        }
        return URL(fileURLWithPath: model.remoteFilePath)
            .lastPathComponent
    }
}
