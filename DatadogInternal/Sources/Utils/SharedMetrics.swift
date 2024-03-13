/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Common definitions for telemetries.
public enum BasicMetric {
    /// Basic Metric type key.
    public static let typeKey = "metric_type"
}

/// Definition of "Method Called" telemetry.
public enum MethodCalledMetric {
    /// The name of this metric, included in telemetry log.
    /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
    public static let name = "Method Called"
    /// Metric type value.
    public static let typeValue = "method called"

    /// The key for operation name.
    public static let operationName = "operation_name"
    /// The key for caller class.
    public static let callerClass = "caller_class"
    /// The key for is successful.
    public static let isSuccessful = "is_successful"
    /// They key for start time.
    public static let startTime = "start_time"
    /// The key for execution time.
    public static let executionTime = "execution_time"

    public enum Device {
        /// The key for device object.
        public static let key = "device"

        /// The key for device model name.
        public static let model = "model"
        /// The key for device brand.
        public static let brand = "brand"
        /// The key for CPU architecture.
        public static let architecture = "architecture"
    }

    /// The key for OS object.
    public enum OS {
        /// The key for operating system object.
        public static let key = "os"

        /// The key for OS name.
        public static let name = "name"
        /// The key for OS version.
        public static let version = "version"
        /// The key for OS build.
        public static let build = "build"
    }
}
