---
beta: true
dependencies: 
- https://github.com/DataDog/dd-sdk-ios/blob/master/docs/web_view_tracking.md
title: iOS Web View Tracking
kind: documentation
description: Monitor web views in your hybrid iOS applications.
further_reading:
- link: "/real_user_monitoring/ios/"
  tag: "Documentation"
  text: "iOS Monitoring"
- link: "/real_user_monitoring/browser/"
  tag: "Documentation"
  text: "Browser Monitoring"
---

## Overview

Real User Monitoring allows you to monitor web views and eliminate blind spots in your hybrid iOS and tvOS applications.

You can:

- Track user journeys across web and native components in mobile applications
- Scope the root cause of latency to web pages or native components in mobile applications
- Support users that have difficulty loading web pages on mobile devices

## Setup

### Prerequisites

Set up the web page you want rendered on your mobile iOS and tvOS application with the Browser SDK first. For more information, see [RUM Browser Monitoring][1].

### Update your existing SDK setup

1. Download the [latest version][2] of the RUM iOS SDK.
2. Edit your existing iOS SDK setup from [RUM iOS Monitoring][3].
3. Add tracking for web views with the following example:

   ```
   // Start tracking
   webView.configuration.userContentController.trackDatadogEvents(in: hosts)
   // Stop tracking
   // Note: This method must be called when the webview is de-initialized.
   webView.configuration.userContentController.stopTrackingDatadogEvents()
   ```

## Access your web views

Your web views appear as events and views in the [RUM Explorer][4]. Filter on your iOS and tvOS applications and click a session. A side panel with a list of events in the session appears. 

{{< img src="real_user_monitoring/ios/ios-webview-tracking.png" alt="Webview events captured in a session in the RUM Explorer" style="width:100%;">}}

Click **Open View waterfall** to navigate from the session to a resource waterfall visualization in the view's **Performance** tab. 

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: https://docs.datadoghq.com/real_user_monitoring/browser/#npm
[2]: https://github.com/DataDog/dd-sdk-ios/releases/tag/1.10.0-beta1
[3]: https://docs.datadoghq.com/real_user_monitoring/ios/
[4]: https://app.datadoghq.com/rum/explorer