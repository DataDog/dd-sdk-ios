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

### Custom Actions

In addition to [tracking actions automatically][5], you can also track specific custom user actions (taps, clicks, scrolls, etc.) with `RumMonitor#addUserAction`. To manually register instantaneous RUM actions (e.g: `.tap`), on `Global.rum` use:
- `.addUserAction(type:name:)`

or for continuous RUM actions (e.g: `.scroll`), use:
- `.startUserAction(type:.scroll:)`
- `.stopUserAction(type:.scroll)`

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

Find more details and available options in `DDRUMMonitor` class.

### Custom Resources

In addition to [tracking resources automatically][6], you can also track specific custom resources (network requests, third party provider APIs, etc.). Use the following methods on `Global.rum` to manually collect RUM resources:
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

To track specific errors, notify `Global.rum` when an error occurs with the message, source, exception, and additional attributes. Refer to the [Error Attributes documentation][9].

```swift
Global.rum.addError(message: "error message.")
```

For more details and available options, refer to the code documentation comments in `DDRUMMonitor` class.


## Track custom global attributes

In addition to the [default RUM attributes][3] captured by the mobile SDK automatically, you can choose to add additional contextual information, such as custom attributes, to your RUM events to enrich your observability within Datadog. Custom attributes allow you to slice and dice information about observed user behavior (such as cart value, merchant tier, or ad campaign) with code-level information (such as backend services, session timeline, error logs, and network health).

//add sample code snippet

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

To identify user sessions, use the `setUser` API, for example:

//add sample code snippet

## Initialization Parameters
 
The following methods in `Datadog.Configuration` can be used to initialize the library:
 
| Method                                        | Description                                                                                                                                                                                      |
|-----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `set(serviceName: "service-name")`            | Set `<SERVICE_NAME>` as default value for the `service` [standard attribute][9] attached to all logs and traces sent to Datadog (this can be overriden in each Logger)                           |
| `trackUIKitActions()`                         | Enables tracking User interactions (such as Tap, Scroll or Swipe). For privacy reasons, all interactions with the on-screen keyboard are ignored                                                 |
| `trackUIKitRUMViews()`                        | Enables tracking for `ViewController` as a RUM View. You can also [customize view tracking][10] by using your own implementation of the `predicate` conforming `UIKitRUMViewsPredicate` protocol |
| `track(firstPartyHosts: ["your.domain.com"])` | Enables tracking for RUM resources. Requests whose URLs match the `firstPartyHosts` will be tagged as "first party" in the RUM events                                                            |
| `set(endpoint: .eu)`                          | Switch target endpoints for data to EU for europe users                                                                                                                                          |
 
### Automatically track views

To automatically track views, use the `.trackUIKitRUMViews()` option when configuring the SDK. To customize RUM views tracking, use `.trackUIKitRUMViews(using: predicate)` and provide your own implementation of the `predicate` which conforms to `UIKitRUMViewsPredicate` protocol:

```swift
public protocol UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView?
}
```

Inside the `rumView(for:)` implementation, your app should decide if a given `UIViewController` instance should start the RUM view or not (and return `nil` in this case). The returned value of `RUMView` should specify at least the `path` for created the RUM view.
//TODO explain this better

**Note**: The SDK calls `rumView(for:)` many times while your app is running. Your implementation of the predicate should not depend on the order of SDK calls.

### Automatically track network requests

To get timing information in resources (third-party providers, network requests) such as time to first byte or DNS resolution, use the `.track(firstPartyHosts:)` option when configuring the SDK:
```swift
Datadog.Configuration
   .builderUsing(...)
   .trackURLSession(firstPartyHosts: ["your.domain.com"])
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

### Automatically track RUM errors

All "error" and "critical" logs are automatically reported as RUM errors and linked to the current RUM view:
```swift
logger.error("message")
logger.critical("message")
```

Similarly, all ended APM spans marked as error are be reported as RUM errors:
```swift
span.setTag(key: OTTags.error, value: true)
```

## Modify or drop RUM events

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
Each mapper is a Swift closure with a signature of `(T) -> T?`, where `T` is a concrete RUM event type. This allows changing portions of the event before it gets sent. For example to redact sensitive information in RUM Resource's `url` you may implement a custom `redacted(_:) -> String` function and use it in `RUMResourceEventMapper`:

```swift
.setRUMResourceEventMapper { resourceEvent in
    var resourceEvent = resourceEvent
    resourceEvent.resource.url = redacted(resourceEvent.resource.url)
    return resourceEvent
}
```

Returning `nil` from the error, resource or action mapper will drop the event entirely (it won't be sent to Datadog). The value returned from the view event mapper must be not `nil`.

Depending on a given event's type, only some specific properties can be mutated:

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


[1]: https://docs.datadoghq.com/real_user_monitoring/data_collected/
[2]: https://github.com/DataDog/dd-sdk-ios
[3]: https://github.com/DataDog/dd-sdk-ios/releases
[7]: https://docs.datadoghq.com/account_management/api-app-keys/#client-tokens
[8]: https://docs.datadoghq.com/real_user_monitoring/browser/#setup
[9]: https://docs.datadoghq.com/account_management/api-app-keys/#api-keys
