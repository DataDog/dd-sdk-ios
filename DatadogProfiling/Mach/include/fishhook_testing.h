/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_FISHHOOK_TESTING_H_
#define DD_FISHHOOK_TESTING_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH && !TARGET_OS_OSX && defined(DEBUG)

#include <mach/mach.h>
#include "fishhook.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef kern_return_t (*dd_fishhook_protect_callback_t)(
    vm_map_t task, vm_address_t address, vm_size_t size, boolean_t set_maximum,
    vm_prot_t protection, void *context);

/// Rebinds a synthetic non-lazy section using the production rebinding routine.
/// Symbol indices are either INDIRECT_SYMBOL_LOCAL or zero for the name "target".
/// The optional protection callback applies only to this invocation.
void dd_fishhook_rebind_section_for_testing(
    void **slots, size_t slot_count, uint32_t *symbol_indices,
    struct rebinding *binding, dd_fishhook_protect_callback_t protect, void *context);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH && !TARGET_OS_OSX && defined(DEBUG)
#endif // __APPLE__
#endif // DD_FISHHOOK_TESTING_H_
