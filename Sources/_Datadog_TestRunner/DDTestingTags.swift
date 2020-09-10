/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct DDTestingTags {
    static let testSuite       = "test.suite"
    static let testName        = "test.name"
    static let testFramework   = "test.framework"
    static let testTraits      = "test.traits"
    static let testCode        = "test.code"

    static let testType        = "test.type"
    static let typeTest        = "test"
    static let typeBenchmark   = "benchmark"

    static let testStatus      = "test.status"
    static let statusPass      = "pass"
    static let statusFail      = "fail"
    static let statusSkip      = "skip"

    static let spanType        = "span.type"

    static let logSource       = "source"
}

internal struct DDCITags {
    static let gitRepository    = "git.repository_url"
    static let gitCommit        = "git.commit_sha"
    static let gitBranch        = "git.branch"
    static let gitTag           = "git.tag"

    static let buildSourceRoot  = "build.source_root"

    static let ciProvider       = "ci.provider.name"
    static let ciPipelineId     = "ci.pipeline.id"
    static let ciPipelineNumber = "ci.pipeline.number"
    static let ciPipelineURL    = "ci.pipeline.url"
    static let ciJobURL         = "ci.job.url"
    static let ciWorkspacePath  = "ci.workspace_path"
}

internal struct DDBenchmarkingTags {
    static let durationMean                 = "benchmark.duration.mean"
    static let benchmarkRuns                = "benchmark.runs"
    static let memoryTotalBytes             = "benchmark.memory.total_bytes_allocations"
    static let memoryMeanBytes_allocations  = "benchmark.memory.mean_bytes_allocations"
}
