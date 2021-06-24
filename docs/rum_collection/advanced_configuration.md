---
title: RUM iOS Advanced Configuration
kind: documentation
further_reading:
  - link: "https://github.com/DataDog/dd-sdk-ios"
    tag: "Github"
    text: "dd-sdk-ios Source code"
  - link: "/real_user_monitoring"
    tag: "Homepage"
    text: "Explore Datadog RUM"
---

If you have not set up the SDK yet, follow the [in-app setup instructions][1] or refer to the [iOS RUM setup documentation][2].

## Enrich user sessions

iOS RUM automatically tracks attributes such as user activity, screens, errors, and network requests. See the [RUM Data Collection documentation][3] to learn about the RUM events and default attributes. You can further enrich user session information and gain finer control over the attributes collected by tracking custom events.

### Custom Views

In addition to [tracking views automatically][4], you can also track specific distinct views (viewControllers) when they become visible and interactive. Stop tracking when the view is no longer visible using the following methods in `Global.rum`:

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
Find more details and available options in `DDRUMMonitor` class.

### Add your own performance timing

In addition to RUM’s default attributes, you can measure where your application is spending its time by using the `addTiming(name:)` API. The timing measure is relative to the start of the current RUM view. For example, you can time how long it takes for your hero image to appear:

```swift
func onHeroImageLoaded() {
    Global.rum.addTiming(name: "hero_image")
} 
```

Once the timing is sent, the timing will be accessible as `@view.custom_timings.<timing_name>` (For example, `@view.custom_timings.hero_image`). You must [create a measure][5] before graphing it in RUM analytics or in dashboards.


### Custom Actions

In addition to [tracking actions automatically][6], you can also track specific custom user actions (taps, clicks, scrolls, etc.) with `addUserAction(type:name:)` API. To manually register instantaneous RUM actions (e.g: `.tap`), on `Global.rum` use:
- `.addUserAction(type:name:)`

or for continuous RUM actions (e.g: `.scroll`), use:
- `.startUserAction(type:name:)`
- `.stopUserAction(type:)`

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

**Note**: When using `.startUserAction(type:name:)` and `.stopUserAction(type:)`, the action `type` must be the same. This is necessary for the SDK to match a action start with its completion. 

Find more details and available options in `DDRUMMonitor` class.

### Custom Resources

In addition to [tracking resources automatically][7], you can also track specific custom resources (network requests, third party provider APIs, etc.). Use the following methods on `Global.rum` to manually collect RUM resources:
- `.startResourceLoading(resourceKey:request:)`
- `.stopResourceLoading(resourceKey:response:)`
- `.stopResourceLoadingWithError(resourceKey:error:)`
- `.stopResourceLoadingWithError(resourceKey:errorMessage:)`

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

Find more details and available options in `DDRUMMonitor` class.

### Custom Errors

To track specific errors, notify `Global.rum` when an error occurs with the message, source, exception, and additional attributes. Refer to the [Error Attributes documentation][8].

```swift
Global.rum.addError(message: "error message.")
```

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.


## Track custom global attributes

In addition to the [default RUM attributes][11] captured by the mobile SDK automatically, you can choose to add additional contextual information, such as custom attributes, to your RUM events to enrich your observability within Datadog. Custom attributes allow you to slice and dice information about observed user behavior (such as cart value, merchant tier, or ad campaign) with code-level information (such as backend services, session timeline, error logs, and network health).

### Track User Sessions
Adding user information to your RUM sessions makes it easy to:
* Follow the journey of a given user
* Know which users are the most impacted by errors
* Monitor performance for your most important users

{{< img src="real_user_monitoring/browser/advanced_configuration/user-api.png" alt="User API in RUM UI"  >}}

The following attributes are **optional**, you should provide **at least one** of them:

| Attribute | Type   | Description                                                                                              |
|-----------|--------|----------------------------------------------------------------------------------------------------------|
| usr.id    | String | Unique user identifier.                                                                                  |
| usr.name  | String | User friendly name, displayed by default in the RUM UI.                                                  |
| usr.email | String | User email, displayed in the RUM UI if the user name is not present. It is also used to fetch Gravatars. |

To identify user sessions, use the `setUserInfo(id:name:email:)` API, for example:

```swift
Datadog.setUserInfo(id: "1234", name: "John Doe", email: "john@doe.com")
```

## Initialization Parameters
 
You can use the following methods in `Datadog.Configuration.Builder` when creating the Datadog configuration to initialize the library:

`set(endpoint: DatadogEndpoint)`
: Sets the Datadog server endpoint where data is sent.

`set(batchSize: BatchSize)`
: Sets the preferred size of batched data uploaded to Datadog. This value impacts the size and number of requests performed by the SDK (small batches mean more requests, but each will be smaller in size). Available values are: `.small`, `.medium` and `.large`.

