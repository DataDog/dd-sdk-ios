/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
import Datadog

class RUMGlobalE2ETests: E2ETests {
    private lazy var rum = Global.rum.dd

    // MARK: - Common Monitors

    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_globalrum_add_attribute
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_globalrum_add_attribute: has a high average execution time"
    /// $monitor_query = "sum(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_globalrum_add_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```
    ///
    /// ```apm
    /// $feature = rum
    /// $monitor_id = rum_globalrum_remove_attribute
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - rum_globalrum_remove_attribute: has a high average execution time"
    /// $monitor_query = "sum(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:rum_globalrum_remove_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// $monitor_threshold = 0.024
    /// ```

    // MARK: - RUM manual APIs

    /// - api-surface: DDRUMMonitor.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_add_attribute_for_view
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_add_attribute_for_view: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_add_attribute_for_view @type:view @view.name:rumView* @view.url_path:datadog\\/rum* @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_add_attribute_for_view() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)
        }

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())
        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: DDRUMMonitor.removeAttribute(forKey key: AttributeKey)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_remove_attribute_for_view
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_remove_attribute_for_view: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_remove_attribute_for_view @type:view @view.name:rumView* @view.url_path:datadog\\/rum* @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// ```
    func test_rum_globalrum_remove_attribute_for_view() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)

        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
        }

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())
        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: DDRUMMonitor.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_add_attribute_for_action
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_add_attribute_for_action: number of actions is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_add_attribute_for_action @type:action @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_add_attribute_for_action() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)
        }

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.addUserAction(type: .custom, name: actionName, attributes: DD.logAttributes())
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])

        rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
    }

    /// - api-surface: DDRUMMonitor.removeAttribute(forKey key: AttributeKey)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_remove_attribute_for_action
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_remove_attribute_for_action: number of actions is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_remove_attribute_for_action @type:action @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_remove_attribute_for_action() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let actionName = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)

        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        }

        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
        }

        rum.addUserAction(type: .custom, name: actionName, attributes: DD.logAttributes())
        Thread.sleep(forTimeInterval: RUMConstants.actionInactivityThreshold)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: DDRUMMonitor.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_add_attribute_for_resource
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_add_attribute_for_resource: number of actions is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_add_attribute_for_resource @type:resource @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_add_attribute_for_resource() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)
        }

        rum.startResourceLoading(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        Thread.sleep(forTimeInterval: RUMConstants.writeDelay)

        rum.stopView(key: viewKey, attributes: [:])

        rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
    }

    /// - api-surface: DDRUMMonitor.removeAttribute(forKey key: AttributeKey)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_remove_attribute_for_resource
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_remove_attribute_for_resource: number of actions is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_remove_attribute_for_resource @type:resource @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_remove_attribute_for_resource() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let resourceKey = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)

        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
        }

        rum.startResourceLoading(
            resourceKey: resourceKey,
            httpMethod: .get,
            urlString: String.mockRandom(),
            attributes: DD.logAttributes()
        )
        Thread.sleep(forTimeInterval: RUMConstants.writeDelay)

        rum.stopView(key: viewKey, attributes: [:])
    }

    /// - api-surface: DDRUMMonitor.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_add_attribute_for_error
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_add_attribute_for_error: number of actions is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_add_attribute_for_error @type:resource @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_add_attribute_for_error() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let errorMessage = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeAddAttribute) {
            rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)
        }

        rum.addError(
            message: errorMessage,
            source: .source,
            stack: nil,
            attributes: DD.logAttributes(),
            file: nil,
            line: nil
        )
        Thread.sleep(forTimeInterval: RUMConstants.writeDelay)

        rum.stopView(key: viewKey, attributes: [:])

        rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
    }

    /// - api-surface: DDRUMMonitor.removeAttribute(forKey key: AttributeKey)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_globalrum_remove_attribute_for_error
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_globalrum_remove_attribute_for_error: number of actions is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @context.test_method_name:rum_globalrum_remove_attribute_for_error @type:resource @context.custom_attribute.int:* @context.custom_attribute.string:*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_rum_globalrum_remove_attribute_for_error() {
        let viewKey = String.mockRandom()
        let viewName = String.mockRandom()
        let errorMessage = String.mockRandom()
        let strAttrValue = String.mockRandom()
        let intAttrValue = Int.mockRandom()

        rum.startView(key: viewKey, name: viewName, attributes: DD.logAttributes())

        rum.addAttribute(forKey: RUMConstants.customAttribute_String, value: strAttrValue)
        rum.addAttribute(forKey: RUMConstants.customAttribute_Int, value: intAttrValue)

        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_String)
        }
        measure(resourceName: DD.PerfSpanName.rumAttributeRemoveAttribute) {
            rum.removeAttribute(forKey: RUMConstants.customAttribute_Int)
        }

        rum.addError(
            message: errorMessage,
            source: .source,
            stack: nil,
            attributes: DD.logAttributes(),
            file: nil,
            line: nil
        )
        Thread.sleep(forTimeInterval: RUMConstants.writeDelay)

        rum.stopView(key: viewKey, attributes: [:])
    }
}
