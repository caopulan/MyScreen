import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var permissionStatus: ScreenCapturePermissionStatus
    var selectedSources: [MonitorSource]
    var sourceCatalog: SourceCatalog
    var tiles: [String: TileState]
    var wallLayout: WallLayoutState
    var isPermissionRequestInFlight = false
    var isSourcePickerPresented = false
    var isRefreshingSourceCatalog = false
    var sourceCatalogError: String?

    private let permissionService: ScreenCapturePermissionService
    private let sourceCatalogService: SourceCatalogService
    private let windowActivationService: WindowActivationService
    private let snapshotStore: WallSessionSnapshotStore
    private let captureCoordinator: CaptureCoordinator
    private var captureSyncTask: Task<Void, Never>?
    private var catalogRefreshTask: Task<Void, Never>?
    private var freshnessSweepTask: Task<Void, Never>?

    init(
        permissionService: ScreenCapturePermissionService = ScreenCapturePermissionService(),
        sourceCatalogService: SourceCatalogService = SourceCatalogService(),
        windowActivationService: WindowActivationService = WindowActivationService(),
        captureCoordinator: CaptureCoordinator = CaptureCoordinator(),
        snapshotStore: WallSessionSnapshotStore = WallSessionSnapshotStore()
    ) {
        self.permissionService = permissionService
        self.sourceCatalogService = sourceCatalogService
        self.windowActivationService = windowActivationService
        self.captureCoordinator = captureCoordinator
        self.snapshotStore = snapshotStore

        let snapshot = snapshotStore.load() ?? .empty
        self.permissionStatus = permissionService.currentStatus()
        self.selectedSources = snapshot.selectedSources
        self.sourceCatalog = .empty
        self.wallLayout = WallLayoutState(
            activeSourceIDs: snapshot.selectedSources.map(\.id),
            focusedSourceID: snapshot.focusedSourceID,
            grid: WallGridCalculator.calculate(
                for: snapshot.selectedSources.count,
                in: snapshot.windowSize.cgSize,
                preferredColumnCount: snapshot.preferredColumnCount
            ),
            windowSize: snapshot.windowSize,
            preferredColumnCount: snapshot.preferredColumnCount
        )
        self.tiles = Dictionary(
            uniqueKeysWithValues: snapshot.selectedSources.map { source in
                (
                    source.id,
                    TileState.placeholder(
                        sourceID: source.id,
                        fpsTier: .balanced,
                        freshness: source.isAvailable ? .stale : .offline,
                        lastFrameAt: source.lastSeenAt
                    )
                )
            }
        )

        self.captureCoordinator.onFrame = { [weak self] sourceID, frame, tier in
            self?.applyFrame(sourceID: sourceID, frame: frame, tier: tier)
        }
        self.captureCoordinator.onError = { [weak self] sourceID, message in
            self?.applyError(sourceID: sourceID, message: message)
        }
        self.captureCoordinator.onOffline = { [weak self] sourceID in
            self?.applyOffline(sourceID: sourceID)
        }
    }

    func bootstrap() async {
        permissionStatus = permissionService.currentStatus()
        ensureTileStateCoverage()
        guard permissionStatus == .granted else {
            stopCatalogAutoRefresh()
            stopFreshnessSweep()
            scheduleCaptureSync()
            return
        }
        startCatalogAutoRefresh()
        startFreshnessSweep()
        await refreshSourceCatalog()
    }

    func requestScreenCapturePermission() async {
        guard !isPermissionRequestInFlight else { return }
        isPermissionRequestInFlight = true
        permissionStatus = await permissionService.requestAccess()
        isPermissionRequestInFlight = false
        guard permissionStatus == .granted else {
            stopCatalogAutoRefresh()
            stopFreshnessSweep()
            scheduleCaptureSync()
            return
        }
        startCatalogAutoRefresh()
        startFreshnessSweep()
        await refreshSourceCatalog()
    }

    func updateWindowSize(_ size: CGSize) {
        let codableSize = CodableSize(size)
        guard wallLayout.windowSize != codableSize else { return }
        wallLayout.windowSize = codableSize
        wallLayout.grid = WallGridCalculator.calculate(
            for: selectedSources.count,
            in: size,
            preferredColumnCount: wallLayout.preferredColumnCount
        )
        persistSnapshot()
    }

    func setFocusedSourceID(_ sourceID: String?) {
        wallLayout.focusedSourceID = sourceID
        persistSnapshot()
        scheduleCaptureSync()
    }

    func setPreferredColumnCount(_ preferredColumnCount: Int?) {
        wallLayout.preferredColumnCount = preferredColumnCount
        wallLayout.grid = WallGridCalculator.calculate(
            for: selectedSources.count,
            in: wallLayout.windowSize.cgSize,
            preferredColumnCount: preferredColumnCount
        )
        persistSnapshot()
    }

    func activate(sourceID: String) {
        guard let source = selectedSources.first(where: { $0.id == sourceID }) else { return }
        windowActivationService.activate(source: source)
    }

    func refreshSourceCatalog() async {
        guard permissionStatus == .granted else { return }
        guard !isRefreshingSourceCatalog else { return }
        isRefreshingSourceCatalog = true
        sourceCatalogError = nil

        defer {
            isRefreshingSourceCatalog = false
        }

        do {
            let catalog = try await sourceCatalogService.fetchCatalog()
            sourceCatalog = catalog
            selectedSources = SourceCatalogReconciler.reconcileSelections(selectedSources, with: catalog)
            wallLayout.activeSourceIDs = selectedSources.map(\.id)
            wallLayout.grid = WallGridCalculator.calculate(
                for: selectedSources.count,
                in: wallLayout.windowSize.cgSize,
                preferredColumnCount: wallLayout.preferredColumnCount
            )
            ensureTileStateCoverage()
            syncTilesWithSelectedSources()
            persistSnapshot()
            scheduleCaptureSync()
        } catch {
            sourceCatalogError = error.localizedDescription
        }
    }

    func isSelected(sourceID: String) -> Bool {
        selectedSources.contains(where: { $0.id == sourceID })
    }

    func toggleSelection(for source: MonitorSource) {
        if isSelected(sourceID: source.id) {
            removeSource(id: source.id)
            return
        }

        selectedSources.append(source)
        wallLayout.activeSourceIDs = selectedSources.map(\.id)
        wallLayout.grid = WallGridCalculator.calculate(
            for: selectedSources.count,
            in: wallLayout.windowSize.cgSize,
            preferredColumnCount: wallLayout.preferredColumnCount
        )
        tiles[source.id] = TileState.placeholder(
            sourceID: source.id,
            fpsTier: .balanced,
            freshness: source.isAvailable ? .stale : .offline,
            lastFrameAt: source.lastSeenAt
        )
        persistSnapshot()
        scheduleCaptureSync()
    }

    func replaceSelectedSources(_ sources: [MonitorSource]) {
        selectedSources = sources
        wallLayout.activeSourceIDs = sources.map(\.id)
        wallLayout.grid = WallGridCalculator.calculate(
            for: sources.count,
            in: wallLayout.windowSize.cgSize,
            preferredColumnCount: wallLayout.preferredColumnCount
        )
        ensureTileStateCoverage()
        syncTilesWithSelectedSources()
        persistSnapshot()
        scheduleCaptureSync()
    }

    func removeSource(id: String) {
        selectedSources.removeAll { $0.id == id }
        wallLayout.activeSourceIDs.removeAll { $0 == id }
        tiles.removeValue(forKey: id)
        if wallLayout.focusedSourceID == id {
            wallLayout.focusedSourceID = nil
        }
        wallLayout.grid = WallGridCalculator.calculate(
            for: selectedSources.count,
            in: wallLayout.windowSize.cgSize,
            preferredColumnCount: wallLayout.preferredColumnCount
        )
        persistSnapshot()
        scheduleCaptureSync()
    }

    func commitSelectedSourceOrder(_ sourceIDs: [String]) {
        guard sourceIDs.count == selectedSources.count else { return }

        let selectedSourcesByID = Dictionary(uniqueKeysWithValues: selectedSources.map { ($0.id, $0) })
        let reorderedSources = sourceIDs.compactMap { selectedSourcesByID[$0] }
        guard reorderedSources.count == selectedSources.count else { return }
        guard reorderedSources.map(\.id) != selectedSources.map(\.id) else { return }

        selectedSources = reorderedSources
        wallLayout.activeSourceIDs = reorderedSources.map(\.id)
        persistSnapshot()
        scheduleCaptureSync()
    }

    private func ensureTileStateCoverage() {
        for source in selectedSources {
            if tiles[source.id] == nil {
                tiles[source.id] = TileState.placeholder(
                    sourceID: source.id,
                    fpsTier: .balanced,
                    freshness: source.isAvailable ? .stale : .offline,
                    lastFrameAt: source.lastSeenAt
                )
            }
        }
    }

    private func syncTilesWithSelectedSources() {
        let validIDs = Set(selectedSources.map(\.id))
        tiles = tiles.filter { validIDs.contains($0.key) }

        for source in selectedSources {
            guard var tile = tiles[source.id] else { continue }
            if !source.isAvailable {
                tile.freshness = .offline
                tile.errorMessage = nil
            } else if tile.previewImage == nil {
                tile.freshness = .stale
            }
            tile.lastFrameAt = source.lastSeenAt ?? tile.lastFrameAt
            tiles[source.id] = tile
        }
    }

    private func persistSnapshot() {
        snapshotStore.save(
            WallSessionSnapshot(
                selectedSources: selectedSources,
                focusedSourceID: wallLayout.focusedSourceID,
                windowSize: wallLayout.windowSize,
                preferredColumnCount: wallLayout.preferredColumnCount
            )
        )
    }

    private func scheduleCaptureSync() {
        captureSyncTask?.cancel()

        let isGranted = permissionStatus == .granted
        let sources = selectedSources
        let focusSourceID = wallLayout.focusedSourceID
        let coordinator = captureCoordinator

        captureSyncTask = Task {
            if isGranted {
                await coordinator.sync(sources: sources, focusSourceID: focusSourceID)
            } else {
                await coordinator.stopAll()
            }
        }
    }

    private func startCatalogAutoRefresh() {
        guard catalogRefreshTask == nil else { return }

        catalogRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }

                guard let self else { return }
                await self.refreshSourceCatalog()
            }
        }
    }

    private func stopCatalogAutoRefresh() {
        catalogRefreshTask?.cancel()
        catalogRefreshTask = nil
    }

    private func startFreshnessSweep() {
        guard freshnessSweepTask == nil else { return }

        freshnessSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }

                guard let self else { return }
                self.markStaleTiles()
            }
        }
    }

    private func stopFreshnessSweep() {
        freshnessSweepTask?.cancel()
        freshnessSweepTask = nil
    }

    private func applyFrame(sourceID: String, frame: PreviewFrame, tier: TileFrameRateTier) {
        guard var tile = tiles[sourceID] else { return }
        tile.previewImage = frame.image
        tile.fpsTier = tier
        tile.freshness = .live
        tile.lastFrameAt = frame.createdAt
        tile.errorMessage = nil
        tiles[sourceID] = tile
        updateSourceMetadata(sourceID: sourceID, isAvailable: true, lastSeenAt: frame.createdAt)
    }

    private func applyError(sourceID: String, message: String) {
        guard var tile = tiles[sourceID] else { return }
        tile.errorMessage = message
        tile.freshness = .stale
        tiles[sourceID] = tile
    }

    private func applyOffline(sourceID: String) {
        guard var tile = tiles[sourceID] else { return }
        tile.freshness = .offline
        tile.previewImage = nil
        tile.errorMessage = nil
        tiles[sourceID] = tile
        updateSourceMetadata(sourceID: sourceID, isAvailable: false, lastSeenAt: nil)
    }

    private func markStaleTiles(referenceDate: Date = Date()) {
        for sourceID in tiles.keys {
            guard var tile = tiles[sourceID] else { continue }
            guard tile.freshness == .live, tile.errorMessage == nil else { continue }
            guard let lastFrameAt = tile.lastFrameAt else { continue }
            if referenceDate.timeIntervalSince(lastFrameAt) > 3 {
                tile.freshness = .stale
                tiles[sourceID] = tile
            }
        }
    }

    private func updateSourceMetadata(sourceID: String, isAvailable: Bool, lastSeenAt: Date?) {
        guard let index = selectedSources.firstIndex(where: { $0.id == sourceID }) else { return }
        selectedSources[index].isAvailable = isAvailable
        selectedSources[index].lastSeenAt = lastSeenAt ?? selectedSources[index].lastSeenAt
    }
}
