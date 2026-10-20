/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)
import AppKit
import Testing
import TestUtilities
@testable import DatadogRUM

@Suite(.datadogTesting)
@MainActor
struct AppKitExtensionsTests {
    @Test
    func toolbarItemViewerClassIsNotNil() {
        #expect(toolbarItemViewerClass != nil)
    }

    @Test
    func toolbarItemViewerIsIdentified() throws {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let button = NSButton(title: "Button", target: nil, action: nil)
        let item = NSToolbarItem(itemIdentifier: .init("item"))
        item.view = button

        let toolbarDelegate = ToolbarDelegate(item: item)
        let toolbar = NSToolbar(identifier: .init("toolbar"))
        toolbar.delegate = toolbarDelegate
        window.toolbar = toolbar
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        let toolbarItemViewer = try #require(button.superview)
        #expect(toolbarItemViewer.isNSToolbarItemViewer)

        withExtendedLifetime(toolbarDelegate) {}
    }

    @Test
    func rootViewIsCommonAncestorOfContentAndToolbarViews() throws {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        let contentButton = NSButton(title: "Content Button", target: nil, action: nil)
        contentView.addSubview(contentButton)

        let toolbarButton = NSButton(title: "Toolbar Button", target: nil, action: nil)
        let item = NSToolbarItem(itemIdentifier: .init("item"))
        item.view = toolbarButton

        let toolbarDelegate = ToolbarDelegate(item: item)
        let toolbar = NSToolbar(identifier: .init("toolbar"))
        toolbar.delegate = toolbarDelegate
        window.toolbar = toolbar
        contentView.superview?.layoutSubtreeIfNeeded()

        let rootView = try #require(window.rootView)
        #expect(rootView.superview == nil)
        #expect(contentButton.isDescendant(of: rootView))
        #expect(toolbarButton.isDescendant(of: rootView))
        #expect(!toolbarButton.isDescendant(of: contentView))

        withExtendedLifetime(toolbarDelegate) {}
    }

    private final class ToolbarDelegate: NSObject, NSToolbarDelegate {
        let item: NSToolbarItem

        init(item: NSToolbarItem) {
            self.item = item
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            return [item.itemIdentifier]
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            return [item.itemIdentifier]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            return itemIdentifier == item.itemIdentifier ? item : nil
        }
    }
}

#endif
