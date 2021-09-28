---
title: RUM iOS Data Collected
kind: documentation
further_reading:
  - link: "https://github.com/DataDog/dd-sdk-ios"
    tag: "Github"
    text: "dd-sdk-ios Source code"
  - link: "/real_user_monitoring"
    tag: "Documentation"
    text: "Datadog Real User Monitoring"
---
The RUM SDK generates events that have associated metrics and attributes. Metrics are quantifiable values that can be used for measurements related to the event. Attributes are non-quantifiable values used to slice metrics data (group by) in analytics. 

Every RUM event has all of the [default attributes](#default-attributes), for example, the device type (`device.type`) and user information such as their name (`usr.name`) and their country (`geo.country`). 

There are additional [metrics and attributes that are specific to a given event type](#event-specific-metrics-and-attributes). For example, the metric `view.time_spent` is associated with "view" events and the attribute `resource.method` is associated with "resource" events. 

This page provides descriptions of each of the metrics and attributes collected.

## Default attributes

RUM collects common attributes for all events and attributes specific to each event by default listed below. You can also choose to enrich your user session data with [additional events][1] to default events specific to your application monitoring and business analytics needs.


### Common core attributes

| Attribute name   | Type    | Description                                                                        |
|------------------|---------|------------------------------------------------------------------------------------|
| `date`           | integer | Start of the event in ms from epoch.                                               |
| `type`           | string  | The type of the event (for example, `view` or `resource`).                         |
| `service`        | string  | The [unified service name][2] for this application used to corelate user sessions. |
| `application.id` | string  | The Datadog application ID.                                                        |

### Device

The following device-related attributes are attached automatically to all events collected by Datadog:

| Attribute name                       | Type   | Description                                                                                              |
|--------------------------------------|--------|----------------------------------------------------------------------------------------------------------|
| `device.type`                        | string | The device type as reported by the device (System User-Agent)                                            |
| `device.brand`                       | string | The device brand as reported by the device (System User-Agent)                                           |
| `device.model`                       | string | The device model as reported by the device (System User-Agent)                                           |
| `device.name`                        | string | The device name as reported by the device (System User-Agent)                                            |
| `connectivity.status`                | string | Status of device network reachability (`connected`, `not connected`, `maybe`).                           |
| `connectivity.interfaces`            | string | The list of available network interfaces (for example, `bluetooth`, `cellular`, `ethernet`, `wifi` etc). |
| `connectivity.cellular.technology`   | string | The type of a radio technology used for cellular connection                                              |
| `connectivity.cellular.carrier_name` | string | The name of the SIM carrier                                                                              |


### Operating system

The following OS-related attributes are attached automatically to all events collected by Datadog:

| Attribute name     | Type   | Description                                                               |
|--------------------|--------|---------------------------------------------------------------------------|
| `os.name`          | string | The OS name as reported by the by the device (System User-Agent)          |
| `os.version`       | string | The OS version as reported by the by the device (System User-Agent)       |
| `os.version_major` | string | The OS version major as reported by the by the device (System User-Agent) |


### Geo-location

The following attributes are related to the geo-location of IP addresses:

| Fullname                           | Type   | Description                                                                                                                               |
|------------------------------------|--------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `geo.country`                      | string | Name of the country                                                                                                                       |
| `geo.country_iso_code`             | string | ISO Code of the country (for example, `US` for the United States, `FR` for France).                                                  |
| `geo.country_subdivision`          | string | Name of the first subdivision level of the country (for example, `California` in the United States or the `Sarthe` department in France). |
| `geo.country_subdivision_iso_code` | string | ISO Code of the first subdivision level of the country (for example, `CA` in the United States or the `SA` department in France).    |
| `geo.continent_code`               | string | ISO code of the continent (`EU`, `AS`, `NA`, `AF`, `AN`, `SA`, `OC`).                                                                     |
| `geo.continent`                    | string | Name of the continent (`Europe`, `Australia`, `North America`, `Africa`, `Antartica`, `South America`, `Oceania`).                        |
| `geo.city`                         | string | The name of the city (example `Paris`, `New York`).                                                                                       |


### Global user attributes

You can enable [tracking user info][2] globally to collect and apply user attributes to all RUM events.

| Attribute name | Type   | Description             |
|----------------|--------|-------------------------|
| `usr.id`      | string | Identifier of the user. |
| `usr.name`     | string | Name of the user.       |
| `usr.email`    | string | Email of the user.      |


## Event specific metrics and attributes

The Datadog Real User Monitoring SDK generates six types of events:

| Event Type | Retention | Description                         |
|------------|-----------|-------------------------------------|
| Session    | 30 days   | Session represents a real user journey on your mobile application. It begins when the user launches the application, and the session remains live as long as the user stays active. During the user journey, all RUM events generated as part of the session will share the same `session.id` attribute. |
| View       | 30 days   | A view represents a unique screen (or screen segment) on your mobile application. Individual `UIViewControllers` are classified as distinct views. While a user stays on a view, RUM event attributes (Errors, Resources, Actions) get attached to the view with a unique `view.id`                           |
| Resource   | 15 days   | Resources represents network requests to first-party hosts, APIs, 3rd party providers, and libraries in your mobile application. All requests generated during a user session are attached to the view with a unique `resource.id`                                                                       |
| Error      | 30 days   | Error represents an exception emitted by the mobile application attached to the view it is generated in.                                                                                                                                                                                        |
| Action     | 30 days   | Action represents user activity in your mobile application (application launch, tap, swipe, back etc). Each action is attached with a unique `action.id` attached to the view it gets generated in.                                                                                                      |

The following diagram illustrates the RUM event hierarchy:

{{< img src="real_user_monitoring/data_collected/event-hierarchy.png" alt="RUM Event hierarchy" style="width:50%;border:none" >}}

### Session metrics

| Metric                    | Type        | Description                                         |
|---------------------------|-------------|-----------------------------------------------------|
| `session.time_spent`      | number (ns) | Time spent on a session.                            |
| `session.view.count`      | number      | Count of all views collected for this session.      |
| `session.error.count`     | number      | Count of all errors collected for this session.     |
| `session.resource.count`  | number      | Count of all resources collected for this session.  |
| `session.action.count`    | number      | Count of all actions collected for this session.    |
| `session.long_task.count` | number      | Count of all long tasks collected for this session. |


### Session attributes

| Attribute name               | Type   | Description                                                                |
|------------------------------|--------|----------------------------------------------------------------------------|
| `session.id`                 | string | Unique ID of the session.                                                  |
| `session.type`               | string | Type of the session (`user`).                                              |
| `session.is_active`          | string | Indicates if the session is currently active                               |
| `session.initial_view.url`   | string | URL of the initial view of the session                                     |
| `ssession.initial_view.name` | string | Name of the initial view of the session                                    |
| `session.last_view.url`      | string | URL of the last view of the session                                        |
| `session.last_view.name`     | string | Name of the last view of the session                                       |
| `session.ip`                 | string | IP address of the session extracted from the TCP connectiion of the intake |
| `session.useragent`          | string | System user agent info to interpret device info                            |


### View metrics

RUM action, error, resource and long task events contain information about the active RUM view event at the time of collection:

| Metric                | Type        | Description                                                                  |
|-----------------------|-------------|------------------------------------------------------------------------------|
| `view.time_spent`     | number (ns) | Time spent on the this view.                                                 |
| `view.error.count`    | number      | Count of all errors collected for this view.                                 |
| `view.resource.count` | number      | Count of all resources collected for this view.                              |
| `view.action.count`   | number      | Count of all actions collected for this view.                                |
| `view.is_active`      | boolean     | Indicates whether the view corresponding to this event is considered active. |

### View attributes      

| Attribute name | Type   | Description                                                     |
|----------------|--------|-----------------------------------------------------------------|
| `view.id`      | string | Unique ID of the initial view corresponding to the event.view.  |
| `view.url`     | string | URL of the `UIViewController` class corresponding to the event. |
| `view.name`    | string | Customizable name of the view corresponding to the event.       |


### Resource metrics

| Metric                         | Type           | Description                                                                                     |
|--------------------------------|----------------|-------------------------------------------------------------------------------------------------|
| `resource.duration`            | number         | Entire time spent loading the resource.                                                         |
| `resource.size`                | number (bytes) | Resource size.                                                                                  |
| `resource.connect.duration`    | number (ns)    | Time spent establishing a connection to the server (connectEnd - connectStart)                  |
| `resource.ssl.duration`        | number (ns)    | Time spent for the TLS handshake.                                                               |
| `resource.dns.duration`        | number (ns)    | Time spent resolving the DNS name of the last request (domainLookupEnd - domainLookupStart)     |
| `resource.redirect.duration`   | number (ns)    | Time spent on subsequent HTTP requests (redirectEnd - redirectStart)                            |
| `resource.first_byte.duration` | number (ns)    | Time spent waiting for the first byte of response to be received (responseStart - requestStart) |
| `resource.download.duration`   | number (ns)    | Time spent downloading the response (responseEnd - responseStart)                               |

### Resource attributes

| Attribute                  | Type   | Description                                                                              |
|----------------------------|--------|------------------------------------------------------------------------------------------|
| `resource.id`              | string | Unique identifier of the resource.                                                       |
| `resource.type`            | string | The type of resource being collected (for example, `xhr`, `image`, `font`, `css`, `js`). |
| `resource.method`          | string | The HTTP method (for example `POST`, `GET` `PATCH`, `DELETE` etc).                       |
| `resource.status_code`     | number | The response status code.                                                                |
| `resource.url`             | string | The resource URL.                                                                        |
| `resource.provider.name`   | string | The resource provider name. Default is `unknown`.                                        |
| `resource.provider.domain` | string | The resource provider domain.                                                            |
| `resource.provider.type`   | string | The resource provider type (for example `first-party`, `cdn`, `ad`, `analytics`).        |


### Error attributes

Front-end errors are collected with Real User Monitoring (RUM). The error message and stack trace are included when available.

| Attribute        | Type   | Description                                                                      |
|------------------|--------|----------------------------------------------------------------------------------|
| `error.source`   | string | Where the error originates from (for example, `webview`, `logger` or `network`). |
| `error.type`     | string | The error type (or error code in some cases).                                    |
| `error.message`  | string | A concise, human-readable, one-line message explaining the event.                |
| `error.stack`    | string | The stack trace or complementary information about the error.                    |
| `error.issue_id` | string | The stack trace or complementary information about the error.                    |

#### Network errors 

Network errors include information about failing HTTP requests. The following facets are also collected:

| Attribute                        | Type   | Description                                                                       |
|----------------------------------|--------|-----------------------------------------------------------------------------------|
| `error.resource.status_code`     | number | The response status code.                                                         |
| `error.resource.method`          | string | The HTTP method (for example `POST`, `GET`).                                      |
| `error.resource.url`             | string | The resource URL.                                                                 |
| `error.resource.provider.name`   | string | The resource provider name. Default is `unknown`.                                 |
| `error.resource.provider.domain` | string | The resource provider domain.                                                     |
| `error.resource.provider.type`   | string | The resource provider type (for example `first-party`, `cdn`, `ad`, `analytics`). |


### Action metrics

| Metric                  | Type        | Description                                   |
|-------------------------|-------------|-----------------------------------------------|
| `action.loading_time`   | number (ns) | The loading time of the action.               |
| `action.resource.count` | number      | Count of all resources issued by this action. |
| `action.error.count`    | number      | Count of all errors issued by this action.    |

### Action attributes

| Attribute            | Type   | Description                                                                     |
|----------------------|--------|---------------------------------------------------------------------------------|
| `action.id`          | string | UUID of the user action.                                                        |
| `action.type`        | string | Type of the user action (`tap`, `application_start`).                           |
| `action.name`        | string | Name of the user action.                                                        |
| `action.target.name` | string | Element that the user interacted with. Only for automatically collected actions |



## Further Reading

{{< partial name="whats-next/whats-next.html" >}}

[1]: /real_user_monitoring/ios/advanced_configuration/#enrich-user-sessions
[2]: /real_user_monitoring/ios/advanced_configuration/#track-user-sessions
