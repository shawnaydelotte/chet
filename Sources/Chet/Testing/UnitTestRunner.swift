import CoreGraphics
import Foundation

enum UnitTestRunner {
    static func runAll() -> Int {
        var failures = 0

        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        func checkFullyContained(_ name: String, at point: CGPoint, in canvas: CGSize) {
            let placement = TreemapTooltip.place(at: point, in: canvas)
            check(
                "\(name).contained",
                TreemapTooltip.isFullyContained(
                    center: placement.center,
                    size: placement.effectiveSize,
                    in: canvas
                )
            )
            check(
                "\(name).contentFits",
                TreemapTooltip.contentFits(in: placement.effectiveSize)
            )
        }

        let size = CGSize(width: 800, height: 600)
        let halfW = TreemapTooltip.width / 2
        let halfH = TreemapTooltip.height / 2

        for (label, point) in [
            ("left", CGPoint(x: 5, y: 300)),
            ("right", CGPoint(x: 795, y: 300)),
            ("top", CGPoint(x: 400, y: 5)),
            ("bottom", CGPoint(x: 400, y: 595)),
            ("center", CGPoint(x: 400, y: 300)),
        ] {
            checkFullyContained("tooltip.\(label)", at: point, in: size)
        }

        let narrow = CGSize(width: 200, height: 600)
        checkFullyContained("tooltip.leftFlip", at: CGPoint(x: 30, y: 300), in: narrow)

        let short = CGSize(width: 800, height: 120)
        checkFullyContained("tooltip.topFlip", at: CGPoint(x: 400, y: 100), in: short)

        let tiny = CGSize(width: 100, height: 50)
        let tinyPlacement = TreemapTooltip.place(at: CGPoint(x: 10, y: 10), in: tiny)
        check(
            "tooltip.tiny.contained",
            TreemapTooltip.isFullyContained(
                center: tinyPlacement.center,
                size: tinyPlacement.effectiveSize,
                in: tiny
            )
        )
        check("tooltip.tiny.effectiveWidth", tinyPlacement.effectiveSize.width == tiny.width)
        check("tooltip.tiny.effectiveHeight", tinyPlacement.effectiveSize.height == tiny.height)
        check("tooltip.tiny.contentFits", TreemapTooltip.contentFits(in: tinyPlacement.effectiveSize))
        check("tooltip.tiny.compactMode", tinyPlacement.contentMode == .compact)
        let tinyRect = TreemapTooltip.boundingRect(center: tinyPlacement.center, size: tinyPlacement.effectiveSize)
        check("tooltip.tiny.fillsCanvas", tinyRect.width == tiny.width && tinyRect.height == tiny.height)

        let nominalPlacement = TreemapTooltip.place(at: CGPoint(x: 400, y: 300), in: size)
        check("tooltip.nominal.fullMode", nominalPlacement.contentMode == .full)
        check("tooltip.nominal.contentFits", TreemapTooltip.contentFits(in: nominalPlacement.effectiveSize))

        for (label, gridSize) in [
            ("standard", size),
            ("narrow", narrow),
            ("short", short),
            ("tiny", tiny),
        ] {
            var gridFailures = 0
            let step = max(10, min(gridSize.width, gridSize.height) / 5)
            for x in stride(from: CGFloat(0), through: gridSize.width, by: step) {
                for y in stride(from: CGFloat(0), through: gridSize.height, by: step) {
                    let placement = TreemapTooltip.place(at: CGPoint(x: x, y: y), in: gridSize)
                    if !TreemapTooltip.isFullyContained(
                        center: placement.center,
                        size: placement.effectiveSize,
                        in: gridSize
                    ) || !TreemapTooltip.contentFits(in: placement.effectiveSize) {
                        gridFailures += 1
                    }
                }
            }
            check("tooltip.grid.\(label).allContained", gridFailures == 0)
        }

        let centerPlacement = TreemapTooltip.place(at: CGPoint(x: 400, y: 300), in: size)
        check(
            "tooltip.center.x",
            abs(centerPlacement.center.x - (400 + TreemapTooltip.offset + halfW)) <= 0.5
        )
        check(
            "tooltip.center.y",
            abs(centerPlacement.center.y - (300 + TreemapTooltip.offset + halfH)) <= 0.5
        )

        failures += runRelativeScalingTests()
        failures += runCleanupTests()
        failures += runCleanupBatchAsyncTests()
        failures += runLiveUpdateQueueTests()
        failures += runScanStateIntegrationTests()
        failures += runPopulationTests()
        failures += runPopulationPathTests()
        failures += runCachePrefixTests()
        failures += runCacheReloadTests()

        check(
            "launch.unitTestsSkipAutoScan",
            !ScanState.shouldAutoScanOnLaunch(environment: ["CHET_UNIT_TESTS": "1"])
        )
        check(
            "launch.interactiveAutoScan",
            ScanState.shouldAutoScanOnLaunch(environment: [:])
        )

        check("formatter.percent.whole", SizeFormatter.percentage(50, of: 0) == "0%")
        check("formatter.percent.half", SizeFormatter.percentage(1, of: 2) == "50.0%")
        check("normalize.trailingSlash", PathNormalizer.normalize("/Users/test/") == "/Users/test")
        check("normalize.root", PathNormalizer.normalize("/") == "/")

        if failures == 0 {
            print("All unit checks passed")
        } else {
            print("Unit checks failed: \(failures)")
        }
        return failures
    }

