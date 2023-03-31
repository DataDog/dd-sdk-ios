/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import Datadog

class LoggerE2ETests: E2ETests {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        logger = Logger.builder.build()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Logging Method

    /// - api-surface: Logger.debug(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_debug_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_debug_log: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_debug_log status:debug\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_debug_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_debug_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_debug_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_DEBUG_log() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.debug(.mockRandom(), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.debug(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_debug_log_with_error_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_debug_log_with_error: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_debug_log_with_error status:debug\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_debug_log_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_debug_log_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_debug_log_with_error*,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_DEBUG_log_with_error() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.debug(.mockRandom(), error: ErrorMock(.mockRandom()), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.info(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_info_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_info_log: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_info_log status:info\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_info_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_info_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_info_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_INFO_log() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.info(.mockRandom(), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.info(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_info_log_with_error_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_info_log_with_error: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_info_log_with_error status:info\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_info_log_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_info_log_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_info_log_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_INFO_log_with_error() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.info(.mockRandom(), error: ErrorMock(.mockRandom()), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.notice(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_notice_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_notice_log: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_notice_log status:notice\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_notice_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_notice_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_notice_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_NOTICE_log() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.notice(.mockRandom(), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.notice(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_notice_log_with_error_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_notice_log_with_error: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_notice_log_with_error status:notice\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_notice_log_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_notice_log_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_notice_log_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_NOTICE_log_with_error() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.notice(.mockRandom(), error: ErrorMock(.mockRandom()), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.warn(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_warn_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_warn_log: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_warn_log status:warn\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_warn_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_warn_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_warn_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_WARN_log() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.warn(.mockRandom(), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.warn(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_warn_log_with_error_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_warn_log_with_error: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_warn_log_with_error status:warn\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_warn_log_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_warn_log_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_warn_log_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_WARN_log_with_error() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.warn(.mockRandom(), error: ErrorMock(.mockRandom()), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.error(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_error_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_error_log: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_error_log status:error\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_error_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_error_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_error_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_ERROR_log() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.error(.mockRandom(), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.error(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_error_log_with_error_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_error_log_with_error: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_error_log_with_error status:error\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_error_log_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_error_log_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_error_log_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_ERROR_log_with_error() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.error(.mockRandom(), error: ErrorMock(.mockRandom()), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.critical(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_critical_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_critical_log: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_critical_log status:critical\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_critical_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_critical_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_critical_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_CRITICAL_log() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.critical(.mockRandom(), attributes: DD.logAttributes())
        }
    }

    /// - api-surface: Logger.critical(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_critical_log_with_error_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_critical_log_with_error: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_critical_log_with_error status:critical\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_critical_log_with_error_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_critical_log_with_error: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_critical_log_with_error,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_CRITICAL_log_with_error() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.critical(.mockRandom(), error: ErrorMock(.mockRandom()), attributes: DD.logAttributes())
        }
    }

    // MARK: - Adding Attributes

    /// - api-surface: Logger.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_add_string_attribute_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_add_string_attribute: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_string_attribute @test_special_string_attribute:customAttribute*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_add_string_attribute_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_add_string_attribute: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_add_string_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_add_STRING_attribute() {
        let attribute = DD.specialStringAttribute()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.addAttribute(forKey: attribute.key, value: attribute.value)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_add_int_attribute_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_add_int_attribute: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_int_attribute @test_special_int_attribute:>10\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_add_int_attribute_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_add_int_attribute: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_add_int_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_add_INT_attribute() {
        let attribute = DD.specialIntAttribute()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.addAttribute(forKey: attribute.key, value: attribute.value)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_add_double_attribute_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_add_double_attribute: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_double_attribute @test_special_double_attribute:>10\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_add_double_attribute_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_add_double_attribute: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_add_double_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_add_DOUBLE_attribute() {
        let attribute = DD.specialDoubleAttribute()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.addAttribute(forKey: attribute.key, value: attribute.value)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.addAttribute(forKey key: AttributeKey, value: AttributeValue)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_add_bool_attribute_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_add_bool_attribute: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_bool_attribute @test_special_bool_attribute:(true OR false)\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_add_bool_attribute_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_add_bool_attribute: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_add_bool_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_add_BOOL_attribute() {
        let attribute = DD.specialBoolAttribute()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.addAttribute(forKey: attribute.key, value: attribute.value)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Removing Attributes

    /// - api-surface: Logger.removeAttribute(forKey key: AttributeKey)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_remove_attribute_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_remove_attribute: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_remove_attribute -@test_special_string_attribute:* -@test_special_int_attribute:* -@test_special_double_attribute:*  -@test_special_bool_attribute:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_remove_attribute_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_remove_attribute: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_remove_attribute,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_remove_attribute() {
        let possibleAttributes = [
            DD.specialStringAttribute(),
            DD.specialIntAttribute(),
            DD.specialDoubleAttribute(),
            DD.specialBoolAttribute()
        ]
        let randomAttribute = possibleAttributes.randomElement()!

        logger.addAttribute(forKey: randomAttribute.key, value: randomAttribute.value)

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.removeAttribute(forKey: randomAttribute.key)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Adding Tags

    /// - api-surface: Logger.addTag(withKey key: String, value: String)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_add_tag_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_add_tag: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_tag test_special_tag:customtag*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_add_tag_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_add_tag: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_add_tag,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_add_tag() {
        let tag = DD.specialTag()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.addTag(withKey: tag.key, value: tag.value)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.add(tag: String)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_add_already_formatted_tag_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_add_already_formatted_tag: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_already_formatted_tag test_special_tag:customtag*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_add_already_formatted_tag_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_add_already_formatted_tag: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:logs_logger_add_already_formatted_tag,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_logs_logger_add_already_formatted_tag() {
        let tag = DD.specialTag()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.add(tag: "\(tag.key):\(tag.value)")
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Removing Tags

    /// - api-surface: Logger.removeTag(withKey key: String)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_remove_tag_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_remove_tag: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_remove_tag -test_special_tag:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_remove_tag_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_remove_tag: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,service:com.datadog.ios.nightly,resource_name:logs_logger_remove_tag} > 0.024"
    /// ```
    func test_logs_logger_remove_tag() {
        let tag = DD.specialTag()
        logger.addTag(withKey: tag.key, value: tag.value)

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.removeTag(withKey: tag.key)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.remove(tag: String)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_remove_already_formatted_tag_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_remove_already_formatted_tag: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_remove_already_formatted_tag -test_special_tag:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_remove_already_formatted_tag_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_remove_already_formatted_tag: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,service:com.datadog.ios.nightly,resource_name:logs_logger_remove_already_formatted_tag} > 0.024"
    /// ```
    func test_logs_logger_remove_already_formatted_tag() {
        let tag = DD.specialTag()
        logger.add(tag: "\(tag.key):\(tag.value)")

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            logger.remove(tag: "\(tag.key):\(tag.value)")
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }
}
