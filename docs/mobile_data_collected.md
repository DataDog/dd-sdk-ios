# Mobile Data Collected

The Datadog Real User Monitoring SDK generates six types of events:

| Event Type | Description                                                                                                                                                                                                                                                   |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Session    | Session represents a real user journey on your mobile application. It begins when the user launches the application, and the session remains live as long as the user stays active. During the user journey, all RUM events generated as part of the session will share the same `session.id` attribute.
 |
| View       | View represents a unique screen (or screen segment) on your mobile application. Individual `ViewControllers` are classified as distinct views. While a user stays on a view, RUM event attributes (Errors, Resources, Actions) get attached to the view with a unique `view.id`                                   |
| Resource   | Resources represents network requests to first-party hosts, APIs, 3rd party providers, and libraries in your mobile application. All requests generated during a user session are attached to the view with a unique `resource.id`                                                      |
| Error     | Error represents an exception or crash (fatal error) emitted by the mobile application attached to the view it is generated in.                                                                                                                                            |
| Action   | Action represents user activity in your mobile application (application launch, tap, swipe, back etc). Each action is attached with a unique `action_id` attached to the view it gets generated in.                                                                                                                                                |             

The following diagram illustrates the RUM event hierarchy:

{{< img src="real_user_monitoring/data_collected/event-hierarchy.png" alt="RUM Event hierarchy" style="width:50%;border:none" >}}

## Default attributes

RUM collects common attributes for all events and attributes specific to each event by default listed below. You can also choose to enrich your user session data with [additional events][1] to default events specific to your application monitoring and business analytics needs.


### Common core attributes

| Attribute name   | Type   | Description                 |
|------------------|--------|-----------------------------|
| `type`     | string | The type of the event (for example, `view` or `resource`).             |
| `application.id` | string | The Datadog application ID. |
| `session.id` | string | Unique ID of the session. |
| `view.id` | string | Unique ID of the initial view corresponding to the event. |
| `view.url` | string | URL of the initial view corresponding to the event. |
| `view.name` | string | Name of the initial view corresponding to the event. |
| `service` | string | The [unified service name][] for this application used to corelate user sessions. |
| `date` | integer  | Start of the event in ms from epoch. |
| `session.type` | string | Type of the session (`user`). |
| `connectivity.status` | string | Status of device connectivity (`connected`, `not connected`, `maybe`). |
| `connectivity.interfaces` | string | The list of available network interfaces (for example, `bluetooth`, `cellular`, `ethernet`, `wifi` etc). |
| `connectivity.cellular.technology` | string | The type of a radio technology used for cellular connection |
| `connectivity.cellular.carrier_name` | string | The name of the SIM carrier |

### Global user attributes

You can enable [tracking user info][2] globally to collect and apply user attributes to all RUM events.

| Attribute name   | Type   | Description                 |
|------------------|--------|-----------------------------|
| `user.id`     | string | Identifier of the user. |
| `usr.name` | string | Name of the user. |
| `usr.email` | string | Email of the user. |


## Event specific metrics and attributes

Metrics are quantifiable values that can be used for measurements related to the event. Attributes are non-quantifiable values used to slice metrics data (group by) in analytics. 

{{% /tab %}}
{{% tab "View" %}}

### View Metrics


| Metric                              | Type        | Description                                                                                          |
|----------------------------------------|-------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `view.time_spent`                             | number (ns) | Time spent on the current view.                                                                                                                                                                                                  |
| `view.error.count`            | number      | Count of all errors collected for this view.                                                                                                                                                                |

| `view.resource.count`         | number      | Count of all resources collected for this view.                                                                                                                                                                            |
| `view.action.count`      | number      | Count of all actions collected for this view.                                                                                     
      |

| `view.is_active`      |    boolean   | Indicates whether the View corresponding to this event is considered active                                                                                       
      |



{{% /tab %}}
{{% tab "Resource" %}}

### Resource Metrics


