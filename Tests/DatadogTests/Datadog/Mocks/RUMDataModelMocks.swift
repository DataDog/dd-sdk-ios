/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension RUMUser: EquatableInTests {}
extension RUMConnectivity: EquatableInTests {}
extension RUMViewEvent: EquatableInTests {}
extension RUMResourceEvent: EquatableInTests {}
extension RUMActionEvent: EquatableInTests {}
extension RUMErrorEvent: EquatableInTests {}
extension RUMLongTaskEvent: EquatableInTests {}
extension RUMEvent: EquatableInTests {}

extension RUMUser {
    static func mockRandom() -> RUMUser {
        return RUMUser(
            email: .mockRandom(),
            id: .mockRandom(),
            name: .mockRandom(),
            usrInfo: mockRandomAttributes()
        )
    }
}

extension RUMConnectivity {
    static func mockRandom() -> RUMConnectivity {
        return RUMConnectivity(
            cellular: .init(
                carrierName: .mockRandom(),
                technology: .mockRandom()
            ),
            interfaces: [.bluetooth, .cellular].randomElements(),
            status: [.connected, .maybe, .notConnected].randomElement()!
        )
    }
}

extension RUMMethod: RandomMockable {
    static func mockRandom() -> RUMMethod {
        return [.post, .get, .head, .put, .delete, .patch].randomElement()!
    }
}

extension RUMEventAttributes: RandomMockable {
    static func mockRandom() -> RUMEventAttributes {
        return .init(contextInfo: mockRandomAttributes())
    }
}

extension RUMViewEvent: RandomMockable {
    static func mockRandom() -> RUMViewEvent {
        return RUMViewEvent(
            dd: .init(
                documentVersion: .mockRandom(),
                session: .init(plan: .plan1)
            ),
            application: .init(id: .mockRandom()),
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            synthetics: nil,
            usr: .mockRandom(),
            view: .init(
                action: .init(count: .mockRandom()),
                cpuTicksCount: .mockRandom(),
                cpuTicksPerSecond: .mockRandom(),
                crash: .init(count: .mockRandom()),
                cumulativeLayoutShift: .mockRandom(),
                customTimings: .mockAny(),
                domComplete: .mockRandom(),
                domContentLoaded: .mockRandom(),
                domInteractive: .mockRandom(),
                error: .init(count: .mockRandom()),
                firstContentfulPaint: .mockRandom(),
                firstInputDelay: .mockRandom(),
                firstInputTime: .mockRandom(),
                frozenFrame: .init(count: .mockRandom()),
                id: .mockRandom(),
                inForegroundPeriods: [
                    .init(
                        duration: .mockRandom(),
                        start: .mockRandom()
                    )
                ],
                isActive: .random(),
                isSlowRendered: .mockRandom(),
                largestContentfulPaint: .mockRandom(),
                loadEvent: .mockRandom(),
                loadingTime: .mockRandom(),
                loadingType: nil,
                longTask: .init(count: .mockRandom()),
                memoryAverage: .mockRandom(),
                memoryMax: .mockRandom(),
                name: .mockRandom(),
                referrer: .mockRandom(),
                refreshRateAverage: .mockRandom(),
                refreshRateMin: .mockRandom(),
                resource: .init(count: .mockRandom()),
                timeSpent: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMResourceEvent: RandomMockable {
    static func mockRandom() -> RUMResourceEvent {
        return RUMResourceEvent(
            dd: .init(
                session: .init(plan: .plan1),
                spanId: .mockRandom(),
                traceId: .mockRandom()
            ),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            resource: .init(
                connect: .init(duration: .mockRandom(), start: .mockRandom()),
                dns: .init(duration: .mockRandom(), start: .mockRandom()),
                download: .init(duration: .mockRandom(), start: .mockRandom()),
                duration: .mockRandom(),
                firstByte: .init(duration: .mockRandom(), start: .mockRandom()),
                id: .mockRandom(),
                method: .mockRandom(),
                provider: .init(
                    domain: .mockRandom(),
                    name: .mockRandom(),
                    type: Bool.random() ? .firstParty : nil
                ),
                redirect: .init(duration: .mockRandom(), start: .mockRandom()),
                size: .mockRandom(),
                ssl: .init(duration: .mockRandom(), start: .mockRandom()),
                statusCode: .mockRandom(),
                type: [.native, .image].randomElement()!,
                url: .mockRandom()
            ),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            synthetics: nil,
            usr: .mockRandom(),
            view: .init(
                id: .mockRandom(),
                referrer: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMActionEvent: RandomMockable {
    static func mockRandom() -> RUMActionEvent {
        return RUMActionEvent(
            dd: .init(
                session: .init(plan: .plan1)
            ),
            action: .init(
                crash: .init(count: .mockRandom()),
                error: .init(count: .mockRandom()),
                id: .mockRandom(),
                loadingTime: .mockRandom(),
                longTask: .init(count: .mockRandom()),
                resource: .init(count: .mockRandom()),
                target: .init(name: .mockRandom()),
                type: [.tap, .swipe, .scroll].randomElement()!
            ),
            application: .init(id: .mockRandom()),
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            synthetics: nil,
            usr: .mockRandom(),
            view: .init(
                id: .mockRandom(),
                inForeground: .random(),
                referrer: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMErrorEvent: RandomMockable {
    static func mockRandom() -> RUMErrorEvent {
        return RUMErrorEvent(
            dd: .init(
                session: .init(plan: .plan1)
            ),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            error: .init(
                handling: nil,
                handlingStack: nil,
                id: .mockRandom(),
                isCrash: .random(),
                message: .mockRandom(),
                resource: .init(
                    method: .mockRandom(),
                    provider: .init(
                        domain: .mockRandom(),
                        name: .mockRandom(),
                        type: Bool.random() ? .firstParty : nil
                    ),
                    statusCode: .mockRandom(),
                    url: .mockRandom()
                ),
                source: [.source, .network, .custom].randomElement()!,
                sourceType: [.android, .browser, .ios, .reactNative].randomElement()!,
                stack: .mockRandom(),
                type: .mockRandom()
            ),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            synthetics: nil,
            usr: .mockRandom(),
            view: .init(
                id: .mockRandom(),
                inForeground: .random(),
                referrer: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMLongTaskEvent: RandomMockable {
    static func mockRandom() -> RUMLongTaskEvent {
        return RUMLongTaskEvent(
            dd: .init(session: .init(plan: .plan1)),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            longTask: .init(duration: .mockRandom(), id: .mockRandom(), isFrozenFrame: .mockRandom()),
            service: .mockRandom(),
            session: .init(hasReplay: false, id: .mockRandom(), type: .user),
            synthetics: nil,
            usr: .mockRandom(),
            view: .init(id: .mockRandom(), name: .mockRandom(), referrer: .mockRandom(), url: .mockRandom())
        )
    }
}
