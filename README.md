# Overview

This repository provides a Datadog SDK fork that relies on the [**official OpenTelemetry-Swift repository**](https://github.com/open-telemetry/opentelemetry-swift/) instead of the [custom OpenTelemetry fork](https://github.com/DataDog/opentelemetry-swift-packages) used by the original Datadog SDK. Our goal is to ensure compatibility with libraries and applications that depend on the official OpenTelemetry implementation.

# **Why This Fork Exists**

## **Original Datadog Fork Issues**

Datadog’s original integration with OpenTelemetry uses a [custom fork](https://github.com/DataDog/opentelemetry-swift-packages). While part of the reason for this was that, at the time, the [official OpenTelemetry-Swift fork](https://github.com/open-telemetry/opentelemetry-swift/) did not support certain common distribution methods on iOS (like CocoaPods), one of the main motivations was related to how SPM works and how the OpenTelemetry-Swift repository is structured.

When downloading the OpenTelemetry dependency, SPM downloads *everything*: all the products and its dependencies. Although these dependencies are not linked to the Datadog SDK (only `OpenTelemetryApi`), they still consume resources during the download process (a more detailed explanation in this [issue](https://github.com/open-telemetry/opentelemetry-swift/issues/486)).

While this approach allows DataDog to resolve the issue of resource consumption during dependency downloads ([reported here](https://github.com/DataDog/dd-sdk-ios/issues/1877)), it introduces two major issues:

1. It does not stay up to date with the latest OpenTelemetry updates.
2. It creates build conflicts with other libraries or apps that use the official OpenTelemetry fork because the module name was not changed ([example](https://github.com/DataDog/dd-sdk-ios/issues/1989)).

These conflicts became a critical issue for libraries like [`Embrace`](https://github.com/embrace-io/embrace-apple-sdk), whose core SDK is built directly on the official OpenTelemetry fork. Without a workaround, developers will just have build errors and frustration during integration.

## **What This Fork Changes**

**This fork solves these problems by:**

- **Adopting the Official OpenTelemetry Repository:** We’ve dropped the Datadog-specific OpenTelemetry fork. Instead, we depend on the official [OpenTelemetry-Swift repository](https://github.com/open-telemetry/opentelemetry-swift/).
- **Keeping Pace with Upstream Updates:** We can now track and quickly integrate the latest features, bug fixes, and architectural improvements from OpenTelemetry.
- **Removing Conflicts:** By relying on the standard OpenTelemetry artifacts, we eliminate naming and build conflicts, allowing seamless coexistence with other libraries (like Embrace) and [apps](https://github.com/DataDog/dd-sdk-ios/issues/1877#issuecomment-2265848754).

> [!WARNING]  
> **Note on Platform Requirements:**
> 
> Because we’ve aligned with more recent—and occasionally breaking—changes in the official OpenTelemetry repository, the minimum supported OS version has been raised to `v13` for iOS, macOS and tvOS.

# **Getting Started**

Since this fork aims to be a drop-in alternative, you can follow the [usual integration steps outlined in the primary Datadog SDK documentation](https://github.com/DataDog/dd-sdk-ios?tab=readme-ov-file#getting-started). Just ensure you point your Swift Package Manager to this fork’s repository.

# **Support and Contributions**

If you run into any issues or have feature requests, feel free to open an issue or pull request. We welcome feedback and community contributions to keep this integration as smooth, efficient, and up-to-date as possible.
