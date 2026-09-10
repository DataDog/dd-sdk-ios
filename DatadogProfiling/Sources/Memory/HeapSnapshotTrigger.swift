/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if !os(watchOS)

/// The RUM event that caused a heap snapshot to be captured outside the periodic cadence.
///
/// Emitted as a `trigger:<raw value>` tag on the `ProfileEvent`. A periodic profile carries no
/// `trigger` tag at all — absence means periodic.
internal enum HeapSnapshotTrigger: String {
    /// The app-launch time-to-initial-display vital.
    case ttid
    /// A RUM app hang error.
    case appHang = "app_hang"
    /// A RUM memory warning error (`didReceiveMemoryWarningNotification`).
    case memoryWarning = "memory_warning"
}

#endif
