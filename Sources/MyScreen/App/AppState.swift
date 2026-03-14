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
    private let snapshotStore: WallSessionSnapshotStore

    init(
        permissionService: ScreenCapturePermissionService = ScreenCapturePermissionService(),
        sourceCatalogService: SourceCatalogService = SourceCatalogService(),
        snapshotStore: WallSessionSnapshotStore = WallSessionSnapshotStore()
    ) {
        self.permissionService = permissionService
        self.sourceCatalogService = sourceCatalogService
        self.snapshotStore = snapshotStore

        let snapshot = snapshotStore.load() ?? .empty
        self.permissionStatus = permissionService.currentStatus()
        self.selectedSources = snapshot.selectedSources
        self.sourceCatalog = .empty
        self.wallLayout = WallLayoutState(
            activeSourceIDs: snapshot.selectedSources.map(\.id),
            focusedSourceID: snapshot.focusedSourceID,
            grid: WallGridCalculator.calculate(for: snapshot.selectedSources.count, in: snapshot.windowSize.cgSize),
            windowSize: snapshot.windowSize
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
    }

    func bootstrap() async {
        permissionStatus = permissionService.currentStatus()
        ensureTileStateCoverage()
        guard permissionStatus == .granted else { return }
        await refreshSourceCatalog()
    }

    func requestScreenCapturePermission() async {
        guard !isPermissionRequestInFlight else { return }
        isPermissionRequestInFlight = true
        permissionStatus = await permissionService.requestAccess()
        isPermissionRequestInFlight = false
        guard permissionStatus == .granted else { return }
        await refreshSourceCatalog()
    }

    func updateWindowSize(_ size: CGSize) {
        let codableSize = CodableSize(size)
        guard wallLayout.windowSize != codableSize else { return }
        wallLayout.windowSize = codableSize
        wallLayout.grid = WallGridCalculator.calculate(for: selectedSources.count, in: size)
        persistSnapshot()
    }

    func setFocusedSourceID(_ sourceID: String?) {
        wallLayout.focusedSourceID = sourceID
        persistSnapshot()
    }

    func refreshSourceCatalog() async {
        guard permissionStatus == .granted else { return }
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
            wallLayout.grid = WallGridCalculator.calculate(for: selectedSources.count, in: wallLayout.windowSize.cgSize)
            ensureTileStateCoverage()
            syncTilesWithSelectedSources()
            persistSnapshot()
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
        wallLayout.grid = WallGridCalculator.calculate(for: selectedSources.count, in: wallLayout.windowSize.cgSize)
        tiles[source.id] = TileState.placeholder(
            sourceID: source.id,
            fpsTier: .balanced,
            freshness: source.isAvailable ? .stale : .offline,
            lastFrameAt: source.lastSeenAt
        )
        persistSnapshot()
    }

    func replaceSelectedSources(_ sources: [MonitorSource]) {
        selectedSources = sources
        wallLayout.activeSourceIDs = sources.map(\.id)
        wallLayout.grid = WallGridCalculator.calculate(for: sources.count, in: wallLayout.windowSize.cgSize)
        ensureTileStateCoverage()
        syncTilesWithSelectedSources()
        persistSnapshot()
    }

    func removeSource(id: String) {
        selectedSources.removeAll { $0.id == id }
        wallLayout.activeSourceIDs.removeAll { $0 == id }
        tiles.removeValue(forKey: id)
        if wallLayout.focusedSourceID == id {
            wallLayout.focusedSourceID = nil
        }
        wallLayout.grid = WallGridCalculator.calculate(for: selectedSources.count, in: wallLayout.windowSize.cgSize)
        persistSnapshot()
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
                windowSize: wallLayout.windowSize
            )
        )
    }
}
