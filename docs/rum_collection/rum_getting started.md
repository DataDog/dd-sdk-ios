# Getting Started with iOS RUM Collection

Datadog Real User Monitoring (RUM) enables you to visualize and analyze the real-time performance and user journeys of your application's individual users.

## Setup

1. Declare [dd-sdk-ios][1] as a dependency, depending on your package manager.


| Package Manager                | Installation Method | 
|:------------------------------:|:-------------------:|
|    [CocoaPods][2]              |  `pod 'DatadogSDK'` |   
|    [Swift Package Manager][3]  |  `.package(url: "https://github.com/DataDog/dd-sdk-ios.git", .upToNextMajor(from: "1.0.0"))` |
|    [Carthage][4]               | `github "DataDog/dd-sdk-ios"` |
    


[2]: https://cocoapods.org/
[3]: https://swift.org/package-manager/
[4]: https://github.com/Carthage/Carthage

2. [Specify application details in Datadog UI][5] to generate a unique Datadog Application ID, and Client Token.

{{< img src="docs/images/screenshot_rum.png" alt="RUM Event hierarchy" style="width:50%;border:none" >}}).

To ensure safety of your data, you must use a client token: you cannot use [Datadog API keys][6] to configure the `dd-sdk-android` library as they would be exposed client-side in the Android application APK byte code. For more information about setting up a client token, see the [client token documentation][7]

3. Initialize the library with application context and start sending data:

    {{< tabs >}}
    {{% tab "US" %}}

```swift
Datadog.initialize(
    appContext: .init(),
    configuration: Datadog.Configuration
        .builderUsing(
            rumApplicationID: "<rum_application-id>",
            clientToken: "<client_token>",
            environment: "<environment_name>"
        )
        .trackUIKitRUMViews()
        .track(firstPartyHosts: ["your.domain.com"])
        .trackUIKitActions()
        .set(serviceName: "app-name")
        .build()
)
```

    {{% /tab %}}
    {{% tab "EU" %}}

```swift
Datadog.initialize(
    appContext: .init(),
    configuration: Datadog.Configuration
        .builderUsing(
            rumApplicationID: "<rum_application-id>",
            clientToken: "<client_token>",
            environment: "<environment_name>"
        )
        .trackUIKitRUMViews()
        .track(firstPartyHosts: ["your.domain.com"])
        .trackUIKitActions()
        .set(serviceName: "app-name")
        .set(endpoint: .eu)
        .build()
)
```

    {{% /tab %}}
    {{< /tabs >}}

RUM SDK automatically tracks user sessions, depending on options provided at SDK initialization. Learn more about [initialization parameters][8] for SDK configuartion options.

3. Configure and register the RUM Monitor. You only need to do it once, usually in your `AppDelegate` code:

    ```swift
    import Datadog

    Global.rum = RUMMonitor.initialize()
    ```

4. To monitor requests sent from `URLSession` instance, assign `DDURLSessionDelegate()` as a `delegate` of that `URLSession`

```swift
let session = URLSession(
    configuration: .default,
    delegate: DDURLSessionDelegate(),
    delegateQueue: nil
)
```

## Initialization Parameters
 
The following methods in `Datadog.Configuration` can be used to initialize the library:
 
| Method                           | Description                                                                                                                                                                                                                                                             |
|----------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `set(serviceName: "service-name")` | Set `<SERVICE_NAME>` as default value for the `service` [standard attribute][9] attached to all logs and traces sent to Datadog (this can be overriden in each Logger)    |
| `trackUIKitActions()` | Enables tracking User interactions (such as Tap, Scroll or Swipe). For privacy reasons, all interactions with the on-screen keyboard are ignored |
| `trackUIKitRUMViews()` | Enables tracking for `ViewController` as a RUM View. You can also [customize view tracking][10] by using your own implementation of the `predicate` conforming `UIKitRUMViewsPredicate` protocol  |
| `track(firstPartyHosts: ["your.domain.com"])` | Enables tracking for RUM resources. Requests whose URLs match the `firstPartyHosts` will be tagged as "first party" in the RUM events |
| `set(endpoint: .eu)` | Switch target endpoints for data to EU for europe users  |


[1]: https://github.com/DataDog/dd-sdk-ios
[5]: https://app.datadoghq.com/rum/create
[6]: https://docs.datadoghq.com/account_management/api-app-keys/#api-keys
[7]: https://docs.datadoghq.com/account_management/api-app-keys/#client-tokens
[8]: /real_user_monitoring/ios/advanced_configuration/initialization_parameters
[9]: https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging/
[10]: /real_user_monitoring/ios/view_tracking/custom_views