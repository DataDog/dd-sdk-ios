# iOS RUM Collection

Send [Real User Monitoring data][1] to Datadog from your iOS applications with [Datadog's `dd-sdk-ios` client-side RUM SDK][2] and leverage the following features:

* Get a holistic view of your app’s performance and demographics.
* Understand which resources are the slowest.
* Analyze errors by OS and device type.

## Setup

1. Declare the library as a dependency, depending on your package manager. See Datadog's [Releases page][3] for the latest beta version.

    {{< tabs >}}
    {{% tab "CocoaPods" %}}

You can use [CocoaPods][4] to install `dd-sdk-ios`:
```
pod 'DatadogSDK'
```

[4]: https://cocoapods.org/

    {{% /tab %}}
    {{% tab "Swift Package Manager (SPM)" %}}

To integrate the SDK using Apple's [Swift Package Manager][5], add the following as a dependency to your `Package.swift`:
```swift
.package(url: "https://github.com/DataDog/dd-sdk-ios.git", .upToNextMajor(from: "1.0.0"))
```

[5]: https://swift.org/package-manager/

    {{% /tab %}}
    {{% tab "Carthage" %}}

You can use [Carthage][6] to install `dd-sdk-ios`:
```
github "DataDog/dd-sdk-ios"
```

[6]: https://github.com/Carthage/Carthage

    {{% /tab %}}
    {{< /tabs >}}

2. Initialize the library with your application context and your [Datadog client token][7]. For security reasons, you must use a client token: you cannot use [Datadog API keys][9] to configure the `dd-sdk-ios` library as they would be exposed client-side in the iOS application IPA byte code. For more information about setting up a client token, see the [client token documentation][7]. You also need to provide an Application ID (create a Javascript RUM application as explained in the [RUM Getting Started page][8]).

    {{< tabs >}}
    {{% tab "US" %}}

```swift
Datadog.initialize(
    appContext: .init(),
    trackingConsent: trackingConsent,
    configuration: Datadog.Configuration
        .builderUsing(
            rumApplicationID: "<rum_application-id>",
            clientToken: "<client_token>",
            environment: "<environment_name>"
        )
        .set(serviceName: "app-name")
        .build()
)
```

    {{% /tab %}}
    {{% tab "EU" %}}

```swift
Datadog.initialize(
    appContext: .init(),
    trackingConsent: trackingConsent,
    configuration: Datadog.Configuration
        .builderUsing(
            rumApplicationID: "<rum_application-id>",
            clientToken: "<client_token>",
            environment: "<environment_name>"
        )
        .set(serviceName: "app-name")
        .set(endpoint: .eu)
        .build()
)
```

    {{% /tab %}}
    {{< /tabs >}}

    To be compliant with the GDPR regulation, the SDK requires the `trackingConsent` value at initialization.
    The `trackingConsent` can be one of the following values:

    - `.pending` - the SDK starts collecting and batching the data but does not send it to Datadog. The SDK waits for the new tracking consent value to decide what to do with the batched data.
    - `.granted` - the SDK starts collecting the data and sends it to Datadog.
    - `.notGranted` - the SDK does not collect any data: logs, traces and RUM events will not be send to Datadog.

    To change the tracking consent value after the SDK is initialized, use `Datadog.set(trackingConsent:)` API.
    The SDK will change its behavior according to the new value, e.g. if the current tracking consent is `.pending`:

    - if changed to `.granted`, the SDK will send all current and future data to Datadog;
    - if changed to `.notGranted`, the SDK will wipe all current data and will not collect any future data.

3. Configure and register the RUM Monitor. You only need to do it once, usually in your `AppDelegate` code:

    ```swift
    import Datadog

    Global.rum = RUMMonitor.initialize()
    ```

The RUM SDK offers two instrumentation methods:

- Auto-instrumentation (recommended) - the SDK tracks views, resources, actions, and errors automatically.
- Manual instrumentation - you instrument your code to send RUM events.

**Note**: It is possible to mix both methods.

## Auto-instrumentation

### RUM Views

To enable RUM views tracking, use the `.trackUIKitRUMViews()` option when configuring the SDK:
```swift
Datadog.Configuration
   .builderUsing(...)
   .trackUIKitRUMViews()
   .build()

Global.rum = RUMMonitor.initialize()
```

To customize RUM views tracking, use `.trackUIKitRUMViews(using: predicate)` and provide your own implementation of the `predicate` which conforms to `UIKitRUMViewsPredicate` protocol:
```swift
public protocol UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView?
}
```

Inside the `rumView(for:)` implementation, your app should decide if a given `UIViewController` instance should start the RUM view or not (and return `nil` in this case). The returned value of `RUMView` should specify at least the `path` for created the RUM view. Refer to code documentation comments for more details.

**Note**: The SDK calls `rumView(for:)` many times while your app is running. Your implementation of the predicate should not depend on the order of SDK calls.

### RUM Resources

To enable RUM resources tracking, use the `.track(firstPartyHosts:)` option when configuring the SDK:
```swift
Datadog.Configuration
   .builderUsing(...)
   .track(firstPartyHosts: ["your.domain.com"])
   .build()

Global.rum = RUMMonitor.initialize()
```
Also, assign `DDURLSessionDelegate()` as a `delegate` of the `URLSession` you want to monitor, for example:
```swift
let session = URLSession(
    configuration: .default,
    delegate: DDURLSessionDelegate(),
    delegateQueue: nil
)
```

This will make the SDK track requests sent from this instance of the `URLSession`. Requests whose URLs match the `firstPartyHosts` will be additionally marked as "first party" in the RUM Explorer.

### RUM Actions

To enable RUM actions tracking, use the `.trackUIKitActions()` option when configuring the SDK:
```
Datadog.Configuration
   .builderUsing(...)
   .trackUIKitActions()
   .build()

Global.rum = RUMMonitor.initialize()
```

This makes the SDK track all significant taps occurring in the app. For privacy reasons, all interactions with the on-screen keyboard are ignored.

### RUM Errors

All "error" and "critical" logs are be reported as RUM errors and linked to the current RUM view:
```swift
logger.error("message")
logger.critical("message")
```

Similarly, all ended APM spans marked as error are be reported as RUM errors:
```swift
span.setTag(key: OTTags.error, value: true)
```

## Manual Instrumentation

### RUM Views

Use the following methods on `Global.rum` to manually collect RUM resources:
- `.startView(viewController:)`
- `.stopView(viewController:)`

Example:
```swift
// in your `UIViewController`:

override func viewDidAppear(_ animated: Bool) {
  super.viewDidAppear(animated)
  Global.rum.startView(viewController: self)
}

override func viewDidDisappear(_ animated: Bool) {
  super.viewDidDisappear(animated)
  Global.rum.stopView(viewController: self)
}
```
For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.

### RUM Resources

Use the following methods on `Global.rum` to manually collect RUM resources:
* `.startResourceLoading(resourceKey:request:)`
* `.stopResourceLoading(resourceKey:response:)`
* `.stopResourceLoadingWithError(resourceKey:error:)`
* `.stopResourceLoadingWithError(resourceKey:errorMessage:)`

Example:
```swift
// in your network client:

Global.rum.startResourceLoading(
    resourceKey: "resource-key", 
    request: request
)

Global.rum.stopResourceLoading(
    resourceKey: "resource-key",
    response: response
)
```

**Note**: The `String` used for `resourceKey` in both calls must be unique for the resource you are calling. This is necessary for the SDK to match a resource's start with its completion. 

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.

### RUM Actions

To manually register instantaneous RUM actions (e.g: `.tap`), use:
* `.addUserAction(type:name:)`

or for continuous RUM actions (e.g: `.scroll`), use:
* `.startUserAction(type:name:)`
* and `.stopUserAction(type:)`

on `Global.rum`.

Example:
```swift
// in your `UIViewController`:

@IBAction func didTapDownloadResourceButton(_ sender: Any) {
    Global.rum.addUserAction(
        type: .tap,
        name: (sender as? UIButton).currentTitle ?? "",
    )
}
```

**Note**: When using `.startUserAction(type:name:)` and `.stopUserAction(type:)`, the action `type` must be the same. This is necessary for the SDK to match a resource's start with its completion. 

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.

### RUM Errors

Use the following methods on `Global.rum` to manually collect RUM errors:
- `.addError(message:)`
- `.addError(error:)`

Example:
```swift
// anywhere in your code:

Global.rum.addError(message: "error message.")
```

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.

## Data scrubbing

To modify the attributes of a RUM event before it is sent to Datadog or to drop an event entirely, use the event mappers API when configuring the SDK:
```swift
Datadog.Configuration
    .builderUsing(...)
    .setRUMViewEventMapper { viewEvent in 
        return viewEvent
    }
    .setRUMErrorEventMapper { errorEvent in
        return errorEvent
    }
    .setRUMResourceEventMapper { resourceEvent in
        return resourceEvent
    }
    .setRUMActionEventMapper { actionEvent in
        return actionEvent
    }
    .build()
```
Each mapper is a Swift closure with a signature of `(T) -> T?`, where `T` is a concrete RUM event type. This allows changing portions of the event before it gets sent, for example to redact sensitive information in RUM Resource's `url` you may implement a custom `redacted(_:) -> String` function and use it in `RUMResourceEventMapper`:
```swift
.setRUMResourceEventMapper { resourceEvent in
    var resourceEvent = resourceEvent
    resourceEvent.resource.url = redacted(resourceEvent.resource.url)
    return resourceEvent
}
```
Returning `nil` from the mapper will drop the event entirely (it won't be sent to Datadog).

Depending on a given event's type, only some specific properties can be mutated:

| Event Type        | Attribute key                     | Description                                     |
|-------------------|-----------------------------------|-------------------------------------------------|
| RUMViewEvent      | `viewEvent.view.url`              | URL of the view                                 |
| RUMActionEvent    | `actionEvent.action.target?.name` | Name of the action                              |
|                   | `actionEvent.view.url`            | URL of the view linked to this action           |
| RUMErrorEvent     | `errorEvent.error.message`        | Error message                                   |
|                   | `errorEvent.error.stack`          | Stacktrace of the error                         |
|                   | `errorEvent.error.resource?.url`  | URL of the resource the error refers to         |
|                   | `errorEvent.view.url`             | URL of the view linked to this error            |
| RUMResourceEvent  | `resourceEvent.resource.url`      | URL of the resource                             |
|                   | `resourceEvent.view.url`          | URL of the view linked to this resource         |

[1]: https://docs.datadoghq.com/real_user_monitoring/data_collected/
[2]: https://github.com/DataDog/dd-sdk-ios
[3]: https://github.com/DataDog/dd-sdk-ios/releases
[7]: https://docs.datadoghq.com/account_management/api-app-keys/#client-tokens
[8]: https://docs.datadoghq.com/real_user_monitoring/browser/#setup
[9]: https://docs.datadoghq.com/account_management/api-app-keys/#api-keys
