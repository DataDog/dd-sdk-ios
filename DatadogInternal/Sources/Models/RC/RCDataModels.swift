/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// This file was generated from JSON Schema. Do not modify it directly.

// swiftlint:disable all

/// iOS RUM SDK Remote Configuration
public struct RemoteConfiguration: Codable {
    public let platform: String = "ios"

    public let profiling: Profiling?

    public let rum: RUM?

    public let sessionReplay: SessionReplay?

    public let trace: Trace?

    public enum CodingKeys: String, CodingKey {
        case platform = "platform"
        case profiling = "profiling"
        case rum = "rum"
        case sessionReplay = "sessionReplay"
        case trace = "trace"
    }

    /// iOS RUM SDK Remote Configuration
    ///
    /// - Parameters:
    ///   - profiling:
    ///   - rum:
    ///   - sessionReplay:
    ///   - trace:
    public init(
        profiling: Profiling? = nil,
        rum: RUM? = nil,
        sessionReplay: SessionReplay? = nil,
        trace: Trace? = nil
    ) {
        self.profiling = profiling
        self.rum = rum
        self.sessionReplay = sessionReplay
        self.trace = trace
    }

    public struct Profiling: Codable {
        public let applicationLaunchSampleRate: Double?

        public let continuousSampleRate: Double?

        public enum CodingKeys: String, CodingKey {
            case applicationLaunchSampleRate = "applicationLaunchSampleRate"
            case continuousSampleRate = "continuousSampleRate"
        }

        ///
        /// - Parameters:
        ///   - applicationLaunchSampleRate:
        ///   - continuousSampleRate:
        public init(
            applicationLaunchSampleRate: Double? = nil,
            continuousSampleRate: Double? = nil
        ) {
            self.applicationLaunchSampleRate = applicationLaunchSampleRate
            self.continuousSampleRate = continuousSampleRate
        }
    }

    public struct RUM: Codable {
        public let appHang: AppHang?

        /// UUID of the RUM application
        public let applicationId: String

        public let longTask: LongTask?

        public let telemetrySampleRate: Double?

        public let trackAnonymousUser: Bool?

        public let trackBackgroundEvents: Bool?

        public let trackFrustrations: Bool?

        public let trackMemoryWarnings: Bool?

        public let trackResources: Bool?

        public let trackSlowFrames: Bool?

        public let trackUserInteractions: Bool?

        public let trackWatchdogTerminations: Bool?

        public let vitalsUpdateFrequency: VitalsUpdateFrequency?

        public enum CodingKeys: String, CodingKey {
            case appHang = "appHang"
            case applicationId = "applicationId"
            case longTask = "longTask"
            case telemetrySampleRate = "telemetrySampleRate"
            case trackAnonymousUser = "trackAnonymousUser"
            case trackBackgroundEvents = "trackBackgroundEvents"
            case trackFrustrations = "trackFrustrations"
            case trackMemoryWarnings = "trackMemoryWarnings"
            case trackResources = "trackResources"
            case trackSlowFrames = "trackSlowFrames"
            case trackUserInteractions = "trackUserInteractions"
            case trackWatchdogTerminations = "trackWatchdogTerminations"
            case vitalsUpdateFrequency = "vitalsUpdateFrequency"
        }

        ///
        /// - Parameters:
        ///   - appHang:
        ///   - applicationId: UUID of the RUM application
        ///   - longTask:
        ///   - telemetrySampleRate:
        ///   - trackAnonymousUser:
        ///   - trackBackgroundEvents:
        ///   - trackFrustrations:
        ///   - trackMemoryWarnings:
        ///   - trackResources:
        ///   - trackSlowFrames:
        ///   - trackUserInteractions:
        ///   - trackWatchdogTerminations:
        ///   - vitalsUpdateFrequency:
        public init(
            appHang: AppHang? = nil,
            applicationId: String,
            longTask: LongTask? = nil,
            telemetrySampleRate: Double? = nil,
            trackAnonymousUser: Bool? = nil,
            trackBackgroundEvents: Bool? = nil,
            trackFrustrations: Bool? = nil,
            trackMemoryWarnings: Bool? = nil,
            trackResources: Bool? = nil,
            trackSlowFrames: Bool? = nil,
            trackUserInteractions: Bool? = nil,
            trackWatchdogTerminations: Bool? = nil,
            vitalsUpdateFrequency: VitalsUpdateFrequency? = nil
        ) {
            self.appHang = appHang
            self.applicationId = applicationId
            self.longTask = longTask
            self.telemetrySampleRate = telemetrySampleRate
            self.trackAnonymousUser = trackAnonymousUser
            self.trackBackgroundEvents = trackBackgroundEvents
            self.trackFrustrations = trackFrustrations
            self.trackMemoryWarnings = trackMemoryWarnings
            self.trackResources = trackResources
            self.trackSlowFrames = trackSlowFrames
            self.trackUserInteractions = trackUserInteractions
            self.trackWatchdogTerminations = trackWatchdogTerminations
            self.vitalsUpdateFrequency = vitalsUpdateFrequency
        }

