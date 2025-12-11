/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_SAFE_READ_H
#define DD_SAFE_READ_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void init_main_thread_id_and_safe_read_handlers(void);

bool safe_read_memory(void* addr, void* buffer, size_t size);

void* get_invalid_address(void);

#ifdef __cplusplus
}
#endif

#endif // DD_SAFE_READ_H
