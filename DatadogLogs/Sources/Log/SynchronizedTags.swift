/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A thread-safe container for managing tags in a set.
/// This class allows concurrent access and modification of tags, ensuring data consistency
/// through the use of a `ReadWriteLock`. It is designed to be used in scenarios where tags
/// need to be safely managed across multiple threads or tasks.
internal final class SynchronizedTags: Sendable {
    /// The underlying set of tags, wrapped in a `ReadWriteLock` to ensure thread safety.
    private let tags: ReadWriteLock<Set<String>>

    /// Initializes a new instance of `SynchronizedTags` with the provided set.
    ///
    /// - Parameter tags: A set of initial tags.
    init(tags: Set<String>) {
        self.tags = .init(wrappedValue: tags)
    }

    /// Adds a tag to the set.
    ///
    /// - Parameter tag: The tag to add.
    func addTag(_ tag: String) {
        tags.mutate { $0.insert(tag) }
    }

    /// Removes a tag from the set.
    ///
    /// - Parameter tag: The tag to remove.
    func removeTag(_ tag: String) {
        tags.mutate { $0.remove(tag) }
    }

    /// Removes tags from the set based on a predicate.
    ///
    /// - Parameter shouldRemove: A closure that takes a tag and returns `true` if the tag should be removed.
    func removeTags(where shouldRemove: (String) -> Bool) {
        tags.mutate { $0 = $0.filter { !shouldRemove($0) } }
    }

    /// Retrieves the current set of tags.
    ///
    /// - Returns: A set containing all the tags.
    func getTags() -> Set<String> {
        return tags.wrappedValue
    }
}
