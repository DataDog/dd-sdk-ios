/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
import DatadogRUM

class RUMMonitorE2ETests: E2ETests {
    private var rum: RUMMonitorProtocol { RUMMonitor.shared() }

    let actionTypePool = [RUMActionType.swipe, .scroll, .tap, .custom]
    let nonCustomActionTypePool = [RUMActionType.swipe, .scroll, .tap]

    /// - api-surface: RUMMonitorProtocol.startView(key: String,name: String? = nil,attributes: [AttributeKey: AttributeValue] = [:])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_start_view
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_start_view: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_start_view @type:view @view.name:rumView* @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_start_view_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_start_view: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_start_view,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_start_view() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.stopView(key: String,attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_view
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_view: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_stop_view @type:view @view.name:rumView* @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_view_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_view: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_view,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_view() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopView(key: viewKey, attributes: [:])
        }
    }

    /// - api-surface: RUMMonitorProtocol.stopView(key: String,attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_view_with_pending_resource
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_view_with_pending_resource: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_stop_view_with_pending_resource @type:view @view.name:rumView* @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_view_with_pending_resource_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_view_with_pending_resource: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_view_with_pending_resource,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_view_with_pending_resource() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())
        rum.startResource(resourceKey: resourceKey, httpMethod: .get, urlString: resourceKey, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopView(key: viewKey, attributes: [:])
        }

        rum.stopResource(resourceKey: resourceKey, statusCode: (200...500).randomElement()!, kind: .other)
    }

    /// - api-surface: RUMMonitorProtocol.stopView(key: String,attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_view_with_pending_action
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_view_with_pending_action: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_stop_view_with_pending_action @type:view @view.name:rumView* @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_view_with_pending_action_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_view_with_pending_action: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_view_with_pending_action,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_view_with_pending_action() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = actionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())
        rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopView(key: viewKey, attributes: [:])
        }

        rum.stopAction(type: actionType, name: actionName, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addTiming(name: String)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_timing
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_timing: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_add_timing @type:view @view.name:rumView* @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_timing_upper_bound
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_timing: timing is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_add_timing @type:view @view.url_path:datadog\\/rum*\").rollup(\"avg\", \"@view.custom_timings.time_event\").last(\"1d\") < 200000000"
    /// $monitor_threshold = 200000000
    /// ```
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_timing_lower_bound
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_timing: timing is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_add_timing_lower_bound @type:view @view.url_path:datadog\\/rum*\").rollup(\"avg\", \"@view.custom_timings.time_event\").last(\"1d\") > 700000000"
    /// $monitor_threshold = 700000000
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_timing_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_timing: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_timing,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_timing() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let timing = Double((200...700).randomElement()!) * 0.01

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())
        Thread.sleep(forTimeInterval: timing)
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addTiming(name: RUMConstants.timingName)
        }
        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_start_non_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_start_non_custom_action_with_no_outcome: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_start_non_custom_action_with_no_outcome\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_start_non_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_start_non_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_start_non_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_start_non_custom_action_with_no_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = nonCustomActionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_start_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_start_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_start_custom_action_with_no_outcome @action.type:custom @view.url_path:datadog\\/rum* @action.name:rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_start_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_start_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_start_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_start_custom_action_with_no_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = RUMActionType.custom

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_start_action_with_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_start_action_with_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_start_action_with_outcome @view.url_path:datadog\\/rum* @action.name:*rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_start_action_with_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_start_action_with_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_start_action_with_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_start_action_with_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = actionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        rum.sendRandomActionOutcomeEvent()

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    /// - api-surface: RUMMonitorProtocol.stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_non_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_non_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_stop_non_custom_action_with_no_outcome\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_non_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_non_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_non_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_non_custom_action_with_no_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = nonCustomActionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopAction(type: actionType, name: actionName, attributes: [:])
        }

        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    /// - api-surface: RUMMonitorProtocol.stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_stop_custom_action_with_no_outcome @action.type:custom @view.url_path:datadog\\/rum* @action.name:rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_custom_action_with_no_outcome_performance_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_custom_action_with_no_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = RUMActionType.custom

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopAction(type: actionType, name: actionName, attributes: [:])
        }

        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    /// - api-surface: RUMMonitorProtocol.stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_action_with_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_action_with_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_stop_action_with_outcome @view.url_path:datadog\\/rum* @action.name:*rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_action_with_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_action_with_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_action_with_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_action_with_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = actionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopAction(type: actionType, name: actionName, attributes: [:])
        }

        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_non_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_non_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_add_non_custom_action_with_no_outcome\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_non_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_non_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_non_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_non_custom_action_with_no_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = nonCustomActionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }

        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_add_custom_action_with_no_outcome @action.type:custom @view.url_path:datadog\\/rum* @action.name:rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_custom_action_with_no_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = RUMActionType.custom

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_action_with_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_action_with_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_add_action_with_outcome @view.url_path:datadog\\/rum* @action.name:*rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_action_with_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_action_with_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_action_with_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_action_with_outcome() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let actionType = actionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        rum.sendRandomActionOutcomeEvent()
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    /// - api-surface: RUMMonitorProtocol.stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_custom_action_while_active_action
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_custom_action_while_active_action: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_add_custom_action_while_active_action @action.type:custom @view.url_path:datadog\\/rum* @action.name:rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_custom_action_while_active_action_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_custom_action_while_active_action: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_custom_action_while_active_action,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_custom_action_while_active_action() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let activeActionName = "rumActiveAction" + String.mockRandom()
        let customActionName = String.mockRandom()
        let actionType = actionTypePool.randomElement()!

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startAction(type: actionType, name: activeActionName, attributes: DD.logAttributes())
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: .custom, name: customActionName, attributes: DD.logAttributes())
        }
        rum.sendRandomActionOutcomeEvent()
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)
        rum.stopAction(type: actionType, name: activeActionName, attributes: [:])

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    /// - api-surface: RUMMonitorProtocol.stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_stop_background_action_with_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_stop_background_action_with_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_ignore_stop_background_action_with_outcome @action.name:*rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_stop_background_action_with_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_stop_background_action_with_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_stop_background_action_with_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_stop_background_action_with_outcome() {
        let actionName = String.mockRandom()
        let actionType = actionTypePool.randomElement()!

        rum.startAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        rum.sendRandomActionOutcomeEvent()
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopAction(type: actionType, name: actionName, attributes: [:])
        }
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome @action.type:custom @action.name:rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_add_background_non_custom_action_with_no_outcome() {
        let actionName = String.mockRandom()
        let actionType = nonCustomActionTypePool.randomElement()!

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_custom_action_with_no_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_add_background_custom_action_with_no_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_ignore_add_background_custom_action_with_no_outcome @action.type:custom @action.name:rumAction* @view.url_path:\"com/datadog/background/view\"\").rollup(\"count\").by(\"@type\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_custom_action_with_no_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_add_background_custom_action_with_no_outcome: has a high average execution time"
    /// $monitor_query = "sum(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_add_background_custom_action_with_no_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_add_background_custom_action_with_no_outcome() {
        let actionName = String.mockRandom()
        let actionType = RUMActionType.custom

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_custom_action_with_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_add_background_custom_action_with_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_ignore_add_background_custom_action_with_outcome @action.type:custom @action.name:rumAction* @view.url_path:\"com/datadog/background/view\"\").rollup(\"count\").by(\"@type\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_custom_action_with_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_add_background_custom_action_with_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_add_background_custom_action_with_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_add_background_custom_action_with_outcome() {
        let actionName = String.mockRandom()
        let actionType = RUMActionType.custom

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)
        rum.sendRandomActionOutcomeEvent()
    }

    /// - api-surface: RUMMonitorProtocol.addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_non_custom_action_with_outcome
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_add_background_non_custom_action_with_outcome: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_rummonitor_ignore_add_background_non_custom_action_with_outcome @action.type:custom @action.name:rumAction*\").rollup(\"count\").by(\"@type\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_non_custom_action_with_outcome_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_add_background_non_custom_action_with_outcome: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_add_background_non_custom_action_with_outcome,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_add_background_non_custom_action_with_outcome() {
        let actionName = String.mockRandom()
        let actionType = nonCustomActionTypePool.randomElement()!

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addAction(type: actionType, name: actionName, attributes: DD.logAttributes())
        }
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)
        rum.sendRandomActionOutcomeEvent()
    }

    /// - api-surface: RUMMonitorProtocol.startResource(resourceKey: String,httpMethod: RUMMethod,urlString: String,attributes: [AttributeKey: AttributeValue] = [:])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_start_resource
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_start_resource: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_start_resource @view.url_path:datadog\\/rum* @type:resource\").rollup(\"count\").last(\"1d\") > 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_start_resource_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_start_resource: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_start_resource,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_start_resource() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.startResource(
                resourceKey: resourceKey,
                httpMethod: .get,
                urlString: String.mockRandom(),
                attributes: DD.logAttributes()
            )
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startResource(resourceKey: String,httpMethod: RUMMethod,urlString: String,attributes: [AttributeKey: AttributeValue] = [:])
    /// - api-surface: RUMMonitorProtocol.stopResource(resourceKey: String,statusCode: Int?,kind: RUMResourceType,size: Int64? = nil,attributes: [AttributeKey: AttributeValue] = [:])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_resource
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_resource: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_stop_resource @view.url_path:datadog\\/rum* @type:resource @resource.status_code:200 @resource.type:(beacon OR fetch OR xhr OR document OR unknown OR image OR js OR font OR css OR media OR other) @resource.url:http\\:\\/\\/datadog\\/resource\\/rum\\/*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_resource_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_resource: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_resource,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_resource() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startResource(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopResource(resourceKey: resourceKey, statusCode: 200, kind: .other)
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startResource(resourceKey: String,httpMethod: RUMMethod,urlString: String,attributes: [AttributeKey: AttributeValue] = [:])
    /// - api-surface: RUMMonitorProtocol.stopResourceWithError(resourceKey: String,message: String,response: URLResponse?,attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_resource_with_error
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_resource_with_error: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_stop_resource_with_error @type:error @error.resource.status_code:>=400 @error.source:(logger OR network OR source OR console OR agent OR webview) @error.resource.url:http\\:\\/\\/datadog\\/resource\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_resource_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_resource_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_resource_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_resource_with_error() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startResource(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopResourceWithError(
                resourceKey: resourceKey,
                message: String.mockRandom(),
                response: HTTPURLResponse(
                    url: URL.mockRandom(),
                    statusCode: (400...511).randomElement()!,
                    httpVersion: nil,
                    headerFields: nil
                ),
                attributes: DD.logAttributes()
            )
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startResource(resourceKey: String,httpMethod: RUMMethod,urlString: String,attributes: [AttributeKey: AttributeValue] = [:])
    /// - api-surface: RUMMonitorProtocol.stopResourceWithError(resourceKey: String,message: String,response: URLResponse?,attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_stop_resource_with_error_without_status_code
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_stop_resource_with_error_without_status_code: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_stop_resource_with_error_without_status_code @type:error @error.source:(logger OR network OR source OR console OR agent OR webview) @error.resource.url:http\\:\\/\\/datadog\\/resource\\/rum* @error.resource.status_code:0\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_stop_resource_with_error_without_status_code_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_stop_resource_with_error_without_status_code: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_stop_resource_with_error_without_status_code,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_stop_resource_with_error_without_status_code() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.startResource(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopResourceWithError(
                resourceKey: resourceKey,
                message: String.mockRandom(),
                response: nil,
                attributes: DD.logAttributes()
            )
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.startResource(resourceKey: String,httpMethod: RUMMethod,urlString: String,attributes: [AttributeKey: AttributeValue] = [:])
    /// - api-surface: RUMMonitorProtocol.stopResource(resourceKey: String,statusCode: Int?,kind: RUMResourceType,size: Int64? = nil,attributes: [AttributeKey: AttributeValue] = [:])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_stop_background_resource
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_stop_background_resource: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_ignore_stop_background_resource @type:resource @resource.status_code:200 @resource.type:(beacon OR fetch OR xhr OR document OR unknown OR image OR js OR font OR css OR media OR other) @resource.url:http\\:\\/\\/datadog\\/resource\\/rum\\/* @view.url_path:\"com/datadog/background/view\"\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_stop_background_resource_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_stop_background_resource: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_stop_background_resource,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_stop_background_resource() {
        let resourceKey = String.mockRandom()

        rum.startResource(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopResource(resourceKey: resourceKey, statusCode: 200, kind: .other)
        }
    }

    /// - api-surface: RUMMonitorProtocol.startResource(resourceKey: String,httpMethod: RUMMethod,urlString: String,attributes: [AttributeKey: AttributeValue] = [:])
    /// - api-surface: RUMMonitorProtocol.stopResourceWithError(resourceKey: String,message: String,response: URLResponse?,attributes: [AttributeKey: AttributeValue])
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_stop_background_resource_with_error
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_stop_background_resource_with_error: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_ignore_stop_background_resource_with_error @type:error @error.resource.url:http\\:\\/\\/datadog\\/resource\\/rum\\/* @view.url_path:\"com/datadog/background/view\"\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_stop_background_resource_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_stop_background_resource_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_stop_background_resource_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_stop_background_resource_with_error() {
        let resourceKey = String.mockRandom()

        rum.startResource(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.stopResourceWithError(
                resourceKey: resourceKey,
                message: String.mockRandom(),
                response: HTTPURLResponse(
                    url: URL.mockRandom(),
                    statusCode: (400...511).randomElement()!,
                    httpVersion: nil,
                    headerFields: nil
                ),
                attributes: DD.logAttributes()
            )
        }
    }

    /// - api-surface: RUMMonitorProtocol.addError(message: String,source: RUMErrorSource,stack: String?,attributes: [AttributeKey: AttributeValue],file: StaticString?,line: UInt?)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_error
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_error: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_add_error @type:error @error.source:(logger OR network OR source OR console OR agent OR webview) @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_error,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_error() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let errorMessage = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addError(message: errorMessage, stack: nil, source: .custom, attributes: DD.logAttributes(), file: nil, line: nil)
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addError(message: String,source: RUMErrorSource,stack: String?,attributes: [AttributeKey: AttributeValue],file: StaticString?,line: UInt?)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_add_error_with_stacktrace
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_add_error_with_stacktrace: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_add_error_with_stacktrace @type:error @error.source:(logger OR network OR source OR console OR agent OR webview) @view.url_path:datadog\\/rum*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_add_error_with_stacktrace_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_add_error_with_stacktrace: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_add_error_with_stacktrace,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_add_error_with_stacktrace() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let errorMessage = String.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addError(
                message: errorMessage,
                stack: String.mockRandom(),
                source: .custom,
                attributes: DD.logAttributes(),
                file: nil,
                line: nil
            )
        }

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: RUMMonitorProtocol.addError(message: String,source: RUMErrorSource,stack: String?,attributes: [AttributeKey: AttributeValue],file: StaticString?,line: UInt?)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_error
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_add_background_error: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_ignore_add_background_error @type:error @error.source:(logger OR network OR source OR console OR agent OR webview) @view.url_path:\"com/datadog/background/view\"\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_add_background_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_add_background_error,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_add_background_error() {
        let errorMessage = String.mockRandom()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addError(message: errorMessage, stack: nil, source: .custom, attributes: DD.logAttributes(), file: nil, line: nil)
        }
    }

    /// - api-surface: RUMMonitorProtocol.addError(message: String,source: RUMErrorSource,stack: String?,attributes: [AttributeKey: AttributeValue],file: StaticString?,line: UInt?)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_error_with_stacktrace
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_rummonitor_ignore_add_background_error_with_stacktrace: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_rummonitor_ignore_add_background_error_with_stacktrace @type:error @error.source:(logger OR network OR source OR console OR agent OR webview) @view.url_path:\"com/datadog/background/view\"\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_rummonitor_ignore_add_background_error_with_stacktrace_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_rummonitor_ignore_add_background_error_with_stacktrace: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_rummonitor_ignore_add_background_error_with_stacktrace,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    func test_rum_rummonitor_ignore_add_background_error_with_stacktrace() {
        let errorMessage = String.mockRandom()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            rum.addError(message: errorMessage, stack: String.mockRandom(), source: .custom, attributes: DD.logAttributes(), file: nil, line: nil)
        }
    }
}
