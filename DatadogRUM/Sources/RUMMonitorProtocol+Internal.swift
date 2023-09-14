/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Extends `RUMMonitorProtocol` with additional methods designed for Datadog cross-platform SDKs.
public extension RUMMonitorProtocol {
    /// Grants access to an internal interface utilized only by Datadog cross-platform SDKs.
    /// **It is not meant for public use** and it might change without prior notice.
    var _internal: DatadogInternalInterface? {
        guard let monitor = self as? RUMCommandSubscriber else {
            return nil
        }
        return DatadogInternalInterface(monitor: monitor)
    }
}

/// An interface granting access to internal methods exclusively utilized by Datadog cross-platform SDKs.
/// **It is not meant for public use.**
///
/// Methods, members, and functionality of this interface is subject to change without prior notice,
/// as they are not considered part of the public interface of the Datadog SDK.
public struct DatadogInternalInterface {
    let monitor: RUMCommandSubscriber

    /// Adds RUM long task to current view.
    /// - Parameters:
    ///   - time: the time of this command in cross-platform SDK
    ///   - duration: duration of the long task
    ///   - attributes: attributes to process along with this call
    public func addLongTask(
        at time: Date,
        duration: TimeInterval,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        let longTaskCommand = RUMAddLongTaskCommand(time: time, attributes: attributes, duration: duration)
        monitor.process(command: longTaskCommand)
    }

    /// Updates cross-platform performance metrics in current view.
    /// - Parameters:
    ///   - time: the time of this command in cross-platform SDK
    ///   - metric: the metric to update
    ///   - value: new value of the metric
    ///   - attributes: attributes to process along with this call
    public func updatePerformanceMetric(
        at time: Date,
        metric: PerformanceMetric,
        value: Double,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        let performanceMetric = RUMUpdatePerformanceMetric(
            metric: metric,
            value: value,
            time: time,
            attributes: attributes
        )
        monitor.process(command: performanceMetric)
    }

    /// Adds temporal metrics to given RUM resource.
    ///
    /// It must be called before the resource is stopped.
    /// - Parameters:
    ///   - time: the time of this command in cross-platform SDK
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - fetch: properties of the fetch phase for the resource (the earliest and latest timing).
    ///   - redirection: properties of the redirection phase for the resource.
    ///   - dns: properties of the name lookup phase for the resource.
    ///   - connect: properties of the connect phase for the resource.
    ///   - ssl: properties of the secure connect phase for the resource.
    ///   - firstByte: properties of the TTFB phase for the resource.
    ///   - download: properties of the download phase for the resource.
    ///   - responseSize: the size of data delivered to delegate or completion handler.
    ///   - attributes: attributes to process along with this call
    public func addResourceMetrics(
        at time: Date,
        resourceKey: String,
        fetch: (start: Date, end: Date),
        redirection: (start: Date, end: Date)?,
        dns: (start: Date, end: Date)?,
        connect: (start: Date, end: Date)?,
        ssl: (start: Date, end: Date)?,
        firstByte: (start: Date, end: Date)?,
        download: (start: Date, end: Date)?,
        responseSize: Int64?,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        monitor.process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: time,
                attributes: attributes,
                metrics: ResourceMetrics(
                    fetch: ResourceMetrics.DateInterval(start: fetch.start, end: fetch.end),
                    redirection: ResourceMetrics.DateInterval.create(start: redirection?.start, end: redirection?.end),
                    dns: ResourceMetrics.DateInterval.create(start: dns?.start, end: dns?.end),
                    connect: ResourceMetrics.DateInterval.create(start: connect?.start, end: connect?.end),
                    ssl: ResourceMetrics.DateInterval.create(start: ssl?.start, end: ssl?.end),
                    firstByte: ResourceMetrics.DateInterval.create(start: firstByte?.start, end: firstByte?.end),
                    download: ResourceMetrics.DateInterval.create(start: download?.start, end: download?.end),
                    responseSize: responseSize
                )
            )
        )
    }
}
