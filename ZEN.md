# Mobile RUM SDK Philosophy

## TL;DR;

> Always keep in mind that this library lives on our users' users' device, within our user's applications. We need to be **stable**, **efficient** and **transparent**.

## Foreword

This SDK lives in our customer’s applications, and is run on end users devices. Because those devices can range from low to high end, and can be used in varying conditions of network and battery, we need to make sure our footprint on the end user experience is as small as possible.

## Small Footprint

- **Runtime performance**
    - Do not perform unnecessary operation;
    - Every public operation must be executed fast;
    - Delegate heavy work to background threads/workers when possible;
- **Library size**
    - Avoid unnecessary dependencies;
- **Network load**
    - Batch requests as much as possible;
    - Avoid making request when the device is asleep or has low battery;

## Stability

- **Zero crash caused by our code!**
    - Unless the crash is on top-level method, caused by identifiable developer mistake, and notified with an understandable error message.
    - Even in top-level methods, prefer making the library non operating and logging the issue in the console logs, rather than throwing an exception.
- **Avoid major breaking changes** in SDK updates.
    - Updating to the latest version must be transparent (unless when changing major version).
    - Minor breaking change (single method signature change, renaming, deprecation…) can happen in minor updates but should be avoided when possible.

## Compatibility

- Support old versions of the OS’s
    - iOS: v11.0 (last 3 major iOS versions generally)
- Support all main languages; especially the behavior should be the same for any language, but can be enhanced for modern languages.
    - iOS: ObjC/Swift
- Support vanilla flavors of the OS first, and add possible extensions for derived flavors of the OSs (Watch, TV, …)

## API Design

- **Start small, extend slowly**
- **Keep new API consistent**
    - with previous APIs;
    - with other Datadog products APIs;
    - with iOS community's best practices;
- Keep backward compatibility on minor updates

## Trust

- Use sensible static analysis tools;
- Use benchmark tools to measure the performance of the library;
- All parts of the libraries must be thoroughly tested;

## Workflow

- All code must be tested and reviewed;
- Keep your PR small (each PR must solve one and only one issue);
- Keep your PR as Draft until it's ready to be reviewed;

## Code architecture

- Favor Object Oriented design, rather than procedural programing;
- Favor code stability and maintainability;
- Follow the SOLID principles;
