/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import ObjectiveC.runtime
import DatadogMachProfiler
import DatadogMachProfiler.Testing
@testable import DatadogProfiling

// =====================================================================
// +allocWithZone: / -dealloc interception — tests
//
// Focus is the production composition/never-restore contract (see
// docs/SWIZZLING.md): the interceptor must be correct when a third-party
// swizzle is installed before OR after ours, in any order, and stop() must
// never restore an IMP (which would clobber a later swizzle or reinstate a
// stale one). A "third-party" swizzle is simulated by installing our own
// forwarding IMP over -[NSObject dealloc].
//
// NOTE: -dealloc / +allocWithZone: swizzles are process-global and, by the
// never-restore discipline, remain installed for the rest of the test
// process; stop() only disables observation. Assertions therefore use the
// interception layer's own diagnostics deltas rather than absolute counts.
// =====================================================================

// MARK: - Fixtures

/// Plain Obj-C class — intercepted via NSObject's +allocWithZone:.
@objc(DDObjCAllocFixture) private class ObjCFixture: NSObject {
    let payload: Int
    init(payload: Int = 0) { self.payload = payload }
}

/// Swift NSObject subclass — same Obj-C runtime path, intercepted.
private class SwiftNSObjectFixture: NSObject {
    let payload: [Int]
    override init() { self.payload = [1, 2, 3]; super.init() }
}

// MARK: - Third-party -dealloc swizzle simulation

/// Shared state for a simulated third-party -[NSObject dealloc] swizzle.
/// `previousIMP` is the IMP that was outermost when we installed (our forward
/// target); `enabled` gates counting so the layer can be cheaply neutralised
/// without being restored.
private final class DeallocSwizzleState: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _previousIMP: IMP
    private var _enabled = true
    private var _count = 0

    init(previousIMP: IMP) { self._previousIMP = previousIMP }

    var previousIMP: IMP { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _previousIMP }
    var count: Int { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _count }
    func disable() { os_unfair_lock_lock(&lock); _enabled = false; os_unfair_lock_unlock(&lock) }

    func recordAndForwardTarget() -> IMP {
        os_unfair_lock_lock(&lock)
        if _enabled { _count += 1 }
        let imp = _previousIMP
        os_unfair_lock_unlock(&lock)
        return imp
    }
}

private typealias DeallocIMPC = @convention(c) (Unmanaged<AnyObject>, Selector) -> Void
private let deallocSelector = NSSelectorFromString("dealloc")

/// Installs a forwarding counter over -[NSObject dealloc], on top of whatever
/// IMP is currently outermost. Returns the shared state (for assertions and
/// neutralisation) plus the installed IMP (so the caller can restore it when it
/// is provably still the outermost layer).
@discardableResult
private func installThirdPartyDeallocCounter() -> (state: DeallocSwizzleState, method: Method, installedIMP: IMP) {
    let method = class_getInstanceMethod(NSObject.self, deallocSelector)!
    // Capture the current outermost IMP up front so an in-flight dealloc that
    // races the install still has a valid forward target.
    let state = DeallocSwizzleState(previousIMP: method_getImplementation(method))
    let block: @convention(block) (Unmanaged<AnyObject>) -> Void = { obj in
        let forward = state.recordAndForwardTarget()
        unsafeBitCast(forward, to: DeallocIMPC.self)(obj, deallocSelector)
    }
    let installedIMP = imp_implementationWithBlock(block)
    _ = method_setImplementation(method, installedIMP)
    return (state, method, installedIMP)
}

