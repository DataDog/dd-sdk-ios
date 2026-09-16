/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct EXP147ScreenScaffold<Actions: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let actions: Actions

    init(
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        List {
            Section("Destination") {
                Text(title)
                    .font(.title2)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Section("Actions") {
                actions
            }
        }
        .navigationTitle(title)
        .accessibilityIdentifier("exp147.screen.\(title)")
    }
}

extension EXP147Route {
    var displayTitle: String {
        switch self {
        case .thread(let id): "Thread \(id)"
        case .channel(let id): "Channel \(id)"
        case .mentions: "Mentions"
        case .savedItems: "Saved items"
        case .scheduledMessages: "Scheduled messages"
        case .people: "People"
        case .huddle(let id): "Huddle \(id)"
        case .canvas(let id): "Canvas \(id)"
        case .search(let query): "Search \(query)"
        case .searchResults(let query): "Results for \(query)"
        case .note(let id): "Note \(id)"
        case .folder(let name): "Folder \(name)"
        case .tag(let name): "Tag \(name)"
        case .recentNotes: "Recent notes"
        case .sharedNotes: "Shared notes"
        case .trash: "Trash"
        case .documentScanner: "Document scanner"
        case .profile: "Profile"
        case .preferences: "Preferences"
        case .notifications: "Notifications"
        case .privacy: "Privacy"
        case .integrations: "Integrations"
        case .appearance: "Appearance"
        case .storage: "Storage"
        case .about: "About"
        }
    }
}

extension EXP147Presentation {
    var displayTitle: String {
        switch self {
        case .compose: "Compose"
        case .threadInfo(let id): "Thread \(id) info"
        case .shareThread(let id): "Share thread \(id)"
        case .quickSwitcher: "Quick switcher"
        case .attachment(let id): "Attachment \(id)"
        case .onboarding: "Onboarding"
        case .whatsNew: "What's new"
        }
    }
}
