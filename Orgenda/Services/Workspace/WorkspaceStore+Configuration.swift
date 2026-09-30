import Foundation

extension WorkspaceStore {
    var effectiveConfiguration: WorkspaceConfiguration { hasWorkspaceConfiguration ? configuration : .classic }

    func workflow(for path: String) -> WorkspaceConfiguration.Workflow {
        OrgConfiguredHeading.workflow(in: documents.first { $0.path == path }?.contents ?? "",
                                      base: effectiveConfiguration.workflow)
    }

    @discardableResult
    func acceptConfiguration(_ source: String?) -> Bool {
        guard source != configurationSource else { return false }
        configurationSource = source
        do {
            let document = try source.map(ConfigurationDocument.init) ?? ConfigurationDocument(configuration: .standard)
            configurationDocument = document
            configuration = document.configuration
            configurationError = nil
            configurationRevision &+= 1
            rebuildDerivedCollections()
            if let source {
                connectionDefaults.set(source, forKey: configurationCacheKey)
            } else {
                connectionDefaults.removeObject(forKey: configurationCacheKey)
            }
            return true
        } catch {
            configurationError = error.localizedDescription
            // Recover only a cache belonging to this exact storage identity.
            if let cached = connectionDefaults.string(forKey: configurationCacheKey),
               let good = try? ConfigurationDocument(cached) {
                configurationDocument = good
                configuration = good.configuration
            }
            configurationRevision &+= 1
            rebuildDerivedCollections()
            return true
        }
    }

    private var configurationCacheKey: String {
        "workspace.configuration.lastValid." + (storageConnection?.identity ?? workspaceFileSessionID.uuidString)
    }

    /// Compare the editor's revision before and after each actor hop. No UI
    /// value is made effective until the local durable snapshot is committed.
    @discardableResult
    func saveConfiguration(_ value: WorkspaceConfiguration, expectedRevision: UInt64) async -> Bool {
        guard !isSavingConfiguration, !isChangingStorage, expectedRevision == configurationRevision else {
            configurationError = "The configuration changed. Reload before applying this edit."
            return false
        }
        guard let fileStore else { configurationError = "Connect a workspace first."; return false }
        if let source = configurationSource, (try? ConfigurationDocument(source)) == nil {
            configurationError = "Repair the existing config.json before saving settings."
            return false
        }
        guard !syncConflicts.contains(where: { $0.path == "config.json" }) else {
            configurationError = "Resolve the config.json sync conflict first."
            return false
        }
        isSavingConfiguration = true
        defer { isSavingConfiguration = false }
        let session = workspaceFileSessionID
        do {
            let source = try configurationDocument.encoded(value)
            try await fileStore.write(path: "config.json", contents: source, expectedContents: configurationSource)
            guard session == workspaceFileSessionID else { return false }
            if let workspaceSession {
                let snapshot = try await workspaceSession.snapshot()
                guard session == workspaceFileSessionID else { return false }
                applyStorageSnapshot(snapshot)
            } else {
                _ = acceptConfiguration(source)
                let document = WorkspaceDocument(path: "config.json", title: "Configuration", contents: source, kind: .configuration)
                documents.removeAll { $0.path == "config.json" }
                documents.append(document)
                scheduleWorkspaceParse()
            }
            if syncConflicts.contains(where: { $0.path == "config.json" }) {
                configurationError = "The configuration changed during saving. Resolve the sync conflict."
                return false
            }
            Task { await synchronizeFiles() }
            return true
        } catch {
            configurationError = error.localizedDescription
            return false
        }
    }

    func capture(_ template: WorkspaceConfiguration.Template, rendered: String, date: Date,
                 createMissing: Bool, expectedContents: String?) -> Bool {
        let current = documents.first { $0.path == template.target.path }
        guard current?.contents == expectedContents else {
            operationError = "The capture destination changed. Preview the template again."
            return false
        }
        do {
            var validation = effectiveConfiguration
            validation.capture.templates = [template]
            validation.capture.defaultTemplate = template.id
            try validation.validate()
            var document = current ?? WorkspaceDocument(path: template.target.path, title: (template.target.path as NSString).lastPathComponent,
                                                       contents: "", kind: .org)
            let parsed = OrgIndexService.parseSynchronously([document], configuration: effectiveConfiguration)[0]
            document.contents = try ConfiguredCapture.inserting(rendered, template: template, into: document.contents,
                                                               parsed: parsed, date: date, createMissing: createMissing)
            if let index = documents.firstIndex(where: { $0.path == document.path }) { documents[index] = document }
            else { documents.append(document) }
            scheduleWorkspaceRefresh(changedPaths: [document.path])
            operationError = nil
            return true
        } catch { operationError = error.localizedDescription; return false }
    }

}
