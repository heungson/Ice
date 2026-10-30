import AppKit
import Combine
import OSLog

/// Keeps the arrow between the saved hidden and visible groups and adopts user drags.
@available(macOS 27.0, *)
@MainActor
final class SectionBoundaryController27: ObservableObject {
    @Published private(set) var isArranging = false
    @Published private(set) var status = ""
    private weak var appState: AppState?
    private var task: Task<Void, Never>?
    private var initialized = false
    private var knownBundles = Set<String>()
    private var knownItems = Set<CGWindowID>()
    private var draggedBundle: String?
    private var draggedItem: CGWindowID?
    private var draggedArrow = false
    private var dragInProgress = false
    private var savedDragStates = [ControlItem.Identifier: ControlItem.HidingState]()
    private var needsAnotherPass = false
    private let logger = Logger(category: "SectionBoundary27")

    func performSetup(with appState: AppState) {
        self.appState = appState
        requestArrangement()
    }

    private func candidates(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.filter {
            !$0.isControlItem && $0.canBeHidden && $0.isOnScreen && $0.bounds.width > 4 &&
            $0.sourceApplication?.bundleIdentifier != MenuBarItemProvider27.menuBarAgentBundleID &&
            $0.sourceApplication?.bundleIdentifier != Constants.bundleIdentifier
        }
    }

    private func arrow(in items: [MenuBarItem]) -> MenuBarItem? {
        items.first { $0.tag == .visibleControlItem && $0.bounds.width > 4 }
    }

    func observe(items: [MenuBarItem]) {
        guard initialized, !isArranging, !dragInProgress, let appState,
              let arrow = arrow(in: items), arrow.isOnScreen else { return }
        let allBundles = Set(items.compactMap { $0.sourceApplication?.bundleIdentifier })
        let added = allBundles.subtracting(knownBundles)
        let newItems = candidates(items).filter { !knownItems.contains($0.windowID) }
        let observed = SectionBoundary27.observedSections(
            items: candidates(items).compactMap { item in
                item.sourceApplication?.bundleIdentifier.map { ($0, item.bounds) }
            }, arrow: arrow.bounds
        )
        for bundle in added {
            if let section = observed[bundle], section == .hidden {
                appState.concealer27.saveSection(section, for: bundle)
            }
        }
        knownBundles.formUnion(allBundles)
        knownItems.formUnion(items.map(\.windowID))
        if newItems.contains(where: { item in
            guard let id = item.sourceApplication?.bundleIdentifier, !added.contains(id) else { return false }
            return !SectionBoundary27.isCorrect(bounds: item.bounds, arrow: arrow.bounds, section: appState.concealer27.section(for: id))
        }) { requestArrangement() }
    }

    func beginUserDrag(at point: CGPoint?) {
        guard !isArranging, let point, let appState else { return }
        let items = MenuBarItemProvider27.cachedItems()
        let source = items.min { abs($0.bounds.midX - point.x) < abs($1.bounds.midX - point.x) }
        guard let source, source.bounds.insetBy(dx: -15, dy: -4).contains(point) else { return }
        draggedArrow = source.tag == .visibleControlItem
        draggedBundle = source.sourceApplication?.bundleIdentifier
        draggedItem = source.windowID
        dragInProgress = true
        savedDragStates = Dictionary(uniqueKeysWithValues: appState.menuBarManager.sections.map { ($0.controlItem.identifier, $0.controlItem.state) })
        if appState.settings.advanced.showAllSectionsOnUserDrag {
            appState.concealer27.isArrangingSections = true
            appState.concealer27.update()
        }
    }

