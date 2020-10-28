# iOS RUM Collection

<div class="alert alert-info">The iOS RUM collection is in beta. If you have any questions, contact the <a href="https://docs.datadoghq.com/help/" target="_blank">support team</a>.</div>

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
pod 'DatadogSDK', :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => '1.4.0-beta1'
```

[4]: https://cocoapods.org/

    {{% /tab %}}
    {{% tab "Swift Package Manager (SPM)" %}}

To integrate the SDK using Apple's [Swift Package Manager][5], add the following as a dependency to your `Package.swift`:
```swift
.package(url: "https://github.com/DataDog/dd-sdk-ios.git", .exact("1.4.0-beta1"))
```

[5]: https://swift.org/package-manager/

    {{% /tab %}}
    {{% tab "Carthage" %}}

You can use [Carthage][6] to install `dd-sdk-ios`:
```
github "DataDog/dd-sdk-ios" "1.4.0-beta1"
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
    configuration: Datadog.Configuration
        .builderUsing(
            rumApplicationID: "<rum_application-id>",
            clientToken: "<client_token>",
            environment: "<environment_name>"
        )
        .set(serviceName: "app-name")
        .set(rumEndpoint: .eu)
        .build()
)
```

    {{% /tab %}}
    {{< /tabs >}}

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

To enable RUM views tracking, use the `.trackUIKitRUMViews(using:)` option when configuring the SDK:
```swift
Datadog.Configuration
   .builderUsing(...)
   .trackUIKitRUMViews(using: predicate)
   .build()
```

`predicate` must be a type that conforms to `UIKitRUMViewsPredicate` protocol:
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

To enable RUM actions tracking, use the `.trackUIKitActions(_:)` option when configuring the SDK:
```
Datadog.Configuration
   .builderUsing(...)
   .trackUIKitActions(true)
   .build()
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
* `.startResourceLoading(resourceKey:url:httpMethod:)`
* `.stopResourceLoading(resourceKey:kind:)`
* `.stopResourceLoadingWithError(resourceKey:error:)`
* `.stopResourceLoadingWithError(resourceKey:errorMessage:)`

Example:
```swift
// in your network client:

Global.rum.startResourceLoading(
    resourceKey: "resource-key",
    url: requestURL,
    httpMethod: .GET
)

Global.rum.stopResourceLoading(
    resourceKey: "resource-key",
    kind: .image,
    httpStatusCode: 200
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

**Note**: when using `.startUserAction(type:name:)` and `.stopUserAction(type:)`. This is necessary for the SDK to match a resource's start with its completion. 

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.

### RUM Errors

Use the following methods on `Global.rum` to manually collect RUM errors:
- `.addError(message:source:)`
- `.addError(error:source:)`

Example:
```swift
// anywhere in your code:

Global.rum.addError(message: "error message.", source: .source)
```

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.

[1]: https://docs.datadoghq.com/real_user_monitoring/data_collected/
[2]: https://github.com/DataDog/dd-sdk-ios
[3]: https://github.com/DataDog/dd-sdk-ios/releases
[7]: https://docs.datadoghq.com/account_management/api-app-keys/#client-tokens
[8]: https://docs.datadoghq.com/real_user_monitoring/browser/#setup
[9]: https://docs.datadoghq.com/account_management/api-app-keys/#api-keys
