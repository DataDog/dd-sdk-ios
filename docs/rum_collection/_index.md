---
title: RUM iOS Monitoring
kind: documentation
beta: true
description: "Collect RUM data from your iOS applications."
aliases:
    - /real_user_monitoring/ios/getting_started
further_reading:
  - link: "https://github.com/DataDog/dd-sdk-ios"
    tag: "Github"
    text: "dd-sdk-ios Source Code"
  - link: "/real_user_monitoring"
    tag: "Documentation"
    text: "Learn how to explore your RUM data"
---

Datadog Real User Monitoring (RUM) enables you to visualize and analyze the real-time performance and user journeys of your application's individual users. 

## Setup

1. Declare the SDK as a dependency.
2. Specify application details in the UI.
3. Initialize the library.
4. Initialize the RUM Monitor, `DDURLSessionDelegate`, and start sending data.

**Note:** The minimum supported version for the Datadog iOS SDK is iOS v11+.

### Declare SDK as dependency

1. Declare [dd-sdk-ios][1] as a dependency, depending on your package manager.


| Package manager            | Installation method                                                                         |
|----------------------------|---------------------------------------------------------------------------------------------|
| [CocoaPods][2]             | `pod 'DatadogSDK'`                                                                          |
| [Swift Package Manager][3] | `.package(url: "https://github.com/DataDog/dd-sdk-ios.git", .upToNextMajor(from: "1.0.0"))` |
| [Carthage][4]              | `github "DataDog/dd-sdk-ios"`                                                               |

### Specify application details in UI

1. In **UX Monitoring** > **RUM Applications**, click **New Application**.
2. Select `iOS` as your **Application Type** in the [Datadog UI][5] and provide a new application name to generate a unique Datadog application ID and client token.

{{< img src="real_user_monitoring/ios/screenshot_rum.png" alt="RUM Event hierarchy" style="width:100%;border:none" >}}

To keep your data safe, do not use a [Datadog API key][6] to configure the `dd-sdk-ios` library. Instead, use the client token to prevent your API key from being publicly exposed on the client side in the iOS application byte code.

For more information about setting up a client token, see the [Client token documentation][7].

### Initialize the library

{{< site-region region="us" >}}
{{< tabs >}}
{{% tab "Swift" %}}

```swift
Datadog.initialize(
    appContext: .init(),
    trackingConsent: trackingConsent,
    configuration: Datadog.Configuration
        .builderUsing(clientToken: "<client_token>", environment: "<environment_name>")
        .set(serviceName: "app-name")
        .set(endpoint: .us1)
        .build()
)
```
{{% /tab %}}
{{% tab "Objective-C" %}}
```objective-c
DDConfigurationBuilder *builder = [DDConfiguration builderWithClientToken:@"<client_token>"
                                                                  environment:@"<environment_name>"];
[builder setWithServiceName:@"app-name"];
[builder setWithEndpoint:[DDEndpoint us1]];

[DDDatadog initializeWithAppContext:[DDAppContext new]
                    trackingConsent:trackingConsent
                      configuration:[builder build]];
```
{{% /tab %}}
{{< /tabs >}}
{{< /site-region >}}

{{< site-region region="eu" >}}
{{< tabs >}}
{{% tab "Swift" %}}
```swift
Datadog.initialize(
    appContext: .init(),
    trackingConsent: trackingConsent,
    configuration: Datadog.Configuration
        .builderUsing(
            rumApplicationID: "<rum_application_id>",
            clientToken: "<client_token>",
            environment: "<environment_name>"
        )
        .set(serviceName: "app-name")
        .trackUIKitRUMViews()
        .trackUIKitActions()
        .trackURLSession()
        .build()
)
```
{{% /tab %}}
{{% tab "Objective-C" %}}
```objective-c
DDConfigurationBuilder *builder = [DDConfiguration builderWithRumApplicationID:@"<rum_application_id>"
                                                                   clientToken:@"<client_token>"
                                                                   environment:@"<environment_name>"];
[builder setWithServiceName:@"app-name"];
[builder setWithEndpoint:[DDEndpoint us1]];
[builder trackUIKitRUMViews];
[builder trackUIKitRUMActions];
[builder trackURLSessionWithFirstPartyHosts:[NSSet new]];

[DDDatadog initializeWithAppContext:[DDAppContext new]
                    trackingConsent:trackingConsent
                        configuration:[builder build]];
```
{{% /tab %}}
{{< /tabs >}}
{{< /site-region >}}

The RUM SDK automatically tracks user sessions depending on options provided at the SDK initialization. To add GDPR compliance for your EU users and other [initialization parameters][9] to the SDK configuration, see the [Set tracking consent documentation][8].

### Initialize RUM Monitor and `DDURLSessionDelegate`

Configure and register the RUM Monitor. You only need to do it once, usually in your `AppDelegate` code:

{{< tabs >}}
{{% tab "Swift" %}}
```swift
import Datadog

Global.rum = RUMMonitor.initialize()
```
{{% /tab %}}
{{% tab "Objective-C" %}}
```objective-c
@import DatadogObjc;

DDGlobal.rum = [[DDRUMMonitor alloc] init];
```
{{% /tab %}}
{{< /tabs >}}

To monitor requests sent from the `URLSession` instance as resources, assign `DDURLSessionDelegate()` as a `delegate` of that `URLSession`:

{{< tabs >}}
{{% tab "Swift" %}}
```swift
let session = URLSession(
    configuration: .default,
    delegate: DDURLSessionDelegate(),
    delegateQueue: nil
)
```
{{% /tab %}}
{{% tab "Objective-C" %}}
```objective-c
NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                      delegate:[[DDNSURLSessionDelegate alloc] init]
                                                 delegateQueue:NULL];
```
{{% /tab %}}
{{< /tabs >}}

## iOS Crash Reporting and Error Tracking

Crash Reporting and Error Tracking for iOS displays any issues and latest available errors. You can view error details and attributes including JSON in the RUM Explorer. 

<div class="alert alert-info"><p>Crash Reporting and Error Tracking is available in beta. To sign up, see <a href="https://docs.datadoghq.com/real_user_monitoring/ios/crash_reporting">Crash Reporting (beta)</a>.</p>
</div>

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}


[1]: https://github.com/DataDog/dd-sdk-ios
[2]: https://cocoapods.org/
[3]: https://swift.org/package-manager/
[4]: https://github.com/Carthage/Carthage
[5]: https://app.datadoghq.com/rum/create
[6]: https://docs.datadoghq.com/account_management/api-app-keys/#api-keys
[7]: https://docs.datadoghq.com/account_management/api-app-keys/#client-tokens
[8]: /real_user_monitoring/ios/advanced_configuration/#set-tracking-consent-gdpr-compliance
[9]: /real_user_monitoring/ios/advanced_configuration/#initialization-parameters