    private static func runRelativeScalingTests() -> Int {
        var failures = 0

        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        check("scale.fraction.zeroMax", RelativeSizeScale.fraction(value: 100, of: 0) == 0)
        check("scale.fraction.half", abs(RelativeSizeScale.fraction(value: 50, of: 100) - 0.5) < 0.001)
        check("scale.fraction.clamped", RelativeSizeScale.fraction(value: 200, of: 100) == 1)

        let parentURL = URL(fileURLWithPath: "/tmp/chet-scale-parent")
        let parent = FileNode(url: parentURL, name: "parent", isDirectory: true, category: .other)
        parent.size = 175

        let large = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-scale-parent/large"),
            name: "large",
            isDirectory: false,
            category: .documents
        )
        large.size = 100
        let medium = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-scale-parent/medium"),
            name: "medium",
            isDirectory: false,
            category: .images
        )
        medium.size = 50
        let small = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-scale-parent/small"),
            name: "small",
            isDirectory: false,
            category: .other
        )
        small.size = 25

        for child in [large, medium, small] { child.parent = parent }
        parent.children = [large, medium, small]

        check(
            "scale.sibling.largest",
            abs(large.relativeToSiblings - 1.0) < 0.001
        )
        check(
            "scale.sibling.medium",
            abs(medium.relativeToSiblings - 0.5) < 0.001
        )
        check(
            "scale.sibling.smallest",
            abs(small.relativeToSiblings - 0.25) < 0.001
        )
        check(
            "scale.parent.medium",
            abs(RelativeSizeScale.fractionOfParent(for: medium) - (50.0 / 175.0)) < 0.001
        )

        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let items = TreemapLayout.layout(nodes: [large, medium, small], in: rect)
        let canvasArea = Double(rect.width * rect.height)
        let layoutArea = items.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }

        check("treemap.itemCount", items.count == 3)
        check("treemap.fillsCanvas", abs(layoutArea - canvasArea) < canvasArea * 0.02)
        func rectArea(_ rect: CGRect) -> Double {
            Double(rect.width * rect.height)
        }
        let largeArea = rectArea(items.first(where: { $0.node.id == large.id })!.rect)
        let mediumArea = rectArea(items.first(where: { $0.node.id == medium.id })!.rect)
        let smallArea = rectArea(items.first(where: { $0.node.id == small.id })!.rect)
        check("treemap.proportionalOrder", largeArea > mediumArea && mediumArea > smallArea)

        for item in items {
            check(
                "treemap.bounds.\(item.node.name)",
                item.rect.minX >= -0.5
                    && item.rect.minY >= -0.5
                    && item.rect.maxX <= rect.width + 0.5
                    && item.rect.maxY <= rect.height + 0.5
            )
        }

        return failures
    }

    private static func runCleanupTests() -> Int {
        var failures = 0

        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        let derived = FileNode(
            url: URL(fileURLWithPath: "/Users/test/Library/Developer/Xcode/DerivedData"),
            name: "DerivedData",
            isDirectory: true,
            category: .xcodeApple
        )
        derived.size = 12_000_000_000
        let derivedImpact = DeletionImpactHeuristicAnalyzer.analyze(
            node: derived,
            rootPath: "/Users/test"
        )
        check("cleanup.derivedData.safe", derivedImpact.riskLevel == .safe)
        check("cleanup.derivedData.reclaimable", derivedImpact.reclaimableBytes == 12_000_000_000)

        let gitDir = FileNode(
            url: URL(fileURLWithPath: "/Users/test/project/.git"),
            name: ".git",
            isDirectory: true,
            category: .versionControl
        )
        gitDir.size = 500_000_000
        let gitImpact = DeletionImpactHeuristicAnalyzer.analyze(node: gitDir, rootPath: "/Users/test/project")
        check("cleanup.git.risky", gitImpact.riskLevel == .risky)

        let systemPath = FileNode(
            url: URL(fileURLWithPath: "/System/Library"),
            name: "Library",
            isDirectory: true,
            category: .other
        )
        systemPath.size = 1
        let systemImpact = DeletionImpactHeuristicAnalyzer.analyze(node: systemPath, rootPath: "/Users/test")
        check("cleanup.system.blocked", systemImpact.riskLevel == .blocked)
        check("cleanup.system.protected", DeletionImpactHeuristicAnalyzer.isProtectedSystemPath("/System/Library"))

        let root = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-cleanup-root"),
            name: "chet-cleanup-root",
            isDirectory: true,
            category: .other
        )
        root.size = 20_000_000

        let cacheDir = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-cleanup-root/.cache"),
            name: ".cache",
            isDirectory: true,
            category: .logsCache
        )
        cacheDir.size = 8_000_000
        cacheDir.parent = root

        let modules = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-cleanup-root/node_modules"),
            name: "node_modules",
            isDirectory: true,
            category: .packageDeps
        )
        modules.size = 15_000_000
        modules.parent = root

        let docs = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-cleanup-root/report.pdf"),
            name: "report.pdf",
            isDirectory: false,
            category: .documents
        )
        docs.size = 1_000_000
        docs.parent = root

        root.children = [modules, cacheDir, docs]

        let candidates = CleanupPlanner.findCandidates(in: root, limit: 5)
        check("cleanup.planner.found", !candidates.isEmpty)
        check(
            "cleanup.planner.prefersSafe",
            candidates.contains { $0.name == ".cache" && $0.riskLevel == .safe }
        )
        check(
            "cleanup.planner.totalBytes",
            CleanupPlanner.totalReclaimable(from: candidates) >= 8_000_000
        )
        check("cleanup.roadmap.phase", EnhancementRoadmap.currentPhase == "cleanup-workflows-v2")

        let cacheCandidate = candidates.first { $0.name == ".cache" }
        let modulesCandidate = candidates.first { $0.name == "node_modules" }
        check("cleanup.preset.caches", cacheCandidate.map { CleanupPreset.matchingIDs(in: candidates, preset: .caches).contains($0.id) } == true)
        check("cleanup.preset.buildEmpty", CleanupPreset.matchingIDs(in: candidates, preset: .buildOutput).isEmpty)
        let depsPresetIDs = CleanupPreset.matchingIDs(in: candidates, preset: .packageDeps)
        check("cleanup.preset.deps", modulesCandidate.map { depsPresetIDs.contains($0.id) } == true)

        let nested = CleanupBatchExecutor.collapseNestedSelections([
            "/tmp/root",
            "/tmp/root/.cache",
            "/tmp/other",
        ])
        check("cleanup.batch.collapseNested", nested == ["/tmp/root", "/tmp/other"])

        let project = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-cleanup-root/project"),
            name: "project",
            isDirectory: true,
            category: .sourceCode
        )
        project.size = 12_000_000
        project.parent = root
        let nestedCache = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-cleanup-root/project/.cache"),
            name: ".cache",
            isDirectory: true,
            category: .logsCache
        )
        nestedCache.size = 8_000_000
        nestedCache.parent = project
        project.children = [nestedCache]
        root.children = [modules, cacheDir, docs, project]

        let nestedCandidates = CleanupPlanner.findCandidates(in: root, limit: 10)
        let projectCandidate = nestedCandidates.first { $0.path.hasSuffix("/project") }
        let nestedCacheCandidate = nestedCandidates.first { $0.path.hasSuffix("/project/.cache") }
        if let projectCandidate, let nestedCacheCandidate {
            let nestedIDs: Set<UUID> = [projectCandidate.id, nestedCacheCandidate.id]
            let collapsedNested = CleanupSelection.collapsed(from: nestedCandidates, selectedIDs: nestedIDs)
            let nestedTally = CleanupSelection.tallyBytes(from: nestedCandidates, selectedIDs: nestedIDs)
            check("cleanup.batch.nestedCount", collapsedNested.count == 1)
            check("cleanup.batch.nestedTally", nestedTally == projectCandidate.size)
            print("LOGIC_DRIVE nested_bytes=\(nestedTally) collapsed=\(collapsedNested.count) raw=2")
        } else {
            check("cleanup.batch.nestedFixtures", false)
        }

        let cachePresetIDs = CleanupPreset.matchingIDs(in: candidates, preset: .caches)
        check(
            "cleanup.batch.totalReclaimable",
            CleanupPlanner.totalReclaimable(from: candidates.filter { cachePresetIDs.contains($0.id) }) >= 8_000_000
        )
        check("cleanup.analyzer.heuristic", {
            let impact = DeletionImpactHeuristicAnalyzer.analyze(node: cacheDir, rootPath: root.url.path)
            return impact.source == .heuristic && impact.allowsDeletion
        }())

        failures += MainActor.assumeIsolated {
            runCleanupSelectionTests(root: root)
        }

        return failures
    }

    @MainActor
    private static func runCleanupSelectionTests(root: FileNode) -> Int {
        var failures = 0

        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        let state = ScanState()
        state.installTestTree(root)
        state.refreshCleanupCandidates()
        check("cleanup.batch.selectionEmpty", state.selectedCleanupIDs.isEmpty)

        guard let cacheCandidate = state.cleanupCandidates.first(where: { $0.name == ".cache" }),
              let modulesCandidate = state.cleanupCandidates.first(where: { $0.name == "node_modules" })
        else {
            check("cleanup.batch.selectionFixtures", false)
            return failures + 1
        }

        state.toggleCleanupSelection(cacheCandidate.id)
        check("cleanup.batch.selectionToggle", state.selectedCleanupIDs.contains(cacheCandidate.id))
        check("cleanup.batch.tallySingle", state.selectedCleanupBytes == cacheCandidate.size)

        state.applyCleanupPreset(.packageDeps)
        check("cleanup.batch.presetDepsState", state.selectedCleanupIDs.contains(modulesCandidate.id))
        check("cleanup.batch.tallyPreset", state.selectedCleanupBytes == modulesCandidate.size)

        state.selectAllCleanupCandidates()
        check("cleanup.batch.selectAll", state.selectedCleanupIDs.count == state.cleanupCandidates.count)
        check("cleanup.batch.tallyAll", state.selectedCleanupBytes > 0)

        state.clearCleanupSelection()
        check("cleanup.batch.clearSelection", state.selectedCleanupIDs.isEmpty)

        state.toggleCleanupSelection(cacheCandidate.id)
        let pathKey = PathNormalizer.normalize(cacheCandidate.path)
        state.refreshCleanupCandidates()
        let cacheAfterRefresh = state.cleanupCandidates.first { PathNormalizer.normalize($0.path) == pathKey }
        check("cleanup.batch.refreshPreservesPath", cacheAfterRefresh.map { state.selectedCleanupIDs.contains($0.id) } == true)
        check("cleanup.batch.refreshNewUUID", cacheAfterRefresh.map { $0.id != cacheCandidate.id } == true)

        return failures
    }

    private static func runCleanupBatchAsyncTests() -> Int {
        final class ResultBox: @unchecked Sendable {
            var failures = 0
            var done = false
        }
        let box = ResultBox()

        Task { @MainActor in
            func batchCheck(_ name: String, _ condition: Bool) {
                if condition {
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name)")
                    box.failures += 1
                }
            }

            let root = FileNode(
                url: URL(fileURLWithPath: "/tmp/chet-batch-root"),
                name: "chet-batch-root",
                isDirectory: true,
                category: .other
            )
            root.size = 10_000_000

            let safeDir = FileNode(
                url: URL(fileURLWithPath: "/tmp/chet-batch-root/.cache"),
                name: ".cache",
                isDirectory: true,
                category: .logsCache
            )
            safeDir.size = 6_000_000
            safeDir.parent = root

            let riskyDir = FileNode(
                url: URL(fileURLWithPath: "/tmp/chet-batch-root/Documents"),
                name: "Documents",
                isDirectory: true,
                category: .documents
            )
            riskyDir.size = 7_000_000
            riskyDir.parent = root
            root.children = [safeDir, riskyDir]

            let plannerCandidates = CleanupPlanner.findCandidates(in: root, limit: 5)
            let safeCandidate = plannerCandidates.first { $0.name == ".cache" }
            let riskyCandidate = CleanupCandidate(
                path: riskyDir.url.path(percentEncoded: false),
                name: "Documents",
                size: riskyDir.size,
                category: .documents,
                riskLevel: .risky,
                reason: "Risky for test"
            )
            guard let safeCandidate else {
                batchCheck("cleanup.batch.asyncFixtures", false)
                box.done = true
                return
            }

            let pathIndex = FileNode.makePathIndex(from: root)
            final class BatchProbe: @unchecked Sendable {
                var progressTotals = [Int]()
                var cancelProgressCount = 0
            }
            let probe = BatchProbe()
            let work = CleanupSelection.collapsed(
                from: [safeCandidate, riskyCandidate],
                selectedIDs: Set([safeCandidate.id, riskyCandidate.id])
            )
            let batchResult = await CleanupBatchExecutor.trashItems(
                candidates: work,
                nodesByPath: pathIndex,
                isCancelled: { false },
                onProgress: { progress in
                    probe.progressTotals.append(progress.total)
                }
            )
            batchCheck("cleanup.batch.progressTotal", probe.progressTotals.allSatisfy { $0 == work.count })
            batchCheck("cleanup.batch.riskGateSkips", batchResult.failedCount >= 1)
            batchCheck("cleanup.batch.riskGateNoSuccessOnRisky", !batchResult.results.contains { $0.success && $0.path.hasSuffix("/Documents") })
            print("LOGIC_DRIVE progress_total=\(work.count) failed=\(batchResult.failedCount)")

            let cancelResult = await CleanupBatchExecutor.trashItems(
                candidates: work,
                nodesByPath: pathIndex,
                isCancelled: { probe.cancelProgressCount > 0 },
                onProgress: { _ in probe.cancelProgressCount += 1 }
            )
            batchCheck("cleanup.batch.cancelFlag", cancelResult.wasCancelled)
            print("LOGIC_DRIVE cancel_wasCancelled=\(cancelResult.wasCancelled)")

            let state = ScanState()
            state.installTestTree(root)
            state.refreshCleanupCandidates()
            guard let selectable = state.cleanupCandidates.first(where: { $0.name == ".cache" }) else {
                batchCheck("cleanup.batch.startFixtures", false)
                box.done = true
                return
            }
            state.toggleCleanupSelection(selectable.id)
            batchCheck("cleanup.batch.startPreTotal", state.cleanupBatchProgress.total == 0)
            state.startBatchCleanup()
            batchCheck("cleanup.batch.startInitialTotal", state.cleanupBatchProgress.total == state.collapsedSelectionCount)

            for _ in 0..<400 {
                if !state.isBatchCleaning { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            batchCheck("cleanup.batch.startCompletes", !state.isBatchCleaning)
            print("LOGIC_DRIVE startBatch_completed=true final_total=\(state.cleanupBatchProgress.total)")

            box.done = true
        }

        let deadline = Date(timeIntervalSinceNow: 8)
        while !box.done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if !box.done {
            print("FAIL cleanup.batch.asyncTimeout")
            box.failures += 1
        }

        return box.failures
    }

    private static func runLiveUpdateQueueTests() -> Int {
        final class ResultBox: @unchecked Sendable {
            var failures = 0
            var done = false
        }
        let box = ResultBox()

        Task { @MainActor in
            func queueCheck(_ name: String, _ condition: Bool) {
                if condition {
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name)")
                    box.failures += 1
                }
            }

            var processedBatches: [[String]] = []
            let queue = LiveUpdateQueue { paths in
                processedBatches.append(paths.sorted())
                try? await Task.sleep(nanoseconds: 30_000_000)
            }

            queue.enqueue(paths: ["/tmp/a"])
            queue.enqueue(paths: ["/tmp/b", "/tmp/c"])

            for _ in 0..<200 {
                if !queue.isDraining && queue.pendingCount == 0 { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            let allPaths = processedBatches.flatMap { $0 }
            queueCheck("liveQueue.allPathsProcessed", Set(allPaths) == ["/tmp/a", "/tmp/b", "/tmp/c"])
            queueCheck("liveQueue.eachPathOnce", allPaths.count == 3)
            queueCheck("liveQueue.completed", !queue.isDraining && queue.pendingCount == 0)

            var coalesceBatches: [[String]] = []
            let coalesceQueue = LiveUpdateQueue { paths in
                coalesceBatches.append(paths.sorted())
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            coalesceQueue.enqueue(paths: ["/tmp/x"])
            try? await Task.sleep(nanoseconds: 5_000_000)
            coalesceQueue.enqueue(paths: ["/tmp/y"])

            for _ in 0..<200 {
                if !coalesceQueue.isDraining && coalesceQueue.pendingCount == 0 { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            let coalescedPaths = coalesceBatches.flatMap { $0 }
            queueCheck("liveQueue.coalesce.allPaths", Set(coalescedPaths) == ["/tmp/x", "/tmp/y"])
            queueCheck("liveQueue.coalesce.eachOnce", coalescedPaths.count == 2)

            var latePaths: [String] = []
            final class LateQueueHolder { var queue: LiveUpdateQueue! }
            let lateHolder = LateQueueHolder()
            lateHolder.queue = LiveUpdateQueue { paths in
                latePaths.append(contentsOf: paths)
                if paths.contains("/tmp/during") {
                    lateHolder.queue.enqueue(paths: ["/tmp/after-drain"])
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            lateHolder.queue.enqueue(paths: ["/tmp/during"])

            for _ in 0..<200 {
                if !lateHolder.queue.isDraining && lateHolder.queue.pendingCount == 0 { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            queueCheck("liveQueue.lateEnqueue.processed", Set(latePaths) == ["/tmp/during", "/tmp/after-drain"])
            queueCheck(
                "liveQueue.lateEnqueue.completed",
                !lateHolder.queue.isDraining && lateHolder.queue.pendingCount == 0
            )

            box.done = true
        }

        let deadline = Date(timeIntervalSinceNow: 6)
        while !box.done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if !box.done {
            print("FAIL liveQueue.timeout")
            box.failures += 1
        }

        return box.failures
    }

    private static func runScanStateIntegrationTests() -> Int {
        final class ResultBox: @unchecked Sendable {
            var failures = 0
            var done = false
        }
        let box = ResultBox()

        Task { @MainActor in
            func integrationCheck(_ name: String, _ condition: Bool) {
                if condition {
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name)")
                    box.failures += 1
                }
            }

            let state = ScanState()
            let rootURL = URL(fileURLWithPath: "/tmp/chet-test-root")
            let root = FileNode(url: rootURL, name: "chet-test-root", isDirectory: true, category: .other)
            let childURL = URL(fileURLWithPath: "/tmp/chet-test-root/subdir")
            let child = FileNode(url: childURL, name: "subdir", isDirectory: true, category: .other)
            child.parent = root
            root.children = [child]
            state.installTestTree(root)

            integrationCheck(
                "scanState.directoryLookup.trailingSlash",
                state.directoryNode(forPath: "/tmp/chet-test-root/subdir/")?.id == child.id
            )
            integrationCheck(
                "scanState.directoryLookup.noSlash",
                state.directoryNode(forPath: "/tmp/chet-test-root/subdir")?.id == child.id
            )

            var notified = false
            let mutationBefore = state.lastTreeMutation
            let queue = LiveUpdateQueue { paths in
                integrationCheck("scanState.liveQueue.normalized", paths == ["/tmp/chet-test-root/subdir"])
                if let node = state.directoryNode(forPath: paths[0]) {
                    node.size += 1024
                    state.lastTreeMutation = Date()
                    notified = true
                }
            }

            queue.enqueue(paths: ["/tmp/chet-test-root/subdir/"])

            for _ in 0..<200 {
                if !queue.isDraining && queue.pendingCount == 0 { break }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            integrationCheck("scanState.liveQueue.notify", notified)
            integrationCheck("scanState.liveQueue.mutation", state.lastTreeMutation > mutationBefore)
            integrationCheck("scanState.liveQueue.completed", !queue.isDraining && queue.pendingCount == 0)

            let sidebarState = ScanState()
            let sidebarRootURL = URL(fileURLWithPath: "/tmp/chet-sidebar-root")
            let sidebarRoot = FileNode(
                url: sidebarRootURL, name: "sidebar-root", isDirectory: true, category: .other
            )
            let sidebarDirURL = URL(fileURLWithPath: "/tmp/chet-sidebar-root/nested")
            let sidebarDir = FileNode(
                url: sidebarDirURL, name: "nested", isDirectory: true, category: .other
            )
            let sidebarFileURL = URL(fileURLWithPath: "/tmp/chet-sidebar-root/nested/readme.txt")
            let sidebarFile = FileNode(
                url: sidebarFileURL, name: "readme.txt", isDirectory: false, category: .documents
            )
            sidebarDir.parent = sidebarRoot
            sidebarFile.parent = sidebarDir
            sidebarDir.children = [sidebarFile]
            sidebarRoot.children = [sidebarDir]
            sidebarState.installTestTree(sidebarRoot)

            integrationCheck(
                "sidebar.select.directory.updatesTreemapRoot",
                {
                    sidebarState.selectInSidebar(sidebarDir)
                    return sidebarState.treemapRoot?.id == sidebarDir.id
                        && sidebarState.displayRoot?.id == sidebarDir.id
                        && sidebarState.selectedNode?.id == sidebarDir.id
                }()
            )

            integrationCheck(
                "sidebar.select.file.preservesTreemapRoot",
                {
                    sidebarState.selectInSidebar(sidebarFile)
                    return sidebarState.treemapRoot?.id == sidebarDir.id
                        && sidebarState.displayRoot?.id == sidebarDir.id
                        && sidebarState.selectedNode?.id == sidebarFile.id
                }()
            )

            box.done = true
        }

        let deadline = Date(timeIntervalSinceNow: 5)
        while !box.done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if !box.done {
            print("FAIL scanState.integration.timeout")
            box.failures += 1
        }

        return box.failures
    }

    private static func runPopulationTests() -> Int {
        var failures = 0

        func populationCheck(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        let parent = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-sort-parent"),
            name: "parent",
            isDirectory: true,
            category: .other
        )
        let small = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-sort-parent/small.txt"),
            name: "small.txt",
            isDirectory: false,
            category: .documents
        )
        small.size = 100
        let large = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-sort-parent/large.txt"),
            name: "large.txt",
            isDirectory: false,
            category: .documents
        )
        large.size = 5000
        parent.children = [small, large]
        parent.sortChildrenBySize()

        populationCheck("population.sortChildren.ordersBySize", parent.children.first?.id == large.id)
        populationCheck("population.sortedChildren.noResort", parent.sortedChildren.first?.id == large.id)
        populationCheck("population.childrenSorted.invariant", FileNode.childrenAreSortedBySize(parent.children))

        let nestedRoot = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-nested-root"),
            name: "nested-root",
            isDirectory: true,
            category: .other
        )
        let nestedDir = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-nested-root/sub"),
            name: "sub",
            isDirectory: true,
            category: .other
        )
        nestedDir.parent = nestedRoot
        let nestedSmall = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-nested-root/sub/a"),
            name: "a",
            isDirectory: false,
            category: .other
        )
        nestedSmall.size = 10
        let nestedLarge = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-nested-root/sub/b"),
            name: "b",
            isDirectory: false,
            category: .other
        )
        nestedLarge.size = 1000
        nestedDir.children = [nestedSmall, nestedLarge]
        nestedRoot.children = [nestedDir]
        FileNode.sortTreeChildrenBySize(from: nestedRoot)

        populationCheck("population.sortTree.nestedSorted", FileNode.childrenAreSortedBySize(nestedDir.children))

        let indexRoot = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-index-root"),
            name: "index-root",
            isDirectory: true,
            category: .other
        )
        let indexChild = FileNode(
            url: URL(fileURLWithPath: "/tmp/chet-index-root/child"),
            name: "child",
            isDirectory: true,
            category: .other
        )
        indexChild.parent = indexRoot
        indexRoot.children = [indexChild]
        let pathIndex = FileNode.makePathIndex(from: indexRoot)

        populationCheck(
            "population.makePathIndex.lookup",
            pathIndex["/tmp/chet-index-root/child"]?.id == indexChild.id
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chet-scan-sort-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tempDir.appendingPathComponent("small.txt").path, contents: Data(count: 64))
            FileManager.default.createFile(atPath: tempDir.appendingPathComponent("large.txt").path, contents: Data(count: 4096))

            var seenInodes = Set<UInt64>()
            let scanner = DiskScanner()
            let scannedChildren = scanner.scanDirectory(at: tempDir, seenInodes: &seenInodes)
            populationCheck(
                "population.scanDirectory.sorted",
                FileNode.childrenAreSortedBySize(scannedChildren)
            )
            try? FileManager.default.removeItem(at: tempDir)
        } catch {
            populationCheck("population.scanDirectory.sorted", false)
            try? FileManager.default.removeItem(at: tempDir)
        }

        return failures
    }

    private static func runPopulationPathTests() -> Int {
        final class ResultBox: @unchecked Sendable {
            var failures = 0
            var done = false
        }
        let box = ResultBox()

        Task { @MainActor in
            func pathCheck(_ name: String, _ condition: Bool) {
                if condition {
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name)")
                    box.failures += 1
                }
            }

            let rootURL = URL(fileURLWithPath: "/tmp/chet-apply-root")
            let root = FileNode(url: rootURL, name: "apply-root", isDirectory: true, category: .other)
            let dirA = FileNode(
                url: URL(fileURLWithPath: "/tmp/chet-apply-root/a"),
                name: "a",
                isDirectory: true,
                category: .other
            )
            let dirB = FileNode(
                url: URL(fileURLWithPath: "/tmp/chet-apply-root/b"),
                name: "b",
                isDirectory: true,
                category: .other
            )
            dirA.size = 1000
            dirB.size = 5000
            dirA.parent = root
            dirB.parent = root
            root.children = [dirB, dirA]
            root.size = 6000

            let applyState = ScanState()
            applyState.installTestTree(root)

            let bigFile = FileNode(
                url: URL(fileURLWithPath: "/tmp/chet-apply-root/a/huge.bin"),
                name: "huge.bin",
                isDirectory: false,
                category: .other
            )
            bigFile.size = 20_000
            bigFile.fileCount = 1
            dirA.size = 20_000
            dirA.fileCount = 1

            await applyState.applyPopulationDiff(
                forTesting: dirA,
                newChildren: [bigFile],
                rootPath: "/tmp/chet-apply-root"
            )

            pathCheck(
                "population.applyDiff.ancestorResort",
                root.children.first?.id == dirA.id && FileNode.childrenAreSortedBySize(root.children)
            )
            pathCheck(
                "population.applyDiff.dirSorted",
                FileNode.childrenAreSortedBySize(dirA.children)
            )

            let newDirParentPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("chet-newdir-apply-\(UUID().uuidString)", isDirectory: true).path
            do {
                try FileManager.default.createDirectory(
                    atPath: newDirParentPath,
                    withIntermediateDirectories: true
                )
                let newSubPath = (newDirParentPath as NSString).appendingPathComponent("newsubdir")
                try FileManager.default.createDirectory(atPath: newSubPath, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: (newSubPath as NSString).appendingPathComponent("inside.txt"),
                    contents: Data(count: 4096)
                )

                let parentNode = FileNode(
                    url: URL(fileURLWithPath: newDirParentPath, isDirectory: true),
                    name: (newDirParentPath as NSString).lastPathComponent,
                    isDirectory: true,
                    category: .other
                )
                let newDirState = ScanState()
                newDirState.installTestTree(parentNode)
                newDirState.cacheLoaded = true
                _ = ScanCache.shared.open()

                var seenForNew = Set<UInt64>()
                let stubs = DiskScanner().scanDirectory(
                    at: URL(fileURLWithPath: newDirParentPath, isDirectory: true),
                    seenInodes: &seenForNew
                )
                pathCheck("population.applyDiff.newDir.stubFound", stubs.contains { $0.name == "newsubdir" })

                await newDirState.applyPopulationDiff(
                    forTesting: parentNode,
                    newChildren: stubs,
                    rootPath: ScanState.normalizePath(newDirParentPath)
                )

                if let addedDir = parentNode.children.first(where: { $0.name == "newsubdir" }) {
                    pathCheck("population.applyDiff.newDir.expanded", !addedDir.children.isEmpty)
                    let cachedKids = ScanCache.shared.loadChildren(
                        forPath: addedDir.url.path(percentEncoded: false)
                    )
                    pathCheck("population.applyDiff.newDir.cacheRows", !cachedKids.isEmpty)
                    newDirState.drillInto(addedDir)
                    pathCheck("population.applyDiff.newDir.drillChildren", !addedDir.children.isEmpty)
                    pathCheck(
                        "population.applyDiff.newDir.drillSorted",
                        FileNode.childrenAreSortedBySize(addedDir.children)
                    )
                } else {
                    pathCheck("population.applyDiff.newDir.expanded", false)
                    pathCheck("population.applyDiff.newDir.cacheRows", false)
                    pathCheck("population.applyDiff.newDir.drillChildren", false)
                }

                try? FileManager.default.removeItem(atPath: newDirParentPath)
            } catch {
                pathCheck("population.applyDiff.newDir.setup", false)
                try? FileManager.default.removeItem(atPath: newDirParentPath)
            }

            let cacheRootPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("chet-cache-pop-\(UUID().uuidString)", isDirectory: true).path
            do {
                try FileManager.default.createDirectory(
                    atPath: cacheRootPath,
                    withIntermediateDirectories: true
                )
                let subPath = (cacheRootPath as NSString).appendingPathComponent("nested")
                try FileManager.default.createDirectory(atPath: subPath, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: (subPath as NSString).appendingPathComponent("small.txt"),
                    contents: Data(count: 128)
                )
                FileManager.default.createFile(
                    atPath: (subPath as NSString).appendingPathComponent("large.txt"),
                    contents: Data(count: 8192)
                )
                let innerSub = (subPath as NSString).appendingPathComponent("inner")
                try FileManager.default.createDirectory(atPath: innerSub, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: (innerSub as NSString).appendingPathComponent("inner.txt"),
                    contents: Data(count: 2048)
                )

                let scanner = DiskScanner()
                let scannedRoot = scanner.scan(url: URL(fileURLWithPath: cacheRootPath)) { _, _ in }
                let normalizedRoot = ScanState.normalizePath(cacheRootPath)
                let cache = ScanCache.shared
                _ = cache.open()
                cache.saveTree(scannedRoot, rootPath: normalizedRoot, eventID: 1)

                let loadState = ScanState()
                pathCheck("population.loadFromCache.found", loadState.loadFromCache(rootPath: normalizedRoot))
                pathCheck("population.loadFromCache.rootSet", loadState.rootNode != nil)
                pathCheck("population.loadFromCache.displayRoot", loadState.displayRoot?.id == loadState.rootNode?.id)
                pathCheck(
                    "population.loadFromCache.childrenSorted",
                    loadState.rootNode.map { FileNode.childrenAreSortedBySize($0.children) } ?? false
                )

                guard let shallow = cache.loadTree(for: normalizedRoot, maxDepth: 1) else {
                    pathCheck("population.drillInto.shallowLoad", false)
                    try? FileManager.default.removeItem(atPath: cacheRootPath)
                    box.done = true
                    return
                }
                let (shallowRoot, _) = shallow
                let drillState = ScanState()
                drillState.rootNode = shallowRoot
                drillState.treemapRoot = shallowRoot
                drillState.cacheLoaded = true

                guard let nestedDir = shallowRoot.children.first(where: { $0.isDirectory }) else {
                    pathCheck("population.drillInto.nestedDir", false)
                    try? FileManager.default.removeItem(atPath: cacheRootPath)
                    box.done = true
                    return
                }

                pathCheck(
                    "population.drillInto.lazyPrecondition",
                    nestedDir.children.isEmpty && nestedDir.fileCount > 0
                )
                drillState.drillInto(nestedDir)
                pathCheck("population.drillInto.loadedChildren", !nestedDir.children.isEmpty)
                pathCheck(
                    "population.drillInto.childrenSorted",
                    FileNode.childrenAreSortedBySize(nestedDir.children)
                )
                pathCheck(
                    "population.drillInto.largestFirst",
                    (nestedDir.children.first?.name ?? "").contains("large")
                )

                var seenInodes = Set<UInt64>()
                let scannedChildren = scanner.scanDirectory(
                    at: URL(fileURLWithPath: subPath, isDirectory: true),
                    seenInodes: &seenInodes
                )
                pathCheck(
                    "population.scanDirectory.dirHasSize",
                    scannedChildren.contains { $0.isDirectory && $0.size > 0 }
                )
                pathCheck(
                    "population.scanDirectory.dirsRankBySize",
                    FileNode.childrenAreSortedBySize(scannedChildren)
                        && (scannedChildren.first?.size ?? 0) >= (scannedChildren.last?.size ?? 0)
                )

                try? FileManager.default.removeItem(atPath: cacheRootPath)
            } catch {
                pathCheck("population.cachePath.setup", false)
                try? FileManager.default.removeItem(atPath: cacheRootPath)
            }

            box.done = true
        }

        let deadline = Date(timeIntervalSinceNow: 10)
        while !box.done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if !box.done {
            print("FAIL population.path.timeout")
            box.failures += 1
        }

        return box.failures
    }

    /// Saving or loading `/tmp/foo` must not touch `/tmp/foobar`, and `a_b` must not match `axb`.
    private static func runCachePrefixTests() -> Int {
        var failures = 0

        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        func names(in node: FileNode) -> Set<String> {
            var found = Set<String>()
            var stack = [node]
            while let current = stack.popLast() {
                found.insert(current.name)
                stack.append(contentsOf: current.children)
            }
            return found
        }

        func tree(path: String, childName: String) -> FileNode {
            let root = FileNode(
                url: URL(fileURLWithPath: path, isDirectory: true),
                name: (path as NSString).lastPathComponent,
                isDirectory: true,
                category: .other
            )
            let child = FileNode(
                url: URL(fileURLWithPath: (path as NSString).appendingPathComponent(childName)),
                name: childName,
                isDirectory: false,
                category: .documents
            )
            child.size = 64
            child.fileCount = 1
            child.parent = root
            root.children = [child]
            root.size = 64
            root.fileCount = 1
            return root
        }

        let cache = ScanCache.shared
        guard cache.open() else {
            check("cache.prefix.open", false)
            return failures
        }

        let token = UUID().uuidString
        let base = (NSTemporaryDirectory() as NSString).appendingPathComponent("chet-cache-prefix-\(token)")
        let shortPath = (base as NSString).appendingPathComponent("foo")
        let siblingPath = (base as NSString).appendingPathComponent("foobar")
        let underPath = (base as NSString).appendingPathComponent("a_b")
        let wildPath = (base as NSString).appendingPathComponent("axb")
        let roots = [shortPath, siblingPath, underPath, wildPath]
        defer {
            for path in roots {
                cache.removeCachedScan(rootPath: path)
            }
        }

        cache.saveTree(tree(path: shortPath, childName: "short-marker.txt"), rootPath: shortPath, eventID: 1)
        cache.saveTree(tree(path: siblingPath, childName: "sibling-marker.txt"), rootPath: siblingPath, eventID: 1)
        cache.saveTree(tree(path: underPath, childName: "under-marker.txt"), rootPath: underPath, eventID: 1)
        cache.saveTree(tree(path: wildPath, childName: "wild-marker.txt"), rootPath: wildPath, eventID: 1)

        if let (loadedShort, _) = cache.loadTree(for: shortPath, maxDepth: 4) {
            let loadedNames = names(in: loadedShort)
            check("cache.prefix.keepsOwnChild", loadedNames.contains("short-marker.txt"))
            check("cache.prefix.excludesSibling", !loadedNames.contains("sibling-marker.txt"))
        } else {
            check("cache.prefix.loadShort", false)
        }

        if let (loadedUnder, _) = cache.loadTree(for: underPath, maxDepth: 4) {
            let loadedNames = names(in: loadedUnder)
            check("cache.prefix.underscoreOwn", loadedNames.contains("under-marker.txt"))
            check("cache.prefix.underscoreExcludesWild", !loadedNames.contains("wild-marker.txt"))
        } else {
            check("cache.prefix.underscoreLoad", false)
        }

        cache.saveTree(tree(path: shortPath, childName: "short-marker.txt"), rootPath: shortPath, eventID: 2)
        cache.saveTree(tree(path: underPath, childName: "under-marker.txt"), rootPath: underPath, eventID: 2)

        if let (sibling, _) = cache.loadTree(for: siblingPath, maxDepth: 4) {
            check("cache.prefix.resaveKeepsSibling", names(in: sibling).contains("sibling-marker.txt"))
        } else {
            check("cache.prefix.resaveKeepsSibling", false)
        }
        if let (wild, _) = cache.loadTree(for: wildPath, maxDepth: 4) {
            check("cache.prefix.resaveKeepsWildcardSibling", names(in: wild).contains("wild-marker.txt"))
        } else {
            check("cache.prefix.resaveKeepsWildcardSibling", false)
        }

        cache.deleteSubtree(path: shortPath)
        if let (siblingAfterDelete, _) = cache.loadTree(for: siblingPath, maxDepth: 4) {
            check(
                "cache.prefix.deleteSubtreeKeepsSibling",
                names(in: siblingAfterDelete).contains("sibling-marker.txt")
            )
        } else {
            check("cache.prefix.deleteSubtreeKeepsSibling", false)
        }

        return failures
    }

    /// Directory upserts must keep the row id, every merged directory must be written,
    /// and a volume-root scan must match descendants of `/`.
    private static func runCacheReloadTests() -> Int {
        final class ResultBox: @unchecked Sendable {
            var failures = 0
            var done = false
        }
        let box = ResultBox()

        Task { @MainActor in
            func check(_ name: String, _ condition: Bool) {
                if condition {
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name)")
                    box.failures += 1
                }
            }

            func find(_ name: String, in node: FileNode) -> FileNode? {
                if node.name == name { return node }
                for child in node.children {
                    if let found = find(name, in: child) { return found }
                }
                return nil
            }

            func directory(path: String, name: String, size: Int64) -> FileNode {
                let node = FileNode(
                    url: URL(fileURLWithPath: path, isDirectory: true),
                    name: name,
                    isDirectory: true,
                    category: .other
                )
                node.size = size
                return node
            }

            func file(path: String, name: String, size: Int64) -> FileNode {
                let node = FileNode(
                    url: URL(fileURLWithPath: path),
                    name: name,
                    isDirectory: false,
                    category: .documents
                )
                node.size = size
                node.fileCount = 1
                return node
            }

            let cache = ScanCache.shared
            guard cache.open() else {
                check("cache.reload.open", false)
                box.done = true
                return
            }

            let token = UUID().uuidString
            let base = (NSTemporaryDirectory() as NSString).appendingPathComponent("chet-cache-reload-\(token)")
            let parentPath = (base as NSString).appendingPathComponent("parent")
            let childPath = (parentPath as NSString).appendingPathComponent("kept.txt")
            let projPath = (base as NSString).appendingPathComponent("proj")
            let readmePath = (projPath as NSString).appendingPathComponent("README")
            let srcPath = (projPath as NSString).appendingPathComponent("src")
            let mainPath = (srcPath as NSString).appendingPathComponent("main.swift")
            let batchPath = (base as NSString).appendingPathComponent("batch")
            let dirAPath = (batchPath as NSString).appendingPathComponent("dirA")
            let dirBPath = (batchPath as NSString).appendingPathComponent("dirB")
            defer {
                for path in [parentPath, projPath, batchPath] {
                    cache.removeCachedScan(rootPath: path)
                }
            }

            let parent = directory(path: parentPath, name: "parent", size: 40)
            let kept = file(path: childPath, name: "kept.txt", size: 40)
            kept.parent = parent
            parent.children = [kept]
            parent.fileCount = 1
            cache.saveTree(parent, rootPath: parentPath, eventID: 1)
            parent.size = 80
            var parentWork = DiffCacheWork()
            parentWork.recordUpsertDirectory(parent, parentPath: nil)
            parentWork.persist()
            if let (reloadedParent, _) = cache.loadTree(for: parentPath, maxDepth: 4) {
                let keptNode = find("kept.txt", in: reloadedParent)
                check("cache.reload.parentIsRoot", reloadedParent.name == "parent")
                check("cache.reload.childStaysUnderParent", keptNode?.parent?.name == "parent")
            } else {
                check("cache.reload.parentIsRoot", false)
                check("cache.reload.childStaysUnderParent", false)
            }

            let project = directory(path: projPath, name: "proj", size: 150)
            let readme = file(path: readmePath, name: "README", size: 100)
            let src = directory(path: srcPath, name: "src", size: 50)
            let mainFile = file(path: mainPath, name: "main.swift", size: 50)
            readme.parent = project
            src.parent = project
            mainFile.parent = src
            src.children = [mainFile]
            src.fileCount = 1
            project.children = [readme, src]
            project.fileCount = 2
            cache.saveTree(project, rootPath: projPath, eventID: 1)

            readme.size = 400
            let state = ScanState()
            state.installTestTree(project)
            await state.applyPopulationDiff(
                forTesting: project,
                newChildren: [readme, src],
                rootPath: projPath
            )
            if let (reloadedProj, _) = cache.loadTree(for: projPath, maxDepth: 6) {
                let readmeNode = find("README", in: reloadedProj)
                let srcNode = find("src", in: reloadedProj)
                let mainNode = find("main.swift", in: reloadedProj)
                check("cache.reload.projRoot", reloadedProj.name == "proj")
                check("cache.reload.readmeStays", readmeNode?.parent?.name == "proj")
                check("cache.reload.srcStays", srcNode?.parent?.name == "proj")
                check("cache.reload.grandchildStays", mainNode?.parent?.name == "src")
            } else {
                check("cache.reload.projRoot", false)
                check("cache.reload.readmeStays", false)
                check("cache.reload.srcStays", false)
                check("cache.reload.grandchildStays", false)
            }

            let batchRoot = directory(path: batchPath, name: "batch", size: 30)
            let dirA = directory(path: dirAPath, name: "dirA", size: 10)
            let dirB = directory(path: dirBPath, name: "dirB", size: 20)
            let markerA = file(path: (dirAPath as NSString).appendingPathComponent("a.txt"), name: "a.txt", size: 10)
            let markerB = file(path: (dirBPath as NSString).appendingPathComponent("b.txt"), name: "b.txt", size: 20)
            markerA.parent = dirA
            markerB.parent = dirB
            dirA.children = [markerA]
            dirB.children = [markerB]
            dirA.fileCount = 1
            dirB.fileCount = 1
            dirA.parent = batchRoot
            dirB.parent = batchRoot
            batchRoot.children = [dirA, dirB]
            batchRoot.fileCount = 2
            cache.saveTree(batchRoot, rootPath: batchPath, eventID: 1)

            dirA.size = 111
            dirB.size = 222
            let batchRootPath = batchRoot.url.path(percentEncoded: false)
            var workA = DiffCacheWork()
            workA.recordUpsertDirectory(dirA, parentPath: batchRootPath)
            var workB = DiffCacheWork()
            workB.recordUpsertDirectory(dirB, parentPath: batchRootPath)
            var merged = DiffCacheWork()
            merged.merge(workA)
            merged.merge(workB)
            merged.persist()
            if let (reloadedBatch, _) = cache.loadTree(for: batchPath, maxDepth: 4) {
                let loadedA = find("dirA", in: reloadedBatch)
                let loadedB = find("dirB", in: reloadedBatch)
                check("cache.reload.mergeDirA", loadedA?.size == 111 && loadedA?.parent?.name == "batch")
                check("cache.reload.mergeDirB", loadedB?.size == 222 && loadedB?.parent?.name == "batch")
                check("cache.reload.mergeChildA", find("a.txt", in: reloadedBatch)?.parent?.name == "dirA")
                check("cache.reload.mergeChildB", find("b.txt", in: reloadedBatch)?.parent?.name == "dirB")
            } else {
                check("cache.reload.mergeDirA", false)
                check("cache.reload.mergeDirB", false)
                check("cache.reload.mergeChildA", false)
                check("cache.reload.mergeChildB", false)
            }

            let volumeDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("chet-volume-cache-\(token)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: volumeDir, withIntermediateDirectories: true)
                let volumeCache = ScanCache(databaseFileURL: volumeDir.appendingPathComponent("scans.db"))
                if volumeCache.open() {
                    let volume = directory(path: "/", name: "/", size: 70)
                    let users = directory(path: "/Users", name: "Users", size: 70)
                    let probe = file(path: "/Users/chet-volume-probe", name: "chet-volume-probe", size: 70)
                    probe.parent = users
                    users.children = [probe]
                    users.fileCount = 1
                    users.parent = volume
                    volume.children = [users]
                    volume.fileCount = 1
                    volumeCache.saveTree(volume, rootPath: "/", eventID: 1)
                    if let (loadedVolume, _) = volumeCache.loadTree(for: "/", maxDepth: 4) {
                        check("cache.root.loadRoot", loadedVolume.url.path(percentEncoded: false) == "/")
                        check(
                            "cache.root.loadChild",
                            find("chet-volume-probe", in: loadedVolume)?.parent?.name == "Users"
                        )
                    } else {
                        check("cache.root.loadRoot", false)
                        check("cache.root.loadChild", false)
                    }

                    volumeCache.deleteSubtree(path: "/")
                    let replacement = directory(path: "/", name: "/", size: 9)
                    let second = file(path: "/Users/chet-volume-second", name: "chet-volume-second", size: 9)
                    second.parent = replacement
                    replacement.children = [second]
                    replacement.fileCount = 1
                    volumeCache.saveTree(replacement, rootPath: "/", eventID: 2)
                    if let (afterDelete, _) = volumeCache.loadTree(for: "/", maxDepth: 4) {
                        let names = find("chet-volume-probe", in: afterDelete)
                        check("cache.root.deleteDropsOldChild", names == nil)
                        check(
                            "cache.root.deleteKeepsNewChild",
                            find("chet-volume-second", in: afterDelete)?.parent?.url.path(percentEncoded: false) == "/"
                        )
                    } else {
                        check("cache.root.deleteDropsOldChild", false)
                        check("cache.root.deleteKeepsNewChild", false)
                    }
                } else {
                    check("cache.root.open", false)
                }
                volumeCache.close()
                try? FileManager.default.removeItem(at: volumeDir)
            } catch {
                check("cache.root.setup", false)
                try? FileManager.default.removeItem(at: volumeDir)
            }

            box.done = true
        }

        let deadline = Date(timeIntervalSinceNow: 8)
        while !box.done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        if !box.done {
            print("FAIL cache.reload.timeout")
            box.failures += 1
        }
        return box.failures
    }
}