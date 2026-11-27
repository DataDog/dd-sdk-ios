# Apollo iOS integration

The Apollo integration in `DatadogCore` enriches GraphQL RUM resources with operation metadata for Apollo iOS 2.x.
It is available through Swift Package Manager and the opt-in `Apollo` trait.

## Installation

Enable `Apollo` on your existing `dd-sdk-ios` dependency. Keep your existing
SDK version requirement in place of `<sdk-version>` below:

```swift
dependencies: [
    .package(
        url: "https://github.com/DataDog/dd-sdk-ios",
        from: "<sdk-version>",
        traits: [.defaults, "Apollo"]
    )
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "DatadogCore", package: "dd-sdk-ios"),
            .product(name: "DatadogRUM", package: "dd-sdk-ios")
        ]
    )
]
```

No dependency on `dd-sdk-ios-apollo-interceptor` is needed. When migrating,
remove that package dependency and replace `import DatadogApollo` with
`import DatadogCore`. No additional Datadog product is required.
Continue declaring Apollo itself as an app dependency if your app imports it.

The trait is disabled by default. Without it, the SDK does not expose the Apollo
integration types or build or link Apollo. The Apollo 2.x package requirement remains
declared in the manifest; dependency resolution behavior depends on the SwiftPM
version, so the trait does not guarantee that Apollo is never fetched or
considered during resolution.

`.defaults` preserves the SDK's default `CrashReporting` and `OpenTelemetry` traits.
Use `traits: ["Apollo"]` to enable Apollo without those integrations, or `traits: []`
to disable all optional integrations. See the [package traits](README.md#swift-package-traits).

## Setup

After enabling Datadog RUM, configure Apollo's session and interceptor provider:

```swift
import Apollo
import DatadogCore

struct NetworkInterceptorProvider: InterceptorProvider {
    func graphQLInterceptors<Operation: GraphQLOperation>(
        for operation: Operation
    ) -> [any GraphQLInterceptor] {
        [DatadogApolloInterceptor()]
            + DefaultInterceptorProvider.shared.graphQLInterceptors(for: operation)
    }
}

URLSessionInstrumentation.enableDurationBreakdown(
    with: .init(delegateClass: DatadogApolloDelegate.self)
)

let session = DatadogApolloURLSession(configuration: .default)
let transport = RequestChainNetworkTransport(
    urlSession: session,
    interceptorProvider: NetworkInterceptorProvider(),
    store: store,
    endpointURL: endpointURL
)
```

`store` and `endpointURL` are your existing Apollo store and GraphQL endpoint.
The interceptor and session setup is the same as in the standalone 2.x integration.

Full query payload collection is disabled by default. To enable it, use
`DatadogApolloInterceptor(sendGraphQLPayloads: true)`. Operation names, types,
and variables are included by the interceptor. Subscriptions are not supported;
the session wrapper buffers each response before yielding a single chunk.

Apollo iOS 1.x continues to use the standalone interceptor's 1.x releases.

## Development

```shell
swift build --target DatadogCore --traits defaults,Apollo
swift build --target DatadogCore --disable-default-traits
```

Implementation: `DatadogInternal/Sources/NetworkInstrumentation/Apollo/`.
The three public integration types are re-exported through `DatadogCore`.

The implementation and baseline tests were migrated from
[`dd-sdk-ios-apollo-interceptor` 2.0.1](https://github.com/DataDog/dd-sdk-ios-apollo-interceptor/tree/2.0.1).
