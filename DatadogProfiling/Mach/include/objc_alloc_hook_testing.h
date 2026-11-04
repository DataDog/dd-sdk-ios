/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_OBJC_ALLOC_HOOK_TESTING_H_
#define DD_OBJC_ALLOC_HOOK_TESTING_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#ifdef __cplusplus
extern "C" {
#endif

/// Fail one installation after the allocation IMP has been installed.
/// The allocation trampoline must remain forwarding and observation disabled.
#if DEBUG
void dd_objc_alloc_hook_test_fail_after_alloc_once(void);
#endif

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_OBJC_ALLOC_HOOK_TESTING_H_
