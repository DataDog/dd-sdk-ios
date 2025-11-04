/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_CTOR_PROFILER_TESTING_H_
#define DD_PROFILER_CTOR_PROFILER_TESTING_H_

#ifdef __cplusplus
extern "C" {
#endif

// Internal functions exposed only for testing
bool is_profiling_enabled();
void delete_profiling_defaults();

#ifdef __cplusplus
}
#endif

#endif // DD_PROFILER_CTOR_PROFILER_TESTING_H_