        public struct AppHang: Codable {
            public let enabled: Bool?

            /// Minimum main-thread freeze duration in milliseconds to report as an app hang
            public let threshold: Double?

            public enum CodingKeys: String, CodingKey {
                case enabled = "enabled"
                case threshold = "threshold"
            }

            ///
            /// - Parameters:
            ///   - enabled:
            ///   - threshold: Minimum main-thread freeze duration in milliseconds to report as an app hang
            public init(
                enabled: Bool? = nil,
                threshold: Double? = nil
            ) {
                self.enabled = enabled
                self.threshold = threshold
            }
        }

        public struct LongTask: Codable {
            public let enabled: Bool?

            /// Minimum main-thread task duration in milliseconds to report as a long task
            public let threshold: Double?

            public enum CodingKeys: String, CodingKey {
                case enabled = "enabled"
                case threshold = "threshold"
            }

            ///
            /// - Parameters:
            ///   - enabled:
            ///   - threshold: Minimum main-thread task duration in milliseconds to report as a long task
            public init(
                enabled: Bool? = nil,
                threshold: Double? = nil
            ) {
                self.enabled = enabled
                self.threshold = threshold
            }
        }

        public enum VitalsUpdateFrequency: String, Codable {
            case frequent = "frequent"
            case average = "average"
            case rare = "rare"
            case never = "never"
        }
    }

    public struct SessionReplay: Codable {
        public let imagePrivacy: ImagePrivacy?

        public let sampleRate: Double?

        public let textAndInputPrivacy: TextAndInputPrivacy?

        public let touchPrivacy: TouchPrivacy?

        public enum CodingKeys: String, CodingKey {
            case imagePrivacy = "imagePrivacy"
            case sampleRate = "sampleRate"
            case textAndInputPrivacy = "textAndInputPrivacy"
            case touchPrivacy = "touchPrivacy"
        }

        ///
        /// - Parameters:
        ///   - imagePrivacy:
        ///   - sampleRate:
        ///   - textAndInputPrivacy:
        ///   - touchPrivacy:
        public init(
            imagePrivacy: ImagePrivacy? = nil,
            sampleRate: Double? = nil,
            textAndInputPrivacy: TextAndInputPrivacy? = nil,
            touchPrivacy: TouchPrivacy? = nil
        ) {
            self.imagePrivacy = imagePrivacy
            self.sampleRate = sampleRate
            self.textAndInputPrivacy = textAndInputPrivacy
            self.touchPrivacy = touchPrivacy
        }

        public enum ImagePrivacy: String, Codable {
            case maskNone = "mask_none"
            case maskNonBundledOnly = "mask_non_bundled_only"
            case maskAll = "mask_all"
        }

        public enum TextAndInputPrivacy: String, Codable {
            case maskSensitiveInputs = "mask_sensitive_inputs"
            case maskAllInputs = "mask_all_inputs"
            case maskAll = "mask_all"
        }

        public enum TouchPrivacy: String, Codable {
            case show = "show"
            case hide = "hide"
        }
    }

    public struct Trace: Codable {
        public let sampleRate: Double?

        public let traceContextInjection: TraceContextInjection?

        /// Per-host distributed tracing configuration. Aligns with browser's allowedTracingUrls model (without regex matching).
        public let tracedHosts: [TracedHosts]?

        public enum CodingKeys: String, CodingKey {
            case sampleRate = "sampleRate"
            case traceContextInjection = "traceContextInjection"
            case tracedHosts = "tracedHosts"
        }

        ///
        /// - Parameters:
        ///   - sampleRate:
        ///   - traceContextInjection:
        ///   - tracedHosts: Per-host distributed tracing configuration. Aligns with browser's allowedTracingUrls model (without regex matching).
        public init(
            sampleRate: Double? = nil,
            traceContextInjection: TraceContextInjection? = nil,
            tracedHosts: [TracedHosts]? = nil
        ) {
            self.sampleRate = sampleRate
            self.traceContextInjection = traceContextInjection
            self.tracedHosts = tracedHosts
        }

        public enum TraceContextInjection: String, Codable {
            case all = "all"
            case sampled = "sampled"
        }

        public struct TracedHosts: Codable {
            public let host: String

            public let propagatorTypes: [PropagatorTypes]

            public enum CodingKeys: String, CodingKey {
                case host = "host"
                case propagatorTypes = "propagatorTypes"
            }

            ///
            /// - Parameters:
            ///   - host:
            ///   - propagatorTypes:
            public init(
                host: String,
                propagatorTypes: [PropagatorTypes]
            ) {
                self.host = host
                self.propagatorTypes = propagatorTypes
            }

            public enum PropagatorTypes: String, Codable {
                case datadog = "datadog"
                case b3 = "b3"
                case b3multi = "b3multi"
                case tracecontext = "tracecontext"
            }
        }
    }
}

// Generated from https://github.com/DataDog/dd-go/blob/96df9f634c7c1215670fce6a12adee84ae5bc392/remote-config/apps/rc-schema-validation/schemas/rum-sdk-config/STAGING/ios.json