    func endUserDrag() {
        guard dragInProgress, !isArranging, let appState else { return }
        dragInProgress = false
        let movedArrow = draggedArrow
        let bundle = draggedBundle
        let movedID = draggedItem
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            MenuBarItemProvider27.invalidateCache()
            let items = await MenuBarItemProvider27.items()
            guard let self else { return }
            defer {
                for section in appState.menuBarManager.sections {
                    if let state = self.savedDragStates[section.controlItem.identifier] { section.controlItem.state = state }
                }
                appState.concealer27.isArrangingSections = false
                appState.concealer27.update()
                self.requestArrangement()
            }
            guard let arrow = self.arrow(in: items) else { return }
            let observed = SectionBoundary27.observedSections(
                items: self.candidates(items).compactMap { item in
                    item.sourceApplication?.bundleIdentifier.map { ($0, item.bounds) }
                }, arrow: arrow.bounds
            )
            var adopted = movedArrow ? observed : [:]
            if !movedArrow, let bundle, let item = items.first(where: { $0.windowID == movedID }),
               let section = SectionBoundary27.section(of: item.bounds, arrow: arrow.bounds) {
                adopted[bundle] = section
            }
            for (id, section) in adopted {
                if appState.concealer27.section(for: id) != .alwaysHidden {
                    appState.concealer27.saveSection(section, for: id)
                }
            }
        }
    }

    func requestArrangement() {
        guard appState != nil else { return }
        // A pass reads the latest saved layout, so edits coalesce before it starts.
        guard !isArranging else { needsAnotherPass = true; return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.arrange()
        }
    }

    private func freshItems() async -> [MenuBarItem] {
        MenuBarItemProvider27.invalidateCache()
        return await MenuBarItemProvider27.items()
    }

    private func arrange() async {
        guard let appState, !isArranging else { return }
        isArranging = true
        status = "Arranging items around the arrow…"
        let concealer = appState.concealer27
        concealer.isArrangingSections = true
        concealer.update()
        defer {
            concealer.isArrangingSections = false
            concealer.update()
            isArranging = false
            initialized = true
            if needsAnotherPass {
                needsAnotherPass = false
                requestArrangement()
            }
        }
        try? await Task.sleep(for: .milliseconds(650))
        var items = await freshItems()
        knownBundles.formUnion(items.compactMap { $0.sourceApplication?.bundleIdentifier })
        knownItems.formUnion(items.map(\.windowID))
        // Overflowed items need macOS's own expanded bar before a physical move.
        if let overflow = MenuBarItemProvider27.overflowButtonFrame(),
           items.contains(where: { !$0.isOnScreen && ($0.tag == .visibleControlItem || $0.canBeHidden) }) {
            await MenuBarItemMover27.shieldedClick(at: CGPoint(x: overflow.midX, y: overflow.midY))
            try? await Task.sleep(for: .milliseconds(500))
            items = await freshItems()
        }
        guard var boundary = arrow(in: items), boundary.isOnScreen else {
            status = "Ice's arrow is not reachable. Expand the macOS menu bar overflow and choose Arrange Around Arrow."
            logger.error("Section arrangement failed: arrow is not drawn")
            return
        }
        let visible = candidates(items).filter { concealer.section(for: $0.sourceApplication?.bundleIdentifier ?? "") == .visible }
        // One arrow move fixes every visible item that is currently on its left.
        if let firstVisible = visible.min(by: { $0.bounds.minX < $1.bounds.minX }),
           firstVisible.bounds.minX < boundary.bounds.maxX {
            await move(boundary, to: CGPoint(x: firstVisible.bounds.minX - boundary.bounds.width / 2 - 3, y: boundary.bounds.midY), appState: appState)
            items = await freshItems()
            if let updated = arrow(in: items) { boundary = updated }
        }
        var failures = Set<String>()
        // Re-read after every drag: the bar reflows and old coordinates are unsafe.
        let targets = candidates(items).map { ($0.ownerPID, $0.tag) }
        for (pid, tag) in targets {
            items = await freshItems()
            guard let currentArrow = arrow(in: items),
                  let item = candidates(items).first(where: { $0.ownerPID == pid && $0.tag == tag }),
                  let bundle = item.sourceApplication?.bundleIdentifier else { continue }
            let section = concealer.section(for: bundle)
            guard !SectionBoundary27.isCorrect(bounds: item.bounds, arrow: currentArrow.bounds, section: section) else { continue }
            let x = section == .visible
                ? currentArrow.bounds.maxX + item.bounds.width / 2 + 3
                : currentArrow.bounds.minX - item.bounds.width / 2 - 3
            await move(item, to: CGPoint(x: x, y: currentArrow.bounds.midY), appState: appState)
            let after = await freshItems()
            if let a = arrow(in: after), let moved = after.first(where: { $0.ownerPID == pid && $0.tag == tag }),
               !SectionBoundary27.isCorrect(bounds: moved.bounds, arrow: a.bounds, section: section) {
                failures.insert(item.displayName)
            }
        }
        // Some applets refuse a direct drag. Move the boundary around the hidden
        // group instead, then move only visible icons that are now on its left.
        if !failures.isEmpty {
            items = await freshItems()
            if let a = arrow(in: items),
               let rightmostHidden = candidates(items).filter({
                   concealer.section(for: $0.sourceApplication?.bundleIdentifier ?? "") != .visible
               }).max(by: { $0.bounds.maxX < $1.bounds.maxX }),
               rightmostHidden.bounds.maxX > a.bounds.minX {
                await move(a, to: CGPoint(x: rightmostHidden.bounds.maxX + a.bounds.width / 2 + 3, y: a.bounds.midY), appState: appState)
            }
            items = await freshItems()
            let visibleTargets = candidates(items).filter {
                concealer.section(for: $0.sourceApplication?.bundleIdentifier ?? "") == .visible
            }.reversed().map { ($0.ownerPID, $0.tag) }
            for (pid, tag) in visibleTargets {
                items = await freshItems()
                guard let a = arrow(in: items),
                      let item = candidates(items).first(where: { $0.ownerPID == pid && $0.tag == tag }),
                      !SectionBoundary27.isCorrect(bounds: item.bounds, arrow: a.bounds, section: .visible)
                else { continue }
                await move(item, to: CGPoint(x: a.bounds.maxX + item.bounds.width / 2 + 3, y: a.bounds.midY), appState: appState)
            }
        }
        failures.removeAll()
        items = await freshItems()
        if let finalArrow = arrow(in: items) {
            for item in candidates(items) {
                let section = concealer.section(for: item.sourceApplication?.bundleIdentifier ?? "")
                if !SectionBoundary27.isCorrect(bounds: item.bounds, arrow: finalArrow.bounds, section: section) {
                    failures.insert(item.displayName)
                }
            }
        }
        status = failures.isEmpty ? "Hidden items are left of the arrow; visible items are right of it."
            : "Could not place: \(failures.sorted().joined(separator: ", ")). Command-drag them across the arrow or try Arrange Around Arrow again."
        logger.notice("\(self.status, privacy: .public)")
        if let finalArrow = arrow(in: items) {
            let summary = candidates(items).map { item in
                "\(item.displayName):\(concealer.section(for: item.sourceApplication?.bundleIdentifier ?? "").rawValue)@\(Int(item.bounds.midX))"
            }.joined(separator: " ")
            logger.notice("Verified boundary x=\(Int(finalArrow.bounds.midX)): \(summary, privacy: .public)")
        }
        await appState.itemManager.cacheItemsRegardless()
    }

    private func move(_ item: MenuBarItem, to target: CGPoint, appState: AppState) async {
        appState.hidEventManager.stopAll()
        defer { appState.hidEventManager.startAll() }
        await MenuBarItemMover27.cmdDrag(from: CGPoint(x: item.bounds.midX, y: item.bounds.midY), to: target, ownItem: item.isControlItem, jump: true)
        try? await Task.sleep(for: .milliseconds(450))
    }
}
