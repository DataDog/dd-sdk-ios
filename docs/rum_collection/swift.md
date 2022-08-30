---
title: Swift
kind: documentation
beta: true
description: Use SwiftUI to instrument your RUM applications.
further_reading:
- link: 'https://github.com/DataDog/dd-sdk-ios'
  tag: 'GitHub'
  text: 'dd-sdk-ios Source code'
---

## Overview

The Datadog iOS SDK for RUM supports Swift and SwiftUI. 

[Version support information here].

## Initialize the library

For more setup information, see [iOS and tvOS Monitoring][1].

## Track background events

<div class="alert alert-info"><p>Tracking background events may lead to additional sessions, which can impact billing. For questions, <a href="https://docs.datadoghq.com/help/">contact Datadog support.</a></p>
</div>

You can track events such as crashes and network requests when your application is in the background (for example, no active view is available).

Add the following snippet during initialization in your Datadog configuration:

```swift
.trackBackgroundEvents()
```

## Further reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: /real_user_monitoring/ios/#setup