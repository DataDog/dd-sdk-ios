# iOS RUM Collection

<div class="alert alert-info">The iOS RUM collection is in beta. If you have any questions, contact our <a href="https://docs.datadoghq.com/help/" target="_blank">support team</a>.</div>

Send [Real User Monitoring data][rum] to Datadog from your iOS applications with [Datadog's `dd-sdk-ios` client-side RUM library][dd-sdk-ios] and leverage the following features:

* get a global idea about your app’s performance and demographics;
* understand which resources are the slowest;
* analyze errors by OS and device type.

## Setup


1. Declare the library as a dependency depending on your package manager (check our [Releases page][releases] for the recent beta version):

    {{< tabs >}}
    {{% tab "CocoaPods" %}}

You can use [CocoaPods][cocoapods] to install `dd-sdk-ios`:
```
pod 'DatadogSDK', :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => '1.4.0-beta1'
```

[cocoapods]: https://cocoapods.org/

    {{% /tab %}}
    {{% tab "Swift Package Manager (SPM)" %}}

To integrate using Apple's [Swift Package Manager][spm], add the following as a dependency to your `Package.swift`:
```swift
.package(url: "https://github.com/DataDog/dd-sdk-ios.git", .exact("1.4.0-beta1"))
```

[spm]: https://swift.org/package-manager/

    {{% /tab %}}
    {{% tab "Carthage" %}}

You can use [Carthage][carthage] to install `dd-sdk-ios`:
```
github "DataDog/dd-sdk-ios" "1.4.0-beta1"
```

[carthage]: https://github.com/Carthage/Carthage

    {{% /tab %}}
    {{< /tabs >}}

2. Initialize the library with your application context and your [Datadog client token][client-token]. For security reasons, you must use a client token: you cannot use [Datadog API keys][api-keys] to configure the `dd-sdk-ios` library as they would be exposed client-side in the iOS application IPA byte code. For more information about setting up a client token, see the [client token documentation][client-token]. You also need to provide an Application ID (see our [RUM Getting Started page][rum-getting-started]).

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

From here, you have two choices. You can either use our auto instrumentation to let the SDK track RUM Views, Resources, Actions and Errors automatically or you can instrument your app manually to send this data. It is also possible to mix both methods.

## Auto Instrumentation

### RUM Views

To enable RUM Views tracking, use the `.trackUIKitRUMViews(using:)` option when configuring the SDK:
```swift
Datadog.Configuration
   .builderUsing(...)
   .trackUIKitRUMViews(using: predicate)
   .build()
```

The `predicate` must be a class or struct conforming to our `UIKitRUMViewsPredicate` protocol:
```swift
public protocol UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMViewFromPredicate?
}
```

Inside the `rumView(for:)` implementation, your app should decide if a given `UIViewController` instance should start the RUM View or not (return `nil` in such case). The returned value of `RUMViewFromPredicate` should specify at least the `path` for created RUM View. Refer to code documentation comments for more details.

Please note: the SDK will call `rumView(for:)` many times while your app is running. Your implementation of the predicate should not depend on the order of SDK calls.

### RUM Resources

To enable RUM Resources tracking, use the `.track(firstPartyHosts:)` option when configuring the SDK:
```swift
Datadog.Configuration
   .builderUsing(...)
   .track(firstPartyHosts: ["your.domain.com"])
   .build()
```
Also, assign our `DDURLSessionDelegate()` as a `delegate` of the `URLSession` you want to monitor, e.g.:
```swift
let session = URLSession(
    configuration: .default,
    delegate: DDURLSessionDelegate(),
    delegateQueue: nil
)
```

This will make the SDK track requests sent from this instance of the `URLSession`. Requests which URLs match the `firstPartyHosts` will be additionally marked as "first party" in RUM Explorer.

### RUM Actions

To enable RUM Actions tracking, use the `.trackUIKitActions(_:)` option when configuring the SDK:
```
Datadog.Configuration
   .builderUsing(...)
   .trackUIKitActions(true)
   .build()
```

This will make the SDK track all significant taps occuring in the app. For privacy reason, all interactions with the on on-screen keyboard are ignored.

### RUM Errors

By default, when RUM feature is enabled, all "error" and "critical" logs will be reported as the RUM Errors occuring on the current RUM View:
```swift
logger.error("message")
logger.critical("message")
```

Similarly, all finished APM spans marked as error will be reported as the RUM Error occuring on the current RUM View:
```swift
span.setTag(key: OTTags.error, value: true)
```

## Manual Instrumentation

### RUM Views

To manually start and stop the RUM View use the `.startView(viewController:)` and `.stopView(viewController:)` methods available on `Global.rum`.

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
For more details and available options, please refer to the code documentation comments.

### RUM Resources

To manually start and complete the RUM Resource use following methods on `Global.rum`:
* `.startResourceLoading(resourceName:url:httpMethod:)`
* `.stopResourceLoading(resourceName:kind:)`
* `.stopResourceLoadingWithError(resourceName:error:source:)`
* `.stopResourceLoadingWithError(resourceName:errorMessage:source:)`

Example:
```swift
// in your network client:

Global.rum.startResourceLoading(
    resourceName: "resource-name",
    url: requestURL,
    httpMethod: .GET
)

Global.rum.stopResourceLoading(
    resourceName: "resource-name",
    kind: .image,
    httpStatusCode: 200
)
```

Please note: the `String` used for `resourceName` in both calls must be unique for the resource you are calling, so the SDK can match resource start with its completion. 

For more details and available options, please refer to the code documentation comments.

### RUM Actions

To manually register RUM Action, use either:
* `.registerUserAction(type:name:)`
or:
* `.startUserAction(type:name:)`
* and `.stopUserAction(type:)`
on `Global.rum`. The first method can be used for sending actions which have no time (e.g. `.tap`), while the other two should be used for actions which define start and stop time (e.g. `.scroll`).

Example:
```swift
// in your `UIViewController`:

@IBAction func didTapDownloadResourceButton(_ sender: Any) {
    Global.rum.registerUserAction(
        type: .tap,
        name: (sender as? UIButton).currentTitle ?? "",
    )
}
```

Please note: when using `.startUserAction(type:name:)` and `.stopUserAction(type:)`, the action `type` must be the same, so the SDK can match the action start with completion.

For more details and available options, please refer to the code documentation comments.

### RUM Errors

To manually register RUM Error, use `addViewError(message:source:)` or `addViewError(error:source:)` methods on `Global.rum`.

Example:
```swift
// anywhere in your code:

rumMonitor.addViewError(message: "error message.", source: .source)
```

For more details and available options, please refer to the code documentation comments.

[rum]: https://docs.datadoghq.com/real_user_monitoring/data_collected/
[dd-sdk-ios]: https://github.com/DataDog/dd-sdk-ios
[releases]: https://github.com/DataDog/dd-sdk-ios/releases
[client-token]: https://docs.datadoghq.com/account_management/api-app-keys/#client-tokens
[api-keys]: https://docs.datadoghq.com/account_management/api-app-keys/#api-keys
[rum-getting-started]: https://docs.datadoghq.com/real_user_monitoring/installation/?tab=us
