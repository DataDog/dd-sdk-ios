# DatadogCore — Agent Guide

> Module-specific guidance for the Core SDK module. For project-wide rules, see the root `AGENTS.md`.

## Module Overview

DatadogCore is the SDK orchestrator. It handles initialization, feature registration, context management, data storage, batching, and upload. All feature modules depend on it indirectly through `DatadogInternal` protocols, but only DatadogCore provides the concrete implementations.

## Key Files Map

| File | Role |
|------|------|
| `Sources/Datadog.swift` | SDK entry point (`Datadog.initialize()`) |
| `Sources/DatadogConfiguration.swift` | SDK configuration struct |
| `Sources/Core/DatadogCore.swift` | Main orchestrator — feature registry, context, storage |
| `Sources/Core/MessageBus.swift` | Concrete inter-feature message bus |
| `Sources/Core/Context/` | Context providers (user, network, device, battery, app state) |
| `Sources/Core/Storage/` | File-based storage pipeline |
| `Sources/Core/Storage/Files/FilesOrchestrator.swift` | File I/O orchestration |
| `Sources/Core/Storage/Writing/` | AsyncWriter, FileWriter |
| `Sources/Core/Storage/Reading/` | DataReader for upload batches |
| `Sources/Core/Upload/DataUploadWorker.swift` | Periodic upload orchestrator |
| `Sources/Core/Upload/DataUploader.swift` | Single batch uploader |
| `Sources/Core/Upload/HTTPClient.swift` | HTTP abstraction |
| `Sources/Core/Upload/URLSessionClient.swift` | URLSession implementation (ephemeral, no caching) |
| `Sources/Core/DataStore/` | Key-value storage for feature-specific data |
| `Sources/Core/TLV/` | Binary TLV encoding for compact storage |

## Feature Registration Lifecycle

1. App calls `Datadog.initialize(with:trackingConsent:)` — creates `DatadogCore` instance
2. `DatadogCore` is registered in `CoreRegistry` (singleton lookup)
3. App calls feature-specific `enable()` (e.g., `RUM.enable(with:in:)`)
4. Feature creates its plugin (e.g., `RUMFeature`) and registers with core
5. Core allocates storage directory and upload worker for the feature
6. Feature can now write events and receive messages via the bus

## Storage Pipeline

```
Feature writes event → AsyncWriter → FileWriter → FilesOrchestrator → disk file
                                                                         ↓
DataUploadWorker (periodic) → DataReader → RequestBuilder → HTTPClient → Datadog backend
```

- Storage location: `[AppSupport]/Datadog/[site]/[feature]/`
- No database — pure filesystem
- Optional encryption via `DataEncryption` protocol
- TLV (Type-Length-Value) encoding for compact binary storage

## Context Providers and Publisher System

`DatadogContextProvider` aggregates multiple publishers into a single `DatadogContext`:

- Each publisher implements `ContextValuePublisher` (from `DatadogInternal`)
- Publishers subscribe to system notifications (e.g., `UIApplication.didBecomeActiveNotification`)
- Context is passed to every feature during event processing
- To add a new context value: create a publisher in `Core/Context/`, register in `DatadogContextProvider`

## MessageBus

- Concrete implementation of the `MessageBus` protocol (defined in `DatadogInternal`)
- Features subscribe to messages from other features
- Examples: RUM subscribes to crash events, Session Replay subscribes to RUM view updates
- Location: `Sources/Core/MessageBus.swift`

## HTTP Client

- `URLSessionClient` uses ephemeral configuration (no caching — RUMM-610)
- All requests go through `URLSessionClient` with DD-API-KEY header
- Proxy support via `connectionProxyDictionary`
- Gzip compression for payloads

## Important for Agents

**When modifying feature modules, always check if DatadogCore needs updates too.** Common oversights:
- Feature interface changes may require updates to how Core registers the feature
- New context values require a publisher registered here
- New message types require bus subscribers here
- Storage format changes affect the upload pipeline here

## HTTP Request Details

All features upload data via the same `URLSessionClient`:
- **Auth header**: `DD-API-KEY` with client token
- **Custom headers**: `DD-EVP-ORIGIN`, `DD-EVP-ORIGIN-VERSION`, `DD-REQUEST-ID`
- **Formats**: JSON, NDJSON (batches), multipart/form-data (Session Replay, crashes)
- **Compression**: Gzip support
- **Endpoints**: Site-specific (`.us1` → `browser-intake-datadoghq.com`, `.eu1` → `browser-intake-datadoghq.eu`, etc.)
- **Header builder**: `DatadogInternal/Sources/Upload/URLRequestBuilder.swift`
- **Site definitions**: `DatadogInternal/Sources/Context/DatadogSite.swift`

## Reference Documentation

- Root `AGENTS.md` — Project-wide rules, data flow, and conventions
- `DatadogInternal/AGENTS.md` — Shared protocols that Core implements
