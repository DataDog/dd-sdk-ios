##Configure iOS SDK

If you haven't setup the SDK yet, follow the [in-app setup instructions][1] or find instructions in [iOS RUM setup][2]. 

## Initialization Parameters
 
The following methods in `Datadog.Configuration` can be used to initialize the library:
 
| Method                           | Description                                                                                                                                                                                                                                                             |
|----------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `set(serviceName: "service-name")` | Set `<SERVICE_NAME>` as default value for the `service` [standard attribute][9] attached to all logs and traces sent to Datadog (this can be overriden in each Logger)    |
| `trackUIKitActions()` | Enables tracking User interactions (such as Tap, Scroll or Swipe). For privacy reasons, all interactions with the on-screen keyboard are ignored |
| `trackUIKitRUMViews()` | Enables tracking for `ViewController` as a RUM View. You can also [customize view tracking][10] by using your own implementation of the `predicate` conforming `UIKitRUMViewsPredicate` protocol  |
| `track(firstPartyHosts: ["your.domain.com"])` | Enables tracking for RUM resources. Requests whose URLs match the `firstPartyHosts` will be tagged as "first party" in the RUM events |
| `set(endpoint: .eu)` | Switch target endpoints for data to EU for europe users  |


## Add Custom Attributes

In addition to the [default RUM attributes][3] captured by the Mobile SDK automatically, you can choose to add additional contextual information as custom attributes to your RUM events to enrich your observability within Datadog. Custom attributes allow you to slice and dice infomation about observed user behavior (cart value, merchant-tier, ad campaign) with code-level infomation (backend services, session timeline, error logs, network health etc).

// TODO Add code snippet
//Globalrum.addAttribute()

## Add User Info

### Identify user sessions
Adding user information to your RUM sessions makes it easy to:
* Follow the journey of a given user
* Know which users are the most impacted by crashes
* Monitor performance for your most important users

{{< img src="real_user_monitoring/browser/advanced_configuration/user-api.png" alt="User API in RUM UI"  >}}

The following attributes are **optional** but it is recommended to provide **at least one** of them:

| Attribute  | Type | Description                                                                                              |
|------------|------|----------------------------------------------------------------------------------------------------|
| usr.id    | String | Unique user identifier.                                                                                  |
| usr.name  | String | User friendly name, displayed by default in the RUM UI.                                                  |
| usr.email | String | User email, displayed in the RUM UI if the user name is not present. It is also used to fetch Gravatars. |

To identify user sessions, use the `setUser` API:

// TODO Add code snippet
//Datadog.setUserInfo()

### Add your own performance timing

On top of RUM’s default attributes, you may measure where your application is spending its time with greater flexibility. The `addTiming` API provides you with a simple way to add extra performance timing. The timing measure will be relative to the start of the current RUM view. For example, you can add a timing when your hero image has appeared:

   ```kotlin
       func onHeroImageLoaded() {
           Global.rum.addTiming(name: "content-ready")
       } 
   ```

Once the timing is sent, the timing will be accessible as `@view.custom_timings.<timing_name>` (For example, `@view.custom_timings.hero_image`). You must [create a measure](https://docs.datadoghq.com/real_user_monitoring/explorer/?tab=measures#setup-facets-and-measures) before graphing it in RUM analytics or in dashboards. 

## Sample RUM events

To control the data your application sends to Datadog RUM, you can secify a sampling rate for RUM sessions while [initializing the RumMonitor][] as a percentage between 0 and 100.
//TODO add code snippet


[1]: https://app.datadoghq.com/rum/create
[2]: /real_user_monitoring/ios
[3]: /real_user_monitoring/ios/data_collected
