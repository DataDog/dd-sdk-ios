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

## Troubleshoot errors

An obfuscated stack trace is not helpful as you don't have access to the class name, file path and the line number. It's hard to know where something is happening in your code base. In addition, the code snippet is still minified (one long line of transformed code) which makes the troubleshooting process even harder. See below an example of an minified stack trace:

[Insert obfuscated image here]

On the contrary, a deobfuscated stack trace gives you all the context you need for troubleshooting:

![image_deobfuscated][3]

[1]: https://github.com/DataDog/dd-sdk-ios
[2]: https:///real_user_monitoring/ios/crash_reporting/#symbolicate-reports-using-datadog-ci
[3]: https://raw.githubusercontent.com/DataDog/dd-sdk-ios/master/docs/images/deobfuscated_stacktrace.png

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}