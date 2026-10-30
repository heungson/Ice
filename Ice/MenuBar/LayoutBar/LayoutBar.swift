//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let appState: AppState
        let section: MenuBarSection.Name

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(appState: appState, section: section)
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) { }
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var imageCache: MenuBarItemImageCache

    let section: MenuBarSection.Name

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .circular)
        }
    }

    var body: some View {
        mainContent
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .menuBarItemContainer(appState: appState)
            .containerShape(backgroundShape)
            .clipShape(backgroundShape)
            .contentShape([.interaction, .focusEffect], backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.quaternary)
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if #available(macOS 27.0, *) {
            NativeSectionLayoutBar27(itemManager: appState.itemManager, imageCache: imageCache, section: section)
        } else if imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .font(.body)
        } else {
            Representable(appState: appState, section: section)
        }
    }
}

/// macOS 27 sections come from saved application identities, not movable windows.
/// Keep tiles independent of stale or zero-sized Accessibility frames.
@available(macOS 27.0, *)
private struct NativeSectionLayoutBar27: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache
    let section: MenuBarSection.Name

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(itemManager.itemCache.managedItems(for: section), id: \.tag) { item in
                        tile(for: item)
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { identifiers, _ in
                let movable = Set(itemManager.itemCache.managedItems.compactMap { item in
                    editableBundleID(for: item)
                })
                let accepted = Set(identifiers).intersection(movable)
                for bundleID in accepted {
                    appState.concealer27.setSection(MacOS27Section(section), for: bundleID)
                }
                return !accepted.isEmpty
            }
        }
    }

    private func editableBundleID(for item: MenuBarItem) -> String? {
        guard item.canBeHidden, !item.isControlItem,
              let bundleID = item.sourceApplication?.bundleIdentifier,
              bundleID != Constants.bundleIdentifier
        else { return nil }
        return bundleID
    }

    private func tile(for item: MenuBarItem) -> some View {
        let captured = imageCache.images[item.tag]
        let icon = captured?.nsImage ?? item.sourceApplication?.icon ?? NSImage()
        let width = min(max(captured?.scaledSize.width ?? 22, 22), 160)
        return Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: 22)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .help(item.displayName)
            .accessibilityLabel(item.displayName)
            .opacity(editableBundleID(for: item) == nil ? 0.6 : 1)
            .draggable(editableBundleID(for: item) ?? "")
            .contextMenu {
                if let bundleID = editableBundleID(for: item) {
                    ForEach(MenuBarSection.Name.allCases, id: \.self) { destination in
                        if appState.menuBarManager.section(withName: destination)?.isEnabled == true {
                            Button("Move to \(destination.displayString)") {
                                appState.concealer27.setSection(MacOS27Section(destination), for: bundleID)
                            }
                        }
                    }
                }
            }
    }
}
