import AppKit
import Observation
import SwiftUI

private final class ScanProgressSink: @unchecked Sendable {
    weak var state: ScanState?
    init(state: ScanState) { self.state = state }
}

private struct ScanResult: @unchecked Sendable {
    let root: FileNode
    let pathIndex: [String: FileNode]
}

@Observable
@MainActor
final class ScanState {
    var rootNode: FileNode?
    var selectedNode: FileNode?
    var treemapRoot: FileNode?
    var isScanning: Bool = false
    var isUpdating: Bool = false
    var scanProgress: String = ""
    var filesScanned: Int = 0
    var hiddenCategories: Set<FileCategory> = []
    var lastTreeMutation: Date = .distantPast

    // Cleanup / reclaim
    var cleanupCandidates: [CleanupCandidate] = []
    var selectedCleanupIDs: Set<UUID> = []
    var deletionImpact: DeletionImpactAssessment?
    var isAnalyzingImpact: Bool = false
    var showCleanupPanel: Bool = false
    var cleanupError: String?
    var isBatchCleaning: Bool = false
    var cleanupBatchProgress = CleanupBatchProgress(completed: 0, total: 0, currentName: "", bytesReclaimed: 0, failedCount: 0)

    // Volume info
    var volumeTotalCapacity: Int64 = 0
    var volumeAvailableCapacity: Int64 = 0
    var volumeUsedCapacity: Int64 { volumeTotalCapacity - volumeAvailableCapacity }

    // Persistence state
    var cacheLoaded: Bool = false
    var lastScanDate: Date?

    // Path → node index for O(1) lookups during incremental updates
    private var nodesByPath = [String: FileNode]()

    private var scanTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var cleanupBatchTask: Task<Void, Never>?
    private let fsWatcher = FSEventsWatcher()
    private var lastEventID: UInt64 = 0
    private var liveUpdateQueue: LiveUpdateQueue!
    private var liveWatchRootPath: String?

    init() {
        liveUpdateQueue = LiveUpdateQueue { [weak self] paths in
            await self?.processLiveUpdateBatch(paths)
        }
    }

    var displayRoot: FileNode? {
        treemapRoot ?? rootNode
    }

    static func normalizePath(_ path: String) -> String {
        PathNormalizer.normalize(path)
    }

    /// Interactive launches scan the home directory. The in-process unit run must not.
    nonisolated static func shouldAutoScanOnLaunch(environment: [String: String]) -> Bool {
        environment["CHET_UNIT_TESTS"] != "1"
    }

    /// Resolve a directory from the path index, normalizing FSEvents-style trailing slashes.
    func directoryNode(forPath path: String) -> FileNode? {
        let normalized = Self.normalizePath(path)
        guard let node = nodesByPath[normalized], node.isDirectory else { return nil }
        return node
    }

    /// Install an in-memory tree for unit/integration checks (same module only).
    func installTestTree(_ root: FileNode, watchRootPath: String? = nil) {
        rootNode = root
        treemapRoot = root
        buildPathIndex(from: root)
        liveWatchRootPath = watchRootPath ?? Self.normalizePath(root.url.path(percentEncoded: false))
    }

    // MARK: - Volume Info

