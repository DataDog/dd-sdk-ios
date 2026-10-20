/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// libwebp 1.6.0: encoder, shared DSP, utilities and SharpYUV.
// Source: https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
// SHA-256: e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
//
// When updating, keep this header included first in each C file and preserve
// the VP8GetCPUInfo undef in sharpyuv_cpu.h. Refresh COPYING, PATENTS, AUTHORS
// and the notices in include/DDWebP.h.

#ifndef DD_WEBP_CONFIG_H
#define DD_WEBP_CONFIG_H

#define WEBP_USE_THREAD 1
#define WEBP_EXTERN extern __attribute__((visibility("hidden")))
#define SHARPYUV_EXTERN extern __attribute__((visibility("hidden")))
#pragma GCC visibility push(hidden)

#ifndef DD_WEBP_UNPREFIXED
#include "DDWebPSymbols.h"
#endif
#endif
