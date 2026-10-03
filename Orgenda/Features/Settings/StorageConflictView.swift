import SwiftUI

struct StorageConflictsView: View {
    let store: WorkspaceStore

    var body: some View {
        List {
            if !store.syncConflicts.isEmpty {
                Section {
                    ForEach(store.syncConflicts) { conflict in
                        NavigationLink {
                            StorageConflictView(store: store, path: conflict.path)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conflict.path).font(.body.weight(.medium))
                                Text(LocalizedStringKey(conflict.remoteContents == nil ? "Deleted at storage location" : "Changed on this device and at storage location"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("storage.conflict.\(conflict.path)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if store.syncConflicts.isEmpty {
                ContentUnavailableView("No Conflicts", systemImage: "checkmark.circle")
                    .orgendaEmptyState()
            }
        }
        .tint(OrgendaTheme.accentText)
        .navigationTitle("Resolve Conflicts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StorageConflictView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let path: String
    @State private var pendingResolution: ResolutionPrompt?
    @State private var isResolving = false

    private var conflict: WorkspaceConflict? { store.syncConflicts.first { $0.path == path } }

    private struct ResolutionPrompt {
        let resolution: WorkspaceConflictResolution
        let conflict: WorkspaceConflict
    }

    var body: some View {
        List {
            if let conflict {
                Section {
                    Text(conflict.path).font(.headline)
                        .listRowBackground(Color.clear)
                }
                Section {
                    StorageVersionPreview(title: "On This Device", contents: conflict.localContents,
                                          modifiedAt: nil, identifier: "storage.conflict.local")
                }
                Section {
                    StorageVersionPreview(title: "At Storage Location", contents: conflict.remoteContents,
                                          modifiedAt: conflict.remoteModifiedAt, identifier: "storage.conflict.remote")
                }
                Section {
                    Button {
                        resolve(.keepBoth, expectedConflict: conflict)
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            if isResolving { ProgressView().tint(.white) }
                            Text("Keep Both").fontWeight(.semibold)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OrgendaTheme.accent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("storage.conflict.keepBoth")
                }
                Section {
                    Button("Use This Device's Version") {
                        pendingResolution = ResolutionPrompt(resolution: .useLocal, conflict: conflict)
                    }
                        .accessibilityIdentifier("storage.conflict.useLocal")
                    Button("Use Storage Version") {
                        pendingResolution = ResolutionPrompt(resolution: .useRemote, conflict: conflict)
                    }
                        .accessibilityIdentifier("storage.conflict.useRemote")
                }
                if let error = store.fileSyncError {
                    Section("File changes need attention") {
                        Text(error).font(.subheadline).textSelection(.enabled)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if conflict == nil {
                ContentUnavailableView("Conflict Resolved", systemImage: "checkmark.circle")
                    .orgendaEmptyState()
            }
        }
        .tint(OrgendaTheme.accentText)
        .disabled(isResolving || store.isSynchronizing)
        .navigationTitle("Resolve Conflict")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(resolutionTitle, isPresented: Binding(
            get: { pendingResolution != nil }, set: { if !$0 { pendingResolution = nil } }
        ), titleVisibility: .visible) {
            if let pendingResolution {
                Button(LocalizedStringKey(pendingResolution.resolution == .useLocal ? "Use This Device's Version" : "Use Storage Version"), role: .destructive) {
                    resolve(pendingResolution.resolution, expectedConflict: pendingResolution.conflict)
                    self.pendingResolution = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingResolution = nil }
        } message: {
            Text(resolutionMessage)
        }
    }

    private var resolutionTitle: LocalizedStringKey {
        pendingResolution?.resolution == .useLocal ? "Use this device's version?" : "Use storage version?"
    }

    private var resolutionMessage: String {
        if pendingResolution?.resolution == .useLocal {
            return String(localized: "The storage version will be replaced with your local edits. A recovery copy of the storage version will be kept.")
        }
        if pendingResolution?.conflict.remoteContents == nil {
            return String(localized: "The file was deleted at the storage location. A recovery copy of your edits will be kept before removing it from this workspace.")
        }
        return String(localized: "Your local edits will be replaced with the storage version. A recovery copy of your local edits will be kept.")
    }

    private func resolve(_ resolution: WorkspaceConflictResolution, expectedConflict: WorkspaceConflict) {
        guard !isResolving else { return }
        isResolving = true
        Task {
            await store.resolveSyncConflict(path: path, resolution: resolution, expectedConflict: expectedConflict)
            isResolving = false
            if conflict == nil { dismiss() }
        }
    }
}

private struct StorageVersionPreview: View {
    let title: LocalizedStringKey
    let contents: String?
    let modifiedAt: Date?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.body.weight(.medium))
            if let modifiedAt {
                Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let contents {
                ScrollView([.horizontal, .vertical]) {
                    Text(contents.isEmpty ? String(localized: "Empty file") : contents)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(height: 130)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier(identifier)
            } else {
                Label("Deleted at storage location", systemImage: "trash")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(identifier)
            }
        }
        .padding(.vertical, 6)
    }
}
