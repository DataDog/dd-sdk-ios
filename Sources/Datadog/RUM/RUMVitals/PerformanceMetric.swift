/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public enum PerformanceMetric {
    // The amount of time Flutter spent in its `build` method for this view.
    case FLUTTER_BUILD_TIME
    
    // The amount of time Flutter spent rasterizing the view.
    case FLUTTER_RASTER_TIME
    
    // The JavaScript refresh rate of a React Native view.
    case JS_REFRESH_RATE
}