`set(uploadFrequency: UploadFrequency)`
: Sets the preferred frequency of uploading data to Datadog. Available values are: `.frequent`, `.average` and `.rare`.

RUM configuration:

`enableRUM(_ enabled: Bool)`
: Enables or disables the RUM feature.

`set(rumSessionsSamplingRate: Float)`
: Sets the sampling rate for RUM sessions. The `rumSessionsSamplingRate` value must be between `0.0` and `100.0` - a value of `0.0` means no sessions will be sent, `100.0` means all sessions will be kept. If not configured, the default value of `100.0` is used.

`trackUIKitRUMViews(using predicate: UIKitRUMViewsPredicate)`
: Enables tracking `UIViewControllers` as RUM views. You can use default implementation of `predicate` by calling this API with no parameter (`trackUIKitRUMViews()`) or implement [your own `UIKitRUMViewsPredicate`][4] customized for your app.

`trackUIKitActions(_ enabled: Bool)`
: Enables tracking user interactions (taps) as RUM actions.

`trackURLSession(firstPartyHosts: Set<String>)`
: Enables tracking `URLSession` tasks (network requests) as RUM resources. The `firstPartyHosts` parameter defines hosts that will be categorized as `first-party` resources (if RUM feature is enabled) and will have tracing information injected (if tracing feature is enabled).

`setRUMViewEventMapper(_ mapper: @escaping (RUMViewEvent) -> RUMViewEvent)`
: Sets the data scrubbing callback for views. This can be used to modify view events before they are send to Datadog - see [Modify or drop RUM events][9] for more.

`setRUMResourceEventMapper(_ mapper: @escaping (RUMResourceEvent) -> RUMResourceEvent?)`
: Sets the data scrubbing callback for resources. This can be used to modify or drop resource events before they are send to Datadog - see [Modify or drop RUM events][9] for more.

`setRUMActionEventMapper(_ mapper: @escaping (RUMActionEvent) -> RUMActionEvent?)`
: Sets the data scrubbing callback for actions. This can be used to modify or drop action events before they are send to Datadog - see [Modify or drop RUM events][9] for more.

`setRUMErrorEventMapper(_ mapper: @escaping (RUMErrorEvent) -> RUMErrorEvent?)`
: Sets the data scrubbing callback for errors. This can be used to modify or drop error events before they are send to Datadog - see [Modify or drop RUM events][9] for more.

`setRUMResourceAttributesProvider(_ provider: @escaping (URLRequest, URLResponse?, Data?, Error?) -> [AttributeKey: AttributeValue]?)`
: Sets a closure to provide custom attributes for intercepted resources. The `provider` closure is called for each resource collected by the SDK. This closure is called with task information and may return custom resource attributes or `nil` if no attributes should be attached.

Logging configuration:

`enableLogging(_ enabled: Bool)`
: Enables or disables the Logging feature.

Tracing configuration:

`enableTracing(_ enabled: Bool)`
: Enables or disables the Tracing feature.

`setSpanEventMapper(_ mapper: @escaping (SpanEvent) -> SpanEvent)`
: Sets the data scrubbing callback for spans. This can be used to modify or drop span events before they are send to Datadog.
 
### Automatically track views

To automatically track views (`UIViewControllers`), use the `.trackUIKitRUMViews()` option when configuring the SDK. By default views will be named with the view controller's class name. To customize it use `.trackUIKitRUMViews(using: predicate)` and provide your own implementation of the `predicate` which conforms to `UIKitRUMViewsPredicate` protocol:

```swift
public protocol UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView?
}
```

Inside the `rumView(for:)` implementation, your app should decide if a given `UIViewController` instance should start the RUM view (return value) or not (return `nil`). The returned `RUMView` value must specify the `name` and may provide additional `attributes` for created RUM view.

For instance, you can configure the predicate to use explicit type check for each view controller in your app:
```swift
class YourCustomPredicate: UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView? {
        switch viewController {
        case is HomeViewController:     return .init(name: "Home")
        case is DetailsViewController:  return .init(name: "Details")
        default:                        return nil
        }
    }
}
```

You can even come up with a more dynamic solution depending on your app's architecture. For example, if your view controllers use `accessibilityLabel` consistently, you can name views by the value of accessibility label:
```swift
class YourCustomPredicate: UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView? {
        if let accessibilityLabel = viewController.accessibilityLabel {
            return .init(name: accessibilityLabel)
        } else {
            return nil
        }
    }
}
```

**Note**: The SDK calls `rumView(for:)` many times while your app is running. It is recommended to keep its implementation fast, performant and single-threaded.

### Automatically track network requests