    func loadVolumeInfo(for url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ])
            volumeTotalCapacity = Int64(values.volumeTotalCapacity ?? 0)
            volumeAvailableCapacity = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        } catch {}
    }

    // MARK: - Cache Loading (instant launch)

    /// Try to load scan results from SQLite cache. Returns true if cache was found.
    func loadFromCache(rootPath: String) -> Bool {
        let normalizedPath = Self.normalizePath(rootPath)
        let cache = ScanCache.shared
        guard cache.open() else { return false }

        guard let (root, eventID) = cache.loadTree(for: normalizedPath) else {
            return false
        }

        self.rootNode = root
        self.treemapRoot = root
        self.lastEventID = eventID
        self.cacheLoaded = true
        self.lastScanDate = Date() // approximate
        buildPathIndex(from: root)
        loadVolumeInfo(for: URL(fileURLWithPath: rootPath))

        return true
    }

    // MARK: - Full Scan (first launch or cache miss)

    func startScan(url: URL) {
        scanTask?.cancel()
        updateTask?.cancel()
        liveUpdateQueue.cancel()
        fsWatcher.stopWatching()
        liveWatchRootPath = nil

        isScanning = true
        filesScanned = 0
        scanProgress = "Preparing..."
        selectedNode = nil
        treemapRoot = nil
        rootNode = nil
        cacheLoaded = false
        nodesByPath.removeAll()
        loadVolumeInfo(for: url)

        let scanner = DiskScanner()
        let rootPath = Self.normalizePath(url.standardizedFileURL.path(percentEncoded: false))

        scanTask = Task { [weak self] in
            guard let self else { return }
            let progressSink = ScanProgressSink(state: self)
            let result = await Task.detached { [progressSink, scanner, url] in
                let root = scanner.scan(url: url) { scanned, path in
                    Task { @MainActor in
                        progressSink.state?.filesScanned = scanned
                        progressSink.state?.scanProgress = path
                    }
                }
                let pathIndex = FileNode.makePathIndex(from: root)
                return ScanResult(root: root, pathIndex: pathIndex)
            }.value

            if !Task.isCancelled {
                self.rootNode = result.root
                self.treemapRoot = result.root
                self.nodesByPath = result.pathIndex

                let eventID = FSEventsWatcher.currentEventID()
                self.lastEventID = eventID
                self.startLiveWatching(rootPath: rootPath)

                let capturedRoot = result.root
                Task.detached { [weak self, rootPath, eventID, capturedRoot] in
                    let cache = ScanCache.shared
                    _ = cache.open()
                    cache.saveTree(capturedRoot, rootPath: rootPath, eventID: eventID)
                    await MainActor.run { [weak self] in
                        self?.cacheLoaded = true
                        self?.lastScanDate = Date()
                    }
                }
            }
            self.isScanning = false
            self.scanProgress = ""
        }
    }

    // MARK: - Incremental Update

    /// Query FSEvents for changes since last scan, rescan only changed directories.
    func startIncrementalUpdate(rootPath: String) {
        guard !isScanning, rootNode != nil else { return }

        updateTask?.cancel()
        liveUpdateQueue.cancel()
        isUpdating = true

        let storedEventID = lastEventID

        updateTask = Task { [weak self] in
            guard let self else { return }
            // Query FSEvents on background thread
            let result = await Task.detached {
                FSEventsWatcher.changedPaths(since: storedEventID, root: rootPath)
            }.value

            guard let (changedPaths, newEventID) = result else {
                // Event ID stale — need full rescan
                self.isUpdating = false
                self.startScan(url: URL(fileURLWithPath: rootPath))
                return
            }

            if changedPaths.isEmpty {
                self.lastEventID = newEventID
                self.isUpdating = false
                // Update event ID in DB
                await Task.detached {
                    ScanCache.shared.updateMeta(rootPath: rootPath, eventID: newEventID)
                }.value
                self.startLiveWatching(rootPath: rootPath)
                return
            }

            // Rescan each changed directory
            let scanner = DiskScanner()
            var seenInodes = Set<UInt64>()
            let cache = ScanCache.shared

            var batchCacheWork = DiffCacheWork()

            for dirPath in changedPaths {
                if Task.isCancelled { break }

                guard let dirNode = self.directoryNode(forPath: dirPath) else {
                    continue
                }

                let normalizedPath = Self.normalizePath(dirPath)
                let dirURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
                let currentChildren = await Task.detached {
                    scanner.scanDirectory(at: dirURL, seenInodes: &seenInodes)
                }.value

                let existingNames = Set(dirNode.children.map(\.name))
                let prepared = await Self.prepareChildrenForDiff(
                    currentChildren,
                    existingNames: existingNames
                )
                var cacheWork = DiffCacheWork()
                self.applyDiff(to: dirNode, newChildren: prepared, cacheWork: &cacheWork)
                batchCacheWork.merge(cacheWork)
            }

            Self.persistCacheWork(batchCacheWork)

            // Update event ID
            self.lastEventID = newEventID
            await Task.detached {
                cache.updateMeta(rootPath: rootPath, eventID: newEventID)
            }.value

            self.isUpdating = false
            self.startLiveWatching(rootPath: rootPath)
        }
    }

    // MARK: - Live Watching

    private func startLiveWatching(rootPath: String) {
        liveWatchRootPath = rootPath
        fsWatcher.startWatching(root: rootPath, latency: 3.0) { [weak self] changedPaths in
            Task { @MainActor [weak self] in
                guard let self, !self.isScanning, !self.isUpdating else { return }
                self.liveUpdateQueue.enqueue(paths: changedPaths)
            }
        }
    }

    private func processLiveUpdateBatch(_ paths: [String]) async {
        guard !isScanning, !isUpdating, let rootPath = liveWatchRootPath else { return }

        let scanner = DiskScanner()
        var seenInodes = Set<UInt64>()
        var updates = [(dirNode: FileNode, children: [FileNode])]()

        for path in paths {
            if Task.isCancelled { break }
            guard let dirNode = directoryNode(forPath: path) else { continue }

            let normalizedPath = Self.normalizePath(path)
            let dirURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
            let currentChildren = await Task.detached {
                scanner.scanDirectory(at: dirURL, seenInodes: &seenInodes)
            }.value
            updates.append((dirNode, currentChildren))
        }

        guard !Task.isCancelled else { return }

        var batchCacheWork = DiffCacheWork()
        for update in updates {
            let existingNames = Set(update.dirNode.children.map(\.name))
            let prepared = await Self.prepareChildrenForDiff(
                update.children,
                existingNames: existingNames
            )
            var cacheWork = DiffCacheWork()
            applyDiff(to: update.dirNode, newChildren: prepared, cacheWork: &cacheWork)
            batchCacheWork.merge(cacheWork)
        }
        Self.persistCacheWork(batchCacheWork)

        let newEventID = FSEventsWatcher.currentEventID()
        lastEventID = newEventID
        let capturedRootPath = rootPath
        Task.detached {
            ScanCache.shared.updateMeta(rootPath: capturedRootPath, eventID: newEventID)
        }
    }

    // MARK: - Diff & Apply

    /// Scan + expand new directory stubs off the main actor before applyDiff.
    static func prepareChildrenForDiff(
        _ children: [FileNode],
        existingNames: Set<String>
    ) async -> [FileNode] {
        await Task.detached {
            let scanner = DiskScanner()
            for child in children where child.isDirectory
                && !existingNames.contains(child.name)
                && child.fileCount > 0 {
                scanner.expandDirectoryStub(child)
            }
            return children
        }.value
    }

    static func persistCacheWork(_ work: DiffCacheWork) {
        Task.detached { work.persist() }
    }

    static func persistCacheWorkAwaitable(_ work: DiffCacheWork) async {
        await Task.detached { work.persist() }.value
    }

    /// Main-actor merge only; cache I/O is deferred via `cacheWork`.
    private func applyDiff(
        to dirNode: FileNode,
        newChildren: [FileNode],
        cacheWork: inout DiffCacheWork
    ) {
        let oldByName = Dictionary(uniqueKeysWithValues: dirNode.children.map { ($0.name, $0) })
        let newByName = Dictionary(uniqueKeysWithValues: newChildren.map { ($0.name, $0) })
        let parentPath = dirNode.url.path(percentEncoded: false)
        let grandparentPath = dirNode.parent?.url.path(percentEncoded: false)
        cacheWork.recordUpsertDirectory(dirNode, parentPath: grandparentPath)

        var sizeDelta: Int64 = 0
        var logicalDelta: Int64 = 0
        var filesDelta = 0
        var dirsDelta = 0

        for (_, oldChild) in oldByName where newByName[oldChild.name] == nil {
            sizeDelta -= oldChild.size
            logicalDelta -= oldChild.logicalSize
            filesDelta -= oldChild.fileCount
            if oldChild.isDirectory {
                dirsDelta -= 1 + oldChild.directoryCount
            }
            removePaths(for: oldChild)
            let childPath = oldChild.url.path(percentEncoded: false)
            if oldChild.isDirectory {
                cacheWork.recordDeleteSubtree(path: childPath)
            } else {
                cacheWork.recordDeleteNode(path: childPath)
            }
        }

        for (name, newChild) in newByName {
            if let oldChild = oldByName[name] {
                let sizeChanged = oldChild.size != newChild.size
                let mtimeChanged = oldChild.modificationDate != newChild.modificationDate
                var childFilesDelta = 0
                var childDirsDelta = 0
                if oldChild.isDirectory {
                    childFilesDelta = newChild.fileCount - oldChild.fileCount
                    childDirsDelta = newChild.directoryCount - oldChild.directoryCount
                }

                if sizeChanged || mtimeChanged || childFilesDelta != 0 || childDirsDelta != 0 {
                    if sizeChanged {
                        sizeDelta += newChild.size - oldChild.size
                        logicalDelta += newChild.logicalSize - oldChild.logicalSize
                    }
                    filesDelta += childFilesDelta
                    dirsDelta += childDirsDelta

                    oldChild.size = newChild.size
                    oldChild.allocatedSize = newChild.allocatedSize
                    oldChild.logicalSize = newChild.logicalSize
                    oldChild.modificationDate = newChild.modificationDate
                    if oldChild.isDirectory {
                        oldChild.fileCount = newChild.fileCount
                        oldChild.directoryCount = newChild.directoryCount
                    }

                    cacheWork.recordUpsertNode(oldChild, parentPath: parentPath)
                }
            } else {
                newChild.parent = dirNode
                if newChild.isDirectory {
                    dirsDelta += 1 + newChild.directoryCount
                    cacheWork.recordUpsertSubtree(newChild, parentPath: parentPath)
                    addSubtreeToPathIndex(newChild)
                } else {
                    let childPath = newChild.url.path(percentEncoded: false)
                    nodesByPath[childPath] = newChild
                    cacheWork.recordUpsertNode(newChild, parentPath: parentPath)
                }
                dirNode.children.append(newChild)
                sizeDelta += newChild.size
                logicalDelta += newChild.logicalSize
                filesDelta += newChild.fileCount
            }
        }

        dirNode.children.removeAll { child in
            newByName[child.name] == nil && oldByName[child.name] != nil
        }

        dirNode.sortChildrenBySize()

        if sizeDelta != 0 || logicalDelta != 0 || filesDelta != 0 || dirsDelta != 0 {
            propagateSizeChange(
                from: dirNode,
                sizeDelta: sizeDelta,
                logicalDelta: logicalDelta,
                filesDelta: filesDelta,
                dirsDelta: dirsDelta
            )
        }

        notifyTreeMutation()
    }

    private func notifyTreeMutation() {
        lastTreeMutation = Date()
    }

    // MARK: - Size Propagation

    private func propagateSizeChange(from node: FileNode, sizeDelta: Int64, logicalDelta: Int64, filesDelta: Int, dirsDelta: Int) {
        var current: FileNode? = node
        while let n = current {
            n.size += sizeDelta
            n.allocatedSize += sizeDelta
            n.logicalSize += logicalDelta
            n.fileCount += filesDelta
            n.directoryCount += dirsDelta
            if let parent = n.parent {
                parent.sortChildrenBySize()
            }
            current = n.parent
        }
    }

    /// Exercises the real applyDiff population path from unit tests.
    func applyPopulationDiff(forTesting dirNode: FileNode, newChildren: [FileNode], rootPath: String) async {
        _ = ScanCache.shared.open()
        let existingNames = Set(dirNode.children.map(\.name))
        let prepared = await Self.prepareChildrenForDiff(newChildren, existingNames: existingNames)
        var cacheWork = DiffCacheWork()
        applyDiff(to: dirNode, newChildren: prepared, cacheWork: &cacheWork)
        await Self.persistCacheWorkAwaitable(cacheWork)
    }

    // MARK: - Path Index

    private func buildPathIndex(from root: FileNode) {
        nodesByPath = FileNode.makePathIndex(from: root)
    }

    private func removePaths(for node: FileNode) {
        var stack: [FileNode] = [node]
        while let n = stack.popLast() {
            let path = n.url.path(percentEncoded: false)
            nodesByPath.removeValue(forKey: path)
            stack.append(contentsOf: n.children)
        }
    }

    private func addSubtreeToPathIndex(_ root: FileNode) {
        var stack = [root]
        while let node = stack.popLast() {
            let path = node.url.path(percentEncoded: false)
            nodesByPath[path] = node
            stack.append(contentsOf: node.children)
        }
    }

    private func loadDirectoryChildren(for node: FileNode) -> [FileNode] {
        let dirPath = node.url.path(percentEncoded: false)
        var children: [FileNode] = []
        if cacheLoaded {
            children = ScanCache.shared.loadChildren(forPath: dirPath)
        }
        if children.isEmpty && node.fileCount > 0 {
            let scanner = DiskScanner()
            var seenInodes = Set<UInt64>()
            children = scanner.scanDirectory(at: node.url, seenInodes: &seenInodes)
            if cacheLoaded, !children.isEmpty {
                let cache = ScanCache.shared
                for child in children {
                    cache.upsertNode(child, parentPath: dirPath)
                }
            }
        }
        return children
    }

    // MARK: - Navigation

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        scanProgress = ""
    }

    /// Sidebar List selection: directories update the treemap root; files only update detail selection.
    func selectInSidebar(_ node: FileNode?) {
        guard let node else {
            selectedNode = nil
            return
        }
        if node.isDirectory {
            drillInto(node)
        } else {
            selectedNode = node
        }
    }

    func drillInto(_ node: FileNode) {
        guard node.isDirectory else { return }

        // Lazy-load children from DB if this directory has none loaded
        // (directories loaded from cache may have fileCount > 0 but empty children array)
        if node.children.isEmpty && node.fileCount > 0 {
            let children = loadDirectoryChildren(for: node)
            for child in children {
                child.parent = node
                let childPath = child.url.path(percentEncoded: false)
                nodesByPath[childPath] = child
                if child.isDirectory {
                    addSubtreeToPathIndex(child)
                }
            }
            node.children = children
            if !FileNode.childrenAreSortedBySize(children) {
                node.sortChildrenBySize()
            }
        }

        treemapRoot = node
        selectedNode = node
    }

    func drillUp() {
        guard let current = treemapRoot, let p = current.parent else { return }
        treemapRoot = p
        selectedNode = p
    }

    func drillToRoot() {
        treemapRoot = rootNode
        selectedNode = rootNode
    }

    func toggleCategory(_ cat: FileCategory) {
        if hiddenCategories.contains(cat) {
            hiddenCategories.remove(cat)
        } else {
            hiddenCategories.insert(cat)
        }
    }

    func chooseDirectoryAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to analyze"
        panel.prompt = "Analyze"

        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url)
        }
    }

    // MARK: - Cleanup

    func node(forPath path: String) -> FileNode? {
        nodesByPath[Self.normalizePath(path)]
    }

    func refreshCleanupCandidates() {
        guard let root = displayRoot ?? rootNode else {
            cleanupCandidates = []
            selectedCleanupIDs = []
            return
        }
        let previouslySelectedPaths = Set(
            cleanupCandidates
                .filter { selectedCleanupIDs.contains($0.id) }
                .map { PathNormalizer.normalize($0.path) }
        )
        cleanupCandidates = CleanupPlanner.findCandidates(in: root)
        if !previouslySelectedPaths.isEmpty {
            selectedCleanupIDs = Set(
                cleanupCandidates
                    .filter { previouslySelectedPaths.contains(PathNormalizer.normalize($0.path)) }
                    .map(\.id)
            )
        }
    }

    var collapsedSelectedCleanupCandidates: [CleanupCandidate] {
        CleanupSelection.collapsed(from: cleanupCandidates, selectedIDs: selectedCleanupIDs)
    }

    var selectedCleanupBytes: Int64 {
        CleanupSelection.tallyBytes(from: cleanupCandidates, selectedIDs: selectedCleanupIDs)
    }

    var collapsedSelectionCount: Int {
        CleanupSelection.selectionCount(from: cleanupCandidates, selectedIDs: selectedCleanupIDs)
    }

    func toggleCleanupSelection(_ id: UUID) {
        if selectedCleanupIDs.contains(id) {
            selectedCleanupIDs.remove(id)
        } else {
            selectedCleanupIDs.insert(id)
        }
    }

    func selectAllCleanupCandidates() {
        selectedCleanupIDs = Set(cleanupCandidates.map(\.id))
    }

    func clearCleanupSelection() {
        selectedCleanupIDs = []
    }

    func applyCleanupPreset(_ preset: CleanupPreset) {
        selectedCleanupIDs = CleanupPreset.matchingIDs(in: cleanupCandidates, preset: preset)
    }

    func cancelBatchCleanup() {
        cleanupBatchTask?.cancel()
    }

    func startBatchCleanup() {
        guard !isBatchCleaning else { return }
        let collapsed = collapsedSelectedCleanupCandidates
        guard !collapsed.isEmpty else { return }

        cleanupError = nil
        isBatchCleaning = true
        cleanupBatchProgress = CleanupBatchProgress(
            completed: 0, total: collapsed.count, currentName: "", bytesReclaimed: 0, failedCount: 0
        )

        let pathIndex = nodesByPath

        cleanupBatchTask = Task.detached(priority: .userInitiated) { [collapsed, pathIndex, weak self] in
            guard let self else { return }
            let result = await CleanupBatchExecutor.trashItems(
                candidates: collapsed,
                nodesByPath: pathIndex,
                isCancelled: { Task.isCancelled },
                onProgress: { progress in
                    await MainActor.run {
                        self.cleanupBatchProgress = progress
                    }
                }
            )
            await self.applyBatchCleanupResult(result)
        }
    }

    private func applyBatchCleanupResult(_ result: CleanupBatchResult) async {
        let scanner = DiskScanner()

        for parentPath in result.parentPathsToRefresh {
            guard let parent = directoryNode(forPath: parentPath) else { continue }
            var seenInodes = Set<UInt64>()
            let currentChildren = await Task.detached {
                scanner.scanDirectory(at: parent.url, seenInodes: &seenInodes)
            }.value

            let existingNames = Set(parent.children.map(\.name))
            let prepared = await Self.prepareChildrenForDiff(currentChildren, existingNames: existingNames)
            var cacheWork = DiffCacheWork()
            applyDiff(to: parent, newChildren: prepared, cacheWork: &cacheWork)
            Self.persistCacheWork(cacheWork)
        }

        if let rootURL = rootNode?.url {
            loadVolumeInfo(for: rootURL)
        }

        refreshCleanupCandidates()
        clearCleanupSelection()

        isBatchCleaning = false
        cleanupBatchTask = nil

        if result.wasCancelled {
            if result.bytesReclaimed > 0 {
                let reclaimed = SizeFormatter.format(result.bytesReclaimed)
                cleanupError = "Cancelled after reclaiming \(reclaimed)."
            } else {
                cleanupError = "Batch cleanup cancelled."
            }
        } else if result.failedCount > 0 {
            let reclaimed = SizeFormatter.format(result.bytesReclaimed)
            cleanupError = "Reclaimed \(reclaimed); \(result.failedCount) item(s) skipped or failed."
        } else if result.bytesReclaimed > 0 {
            cleanupError = nil
        }
    }

    func analyzeDeletionImpact(for node: FileNode) {
        isAnalyzingImpact = true
        let rootPath = rootNode?.url.path(percentEncoded: false)
        Task {
            let assessment = await DeletionImpactAnalyzer.analyze(node: node, rootPath: rootPath)
            deletionImpact = assessment
            isAnalyzingImpact = false
        }
    }

    func moveToTrash(_ node: FileNode) async {
        cleanupError = nil
        let rootPath = rootNode?.url.path(percentEncoded: false)
        let assessment = await DeletionImpactAnalyzer.analyze(node: node, rootPath: rootPath)
        deletionImpact = assessment

        guard assessment.allowsDeletion else {
            cleanupError = assessment.summary
            return
        }

        guard let parent = node.parent else {
            cleanupError = "Missing parent directory."
            return
        }

        do {
            _ = try CleanupExecutor.moveToTrash(url: node.url)
        } catch {
            cleanupError = String(describing: error)
            return
        }

        let scanner = DiskScanner()
        var seenInodes = Set<UInt64>()
        let currentChildren = await Task.detached {
            scanner.scanDirectory(at: parent.url, seenInodes: &seenInodes)
        }.value

        let existingNames = Set(parent.children.map(\.name))
        let prepared = await Self.prepareChildrenForDiff(currentChildren, existingNames: existingNames)
        var cacheWork = DiffCacheWork()
        applyDiff(to: parent, newChildren: prepared, cacheWork: &cacheWork)
        Self.persistCacheWork(cacheWork)

        if let rootURL = rootNode?.url {
            loadVolumeInfo(for: rootURL)
        }

        if selectedNode?.id == node.id {
            selectedNode = parent
        }
        if treemapRoot?.id == node.id {
            treemapRoot = parent
        }

        refreshCleanupCandidates()
        deletionImpact = nil
    }
}