| Metric                              | Type           | Description                                                                                                                               |
|----------------------------------------|----------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `duration`                             | number         | Entire time spent loading the resource.                                                                                                   |
| `resource.size`                | number (bytes) | Resource size.                                                                                                                            |
| `resource.connect.duration`    | number (ns)    | Time spent establishing a connection to the server (connectEnd - connectStart)                                                            |
| `resource.ssl.duration`        | number (ns)    | Time spent for the TLS handshake. If the last request is not over HTTPS, this metric does not appear (connectEnd - secureConnectionStart) |
| `resource.dns.duration`        | number (ns)    | Time spent resolving the DNS name of the last request (domainLookupEnd - domainLookupStart)                                               |
| `resource.redirect.duration`   | number (ns)    | Time spent on subsequent HTTP requests (redirectEnd - redirectStart)                                                                      |
| `resource.first_byte.duration` | number (ns)    | Time spent waiting for the first byte of response to be received (responseStart - RequestStart)                                           |
| `resource.download.duration`   | number (ns)    | Time spent downloading the response (responseEnd - responseStart)                                                                         |

### Resource attributes

| Attribute                      | Type   | Description                                                                             |
|--------------------------------|--------|-----------------------------------------------------------------------------------------|
| `resource.id`                | string |  Unique identifier of the resource.      |
| `resource.type`                | string | The type of resource being collected (for example, `xhr`, `image`, `font`, `CSS`, `Javascript`).          |
| `resource.method`                | string | The HTTP method (for example `POST`, `GET` `PATCH`, `DELETE` etc).           |
| `resource.status_code`             | number | The response status code.                                                               |
| `resource.url`                     | string | The resource URL.                                                                       |

| `resource.provider.name`      | string | The resource provider name. Default is `unknown`.                                            |
| `resource.provider.domain`      | string | The resource provider domain.                                            |
| `resource.provider.type`      | string | The resource provider type (for example `first-party`, `cdn`, `ad`, `analytics`).                                            |



{{% /tab %}}
{{% tab "Error" %}}

Front-end errors are collected with Real User Monitoring (RUM). The error message and stack trace are included when available.

### Error attributes

| Attribute       | Type   | Description                                                       |
|-----------------|--------|-------------------------------------------------------------------|
| `error.source`  | string | Where the error originates from (for example, `webview`, `logger` or `network`).     |
| `error.type`    | string | The error type (or error code in some cases).                   |
| `error.message` | string | A concise, human-readable, one-line message explaining the event. |
| `error.stack`   | string | The stack trace or complementary information about the error.     |


#### Network errors

Network errors include information about failing HTTP requests. The following facets are also collected:

| Attribute                      | Type   | Description                                                                             |
|--------------------------------|--------|-----------------------------------------------------------------------------------------|
| `error.resource.status_code`             | number | The response status code.                                                               |
| `error.resource.method`                | string | The HTTP method (for example `POST`, `GET`).           |
| `error.resource.url`                     | string | The resource URL.                                                                       |
| `error.resource.provider.name`      | string | The resource provider name. Default is `unknown`.                                            |
| `error.resource.provider.domain`      | string | The resource provider domain.                                            |
| `error.resource.provider.type`      | string | The resource provider type (for example `first-party`, `cdn`, `ad`, `analytics`).                                            |


{{% /tab %}}
{{% tab "User Action" %}}



### Action metrics

| Metric    | Type   | Description              |
|--------------|--------|--------------------------|
| `action.loading_time` | number (ns) | The loading time of the action.  |
| `action.resource.count`         | number      | Count of all resources collected for this action. |
| `action.error.count`      | number      | Count of all errors collected for this action.|

### Action attributes

| Attribute    | Type   | Description              |
|--------------|--------|--------------------------|
| `action.id` | string | UUID of the user action. |
| `action.type` | string | Type of the user action (`tap`, `application_start`). |
| `action.target.name` | string | Element that the user interacted with. Only for automatically collected actions |


{{% /tab %}}
{{< /tabs >}}


## Data retention
By default, all data collected is kept at full granularity for 15 days. 

## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: /real_user_monitoring/ios#manual-instrumentation
[2]:https://github.com/DataDog/dd-sdk-ios/blob/master/Datadog/Example/ExampleAppDelegate.swift#L37