To automatically track resources (network requests) and get their timing information such as time to first byte or DNS resolution, use the `.trackURLSession()` option when configuring the SDK and set `DDURLSessionDelegate` for the `URLSession` that you want to monitor:
```swift
let session = URLSession(
    configuration: .default,
    delegate: DDURLSessionDelegate(),
    delegateQueue: nil
)
```

Also, you can configure first party hosts using `.trackURLSession(firstPartyHosts:)`. This will classify resources matching given domain as "first party" in RUM and will propagate tracing information to your backend (if Tracing feature is enabled).

For instance, you can configure `yourdomain.com` as first party host and enable both RUM and Tracing features:
```swift
Datadog.initialize(
    // ...
    configuration: Datadog.Configuration
        .builderUsing(/* ... */)
        .trackUIKitRUMViews()
        .trackURLSession(firstPartyHosts: ["yourdomain.com"])
        .build()
)

Global.rum = RUMMonitor.initialize()
Global.sharedTracer = Tracer.initialize()

let session = URLSession(
    configuration: .default,
    delegate: DDURLSessionDelegate(),
    delegateQueue: nil
)
```
This will track all requests sent with the instrumented `session`. Requests matching `yourdomain.com` domain will be marked as "first party" and tracing information will be send to your backend to [connect the RUM resource with its Trace][10].

To add custom attributes to resources, use the `.setRUMResourceAttributesProvider(_ :)` option when configuring SDK. By setting attributes provider closure you can return additional attributes to be attached to tracked resource. 

For instance, you may want to add HTTP request and response headers to the RUM resource:
```swift
.setRUMResourceAttributesProvider { request, response, data, error in
    return [
        "request.headers" : redactedHeaders(from: request),
        "response.headers" : redactedHeaders(from: response)
    ]
}

```

### Automatically track RUM errors

All "error" and "critical" logs send with `Logger` are automatically reported as RUM errors and linked to the current RUM view:
```swift
let logger = Logger.builder.build()

logger.error("message")
logger.critical("message")
```

Similarly, all finished spans marked as error are be reported as RUM errors:
```swift
let span = Global.sharedTracer.startSpan(operationName: "operation")
// ... capture the `error`
span.setError(error)
span.finish()
```

## Modify or drop RUM events

To modify attributes of a RUM event before it is sent to Datadog or to drop an event entirely, use the event mappers API when configuring the SDK:
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
Each mapper is a Swift closure with a signature of `(T) -> T?`, where `T` is a concrete RUM event type. This allows changing portions of the event before it gets sent. For example to redact sensitive information in RUM Resource's `url` you may implement a custom `redacted(_:) -> String` function and use it in `RUMResourceEventMapper`:

```swift
.setRUMResourceEventMapper { resourceEvent in
    var resourceEvent = resourceEvent
    resourceEvent.resource.url = redacted(resourceEvent.resource.url)
    return resourceEvent
}
```

Returning `nil` from the error, resource or action mapper will drop the event entirely (it won't be sent to Datadog). The value returned from the view event mapper must be not `nil` (to drop views customize your implementation of `UIKitRUMViewsPredicate` - read more in [tracking views automatically][4]).

Depending on the event's type, only some specific properties can be mutated:

| Event Type       | Attribute key                     | Description                             |
|------------------|-----------------------------------|-----------------------------------------|
| RUMViewEvent     | `viewEvent.view.name`             | Name of the view                        |
|                  | `viewEvent.view.url`              | URL of the view                         |
| RUMActionEvent   | `actionEvent.action.target?.name` | Name of the action                      |
|                  | `actionEvent.view.url`            | URL of the view linked to this action   |
| RUMErrorEvent    | `errorEvent.error.message`        | Error message                           |
|                  | `errorEvent.error.stack`          | Stacktrace of the error                 |
|                  | `errorEvent.error.resource?.url`  | URL of the resource the error refers to |
|                  | `errorEvent.view.url`             | URL of the view linked to this error    |
| RUMResourceEvent | `resourceEvent.resource.url`      | URL of the resource                     |
|                  | `resourceEvent.view.url`          | URL of the view linked to this resource |

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}


[1]: https://app.datadoghq.com/rum/application/create
[2]: /real_user_monitoring/ios
[3]: /real_user_monitoring/ios/data_collected
[4]: #automatically-track-views
[5]: https://docs.datadoghq.com/real_user_monitoring/explorer/?tab=measures#setup-facets-and-measures
[6]: #automatically-track-actions
[7]: #automatically-track-network-requests
[8]: /real_user_monitoring/ios/data_collected/?tab=error#error-attributes
[9]: #modify-or-drop-rum-events
[10]: https://docs.datadoghq.com/real_user_monitoring/connect_rum_and_traces?tab=browserrum
[11]: /real_user_monitoring/ios/data_collected?tab=session#default-attributes
