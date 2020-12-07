/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Possible values for the Data Tracking Consent.
internal enum TrackingConsent {
    /// The permission to persist and send data to the Datadog servers was granted.
    /// Any previously stored pending data will be marked as ready for sent.
    case granted
    /// Any previously stored pending data will be deleted and all Logging, RUM and Tracing events will
    /// be dropped from now on, without persisting it in any way.
    case notGranted
    /// All Logging, RUM and Tracing events will be persisted in an intermediate location and will be pending there
    /// until `.granted` or `.notGranted` consent value is set.
    /// Based on the next consent value, intermediate data will be send to Datadog or deleted.
    case pending
}
