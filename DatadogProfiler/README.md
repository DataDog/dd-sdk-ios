# Datadog Profiler

This module provides support for [Datadog Continuous Profiler](https://docs.datadoghq.com/profiler/), allowing you to collect and analyze CPU performance profiles from iOS/tvOS applications.

## Current Status

⚠️ **Proof of Concept (PoC)** ⚠️

This implementation is currently in Proof of Concept stage. It provides basic CPU profiling capabilities but may not be suitable for production use yet.

## Features

- CPU profiling with unsymbolized stack trace collection

## Usage

```swift
import DatadogProfiler

// Enable the profiler with your API key
Profiler.enable(with: .init(apiKey: "api-key"))

// Start profiling (optionally only the current thread)
Profiler.start(currentThreadOnly: true)

// Stop profiling and send the data to Datadog
Profiler.stop()
```