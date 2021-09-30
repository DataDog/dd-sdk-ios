---
title: iOS Error Tracking
kind: documentation
beta: true
further_reading:
- link: '/real_user_monitoring/error_tracking/'
  tag: 'Error Tracking'
  text: 'Get started with Error Tracking'
- link: '/real_user_monitoring/error_tracking/explorer'
  tag: 'Documentation'
  text: 'Visualize Error Tracking data in the Explorer'
---

## Overview

Error Tracking processes errors collected from the iOS SDK. To get started with error tracking, download the latest version of [dd-sdk-ios][1].

If your mobile iOS error is unsymbolicated, upload your dYSM file to Datadog to symbolicate your different stack traces. For any given error, you have access to the file path, the line number, as well as a code snippet for each frame of the related stack trace.

## Upload your mapping file

For more information, see [Symbolicate reports using Datadog CI][2].

[1]: https://github.com/DataDog/dd-sdk-ios
[2]: https://docs.datadoghq.com/real_user_monitoring/ios/crash_reporting/#symbolicate-reports-using-datadog-ci

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}