final class ObjCAllocInterceptionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ObjCAllocInterception.stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        ObjCAllocInterception.stop()
        dd_memory_test_reset()
        super.tearDown()
    }

    // MARK: - Basic interception

    func test_start_installsAndObservesObjCAllocations() {
        XCTAssertEqual(ObjCAllocInterception.start(), .ok, "Install must succeed on a clean environment")
        XCTAssertTrue(ObjCAllocInterception.isRunning)

        let before = ObjCAllocInterception.diagnostics().totalInvocations
        autoreleasepool {
            _ = ObjCFixture(payload: 1)
            _ = SwiftNSObjectFixture()
            _ = NSObject()
        }
        XCTAssertGreaterThan(
            ObjCAllocInterception.diagnostics().totalInvocations, before,
            "The +allocWithZone: trampoline must fire for NSObject-rooted allocations"
        )
    }

    // MARK: - Never-restore: restart correctness

    /// start -> stop -> start must re-enable observation without re-capturing our
    /// own trampoline as the "original" (which would forward to ourselves and
    /// stack-overflow). A tight alloc loop after restart proves there is no
    /// self-referential forwarding.
    func test_startStopRestart_resumesObservation_withoutSelfCapture() {
        XCTAssertEqual(ObjCAllocInterception.start(), .ok)
        ObjCAllocInterception.stop()
        XCTAssertFalse(ObjCAllocInterception.isRunning)

        XCTAssertEqual(ObjCAllocInterception.start(), .ok, "Restart re-enables without reinstalling")
        XCTAssertTrue(ObjCAllocInterception.isRunning)

        let before = ObjCAllocInterception.diagnostics().totalInvocations
        autoreleasepool {
            for i in 0..<500 { _ = ObjCFixture(payload: i) } // would recurse if self-captured
        }
        XCTAssertGreaterThan(ObjCAllocInterception.diagnostics().totalInvocations, before)
    }

    /// After stop(), the trampoline stays installed and keeps forwarding (never
    /// restored), so allocations continue to work and simply stop being observed.
    func test_allocationsStillWorkAfterStop() {
        XCTAssertEqual(ObjCAllocInterception.start(), .ok)
        ObjCAllocInterception.stop()

        let observedBefore = ObjCAllocInterception.diagnostics().observedAllocations
        let invocationsBefore = ObjCAllocInterception.diagnostics().totalInvocations
        autoreleasepool {
            for i in 0..<500 { _ = ObjCFixture(payload: i) } // must not crash; must forward normally
        }
        let diag = ObjCAllocInterception.diagnostics()
        XCTAssertEqual(
            diag.observedAllocations, observedBefore,
            "A stopped interceptor must not observe allocations"
        )
        XCTAssertGreaterThan(
            diag.totalInvocations, invocationsBefore,
            "Never-restore: the trampoline stays installed and keeps forwarding after stop()"
        )
    }

    // MARK: - Composition with third-party swizzles

    /// A third-party -dealloc swizzle installed BEFORE us must keep firing after
    /// we install on top (our trampoline forwards down to it), and our own
    /// deallocation observation must also fire.
    func test_composesWithThirdPartyDeallocSwizzleInstalledBeforeUs() {
        let (thirdParty, _, _) = installThirdPartyDeallocCounter()
        defer { thirdParty.disable() } // cannot restore (we sit on top); neutralise instead

        XCTAssertEqual(ObjCAllocInterception.start(), .ok)

        let ourBefore = ObjCAllocInterception.diagnostics().totalDeallocInvocations
        let theirBefore = thirdParty.count
        autoreleasepool {
            for i in 0..<300 { _ = ObjCFixture(payload: i) }
        }

        XCTAssertGreaterThan(
            ObjCAllocInterception.diagnostics().totalDeallocInvocations, ourBefore,
            "Our -dealloc trampoline must fire"
        )
        XCTAssertGreaterThan(
            thirdParty.count, theirBefore,
            "The pre-existing third-party swizzle must still fire — we forward down to it"
        )
    }

    /// A third-party -dealloc swizzle installed AFTER us captures our trampoline
    /// as its forward target. Calling stop() must NOT restore an IMP: the
    /// third-party layer keeps working and nothing crashes. (This is the RUM
    /// 3.8.0-class hazard the never-restore discipline prevents.)
    func test_stopDoesNotClobberSwizzleInstalledAfterUs() {
        XCTAssertEqual(ObjCAllocInterception.start(), .ok)

        // Third-party installs ON TOP of us, capturing our trampoline.
        let (thirdParty, method, installedIMP) = installThirdPartyDeallocCounter()

        // Stopping our layer must not touch the -dealloc IMP.
        ObjCAllocInterception.stop()

        let theirBefore = thirdParty.count
        autoreleasepool {
            for i in 0..<300 { _ = ObjCFixture(payload: i) }
        }
        XCTAssertGreaterThan(
            thirdParty.count, theirBefore,
            "A swizzle installed after us must survive our stop() — stop() never restores"
        )

        // Safe cleanup: we are the outermost layer, so restoring our captured
        // forward target (our still-installed trampoline) does not clobber anyone.
        if method_getImplementation(method) == installedIMP {
            method_setImplementation(method, thirdParty.previousIMP)
        }
        thirdParty.disable()
    }

    // MARK: - Concurrency

    func test_concurrentAllocationsUnderRunningHookDoNotCrash() {
        XCTAssertEqual(ObjCAllocInterception.start(), .ok)

        let threadCount = 8
        let allocsPerThread = 2_000
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "objc.alloc.concurrent", attributes: .concurrent)
        for _ in 0..<threadCount {
            group.enter()
            queue.async {
                autoreleasepool {
                    for i in 0..<allocsPerThread { _ = ObjCFixture(payload: i) }
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success, "Threads should finish within 30s")
        XCTAssertGreaterThanOrEqual(
            ObjCAllocInterception.diagnostics().totalInvocations,
            UInt64(threadCount * allocsPerThread),
            "Every allocation should have invoked the trampoline"
        )
    }
}

#endif
