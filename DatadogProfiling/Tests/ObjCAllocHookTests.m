/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>
#import <malloc/malloc.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>
#import <unistd.h>

#import "objc_alloc_hook.h"
#import "objc_alloc_hook_testing.h"
#import "memory_live_set.h"

static _Atomic(uint64_t) targetAllocations;
static _Atomic(uint64_t) targetDeallocations;
static _Atomic(uintptr_t) targetAddress;
static _Atomic(uintptr_t) freedAddress;
static _Atomic(uint64_t) targetSize;
static _Atomic(bool) tearingDown;
static _Atomic(uint64_t) messagesDuringTeardown;

@interface DDObjCAllocFixture : NSObject
@property(nonatomic) uint64_t payload;
@end

// Keep the IMP bridge outside ARC ownership inference: +allocWithZone:
// returns a retained object, while a plain C function returning id does not.
typedef void *(*AllocIMP)(Class, SEL, struct _NSZone *);
typedef void (*DeallocIMP)(__unsafe_unretained id, SEL);

static IMP beforeAllocNext;
static IMP beforeDeallocNext;
static IMP afterAllocNext;
static IMP afterDeallocNext;
static _Atomic(bool) beforeEnabled;
static _Atomic(uint64_t) beforeAllocations;
static _Atomic(uint64_t) beforeDeallocations;
static _Atomic(uint64_t) afterAllocations;
static _Atomic(uint64_t) afterDeallocations;
static dispatch_semaphore_t observerEntered;
static dispatch_semaphore_t observerRelease;
static _Atomic(uint64_t) replacementAllocations;
static _Atomic(int) replacementStartStatus;
static _Atomic(dd_memory_live_set_t *) liveTable;
static _Atomic(uint64_t) liveGeneration;

static void observeAllocation(const void *address, uint64_t size, const char *name);
static void observeDeallocation(const void *address);
static void observeBlockingAllocation(const void *address, uint64_t size, const char *name);
static void observeBlockingDeallocation(const void *address);
static void observeReplacementAllocation(const void *address, uint64_t size, const char *name);
static void observeReplacementDeallocation(const void *address);
static void observeLiveAllocation(const void *address, uint64_t size, const char *name);
static void observeLiveDeallocation(const void *address);
static dd_swift_class_name_t resolveUnusedSwiftName(const HeapMetadata *metadata);
static void *beforeAlloc(Class cls, SEL selector, struct _NSZone *zone);
static void beforeDealloc(__unsafe_unretained id object, SEL selector);
static void *afterAlloc(Class cls, SEL selector, struct _NSZone *zone);
static void afterDealloc(__unsafe_unretained id object, SEL selector);

@interface ObjCAllocHookTests : XCTestCase
@end

@implementation ObjCAllocHookTests

- (void)testSnapshotOwnsObjCNameAndReportsRequiredStorage {
    dd_memory_live_set_t *table = dd_memory_live_set_create();
    XCTAssertNotEqual(table, NULL);
    if (table == NULL) {
        return;
    }
    uint64_t generation = dd_memory_live_set_start(table);
    char mutableName[] = "TransientFixture";
    dd_memory_live_sample_t sample = {0};
    sample.address = (const void *)0x10000;
    sample.size = 42;
    sample.class_name = mutableName;
    sample.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC;
    dd_memory_live_sample_t invalid = sample;
    invalid.class_name = NULL;
    invalid.swift_metadata = (const HeapMetadata *)0x10;
    XCTAssertEqual(dd_memory_live_set_insert(table, generation, &invalid),
                   DD_MEMORY_LIVE_SET_INVALID_SAMPLE);
    invalid.class_name = mutableName;
    invalid.swift_name_resolver = resolveUnusedSwiftName;
    XCTAssertEqual(dd_memory_live_set_insert(table, generation, &invalid),
                   DD_MEMORY_LIVE_SET_INVALID_SAMPLE);
    XCTAssertEqual(dd_memory_live_set_insert(table, generation, &sample),
                   DD_MEMORY_LIVE_SET_INSERTED);
    mutableName[0] = 'X';

    dd_memory_live_sample_t output = {0};
    output.size = 123;
    char shortNames[4] = {0};
    size_t count = 99;
    size_t required = 0;
    XCTAssertFalse(dd_memory_live_set_snapshot(table, generation, &output, 1,
                                                shortNames, sizeof(shortNames),
                                                &count, &required));
    XCTAssertEqual(count, (size_t)0);
    XCTAssertEqual(required, sizeof(mutableName));
    XCTAssertEqual(output.size, (uint64_t)123);

    char snapshotNames[sizeof(mutableName)] = {0};
    XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, &output, 1,
                                               snapshotNames, sizeof(snapshotNames),
                                               &count, &required));
    XCTAssertEqual(count, (size_t)1);
    XCTAssertEqual(required, sizeof(mutableName));
    XCTAssertEqual((const void *)output.class_name, (const void *)snapshotNames);
    XCTAssertTrue(dd_memory_live_set_remove(table, generation, sample.address));
    dd_memory_live_set_destroy(table);
    dd_memory_live_class_name_t name = dd_memory_live_sample_class_name(&output);
    XCTAssertEqual(name.length, (uint64_t)(sizeof(mutableName) - 1));
    XCTAssertEqual(strcmp(name.data, "TransientFixture"), 0);
}

- (void)testOversizedObjCNameIsOmittedWithoutBorrowing {
    dd_memory_live_set_t *table = dd_memory_live_set_create();
    XCTAssertNotEqual(table, NULL);
    if (table == NULL) {
        return;
    }
    uint64_t generation = dd_memory_live_set_start(table);
    char longName[DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES + 1];
    memset(longName, 'A', sizeof(longName) - 1);
    longName[sizeof(longName) - 1] = '\0';
    dd_memory_live_sample_t sample = {0};
    sample.address = (const void *)0x10000;
    sample.class_name = longName;
    sample.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC;
    XCTAssertEqual(dd_memory_live_set_insert(table, generation, &sample),
                   DD_MEMORY_LIVE_SET_INSERTED);
    memset(longName, 'X', sizeof(longName) - 1);

    dd_memory_live_sample_t output = {0};
    size_t count = 0;
    size_t required = 99;
    XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, &output, 1,
                                               NULL, 0, &count, &required));
    XCTAssertEqual(count, (size_t)1);
    XCTAssertEqual(required, (size_t)0);
    XCTAssertEqual(output.class_name, NULL);
    XCTAssertEqual(dd_memory_live_set_diagnostics(table).omitted_class_names, (uint64_t)1);
    dd_memory_live_set_destroy(table);
}

- (void)testPartialFailureCompositionAndStop {
    Class root = objc_getClass("NSObject");
    Method allocMethod = class_getClassMethod(root, sel_registerName("allocWithZone:"));
    Method deallocMethod = class_getInstanceMethod(root, sel_registerName("dealloc"));
    XCTAssertNotEqual(allocMethod, NULL);
    XCTAssertNotEqual(deallocMethod, NULL);
    if (allocMethod == NULL || deallocMethod == NULL) {
        return;
    }

    // A third-party layer installed first must remain in the forwarding chain.
    atomic_store(&beforeEnabled, true);
    beforeAllocNext = method_getImplementation(allocMethod);
    beforeDeallocNext = method_getImplementation(deallocMethod);
    beforeAllocNext = method_setImplementation(allocMethod, (IMP)beforeAlloc);
    beforeDeallocNext = method_setImplementation(deallocMethod, (IMP)beforeDealloc);

    XCTAssertEqual(dd_objc_alloc_hook_start(NULL, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_FAILED_INVALID_OBSERVER);
    XCTAssertFalse(dd_objc_alloc_hook_diagnostics().is_enabled);

    // Simulate the second method failing after the first IMP was replaced.
    dd_objc_alloc_hook_test_fail_after_alloc_once();
    XCTAssertEqual(dd_objc_alloc_hook_start(observeAllocation, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_FAILED_INSTALL);
    dd_objc_alloc_hook_diagnostics_t partial = dd_objc_alloc_hook_diagnostics();
    XCTAssertTrue(partial.alloc_installed);
    XCTAssertFalse(partial.dealloc_installed);
    XCTAssertFalse(partial.is_enabled);

    uint64_t beforeCount = atomic_load(&beforeAllocations);
    @autoreleasepool {
        DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
        fixture.payload = 1;
        XCTAssertEqual(fixture.payload, 1);
    }
    XCTAssertGreaterThan(atomic_load(&beforeAllocations), beforeCount);
    XCTAssertEqual(atomic_load(&targetAllocations), 0);

    // Retrying finishes the missing layer without re-capturing our own alloc IMP.
    XCTAssertEqual(dd_objc_alloc_hook_start(observeAllocation, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_OK);
    dd_objc_alloc_hook_diagnostics_t installed = dd_objc_alloc_hook_diagnostics();
    XCTAssertTrue(installed.alloc_installed);
    XCTAssertTrue(installed.dealloc_installed);
    XCTAssertTrue(installed.is_enabled);
    XCTAssertEqual(dd_objc_alloc_hook_start(NULL, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_FAILED_INVALID_OBSERVER);
    XCTAssertEqual(dd_objc_alloc_hook_start(observeAllocation, NULL),
                   DD_OBJC_ALLOC_HOOK_FAILED_INVALID_OBSERVER);
    XCTAssertTrue(dd_objc_alloc_hook_diagnostics().is_enabled);

    atomic_store(&tearingDown, false);
    atomic_store(&messagesDuringTeardown, 0);
    uintptr_t fixtureAddress = 0;
    @autoreleasepool {
        DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
        fixture.payload = 42;
        fixtureAddress = (uintptr_t)(__bridge void *)fixture;
        XCTAssertEqual(atomic_load(&targetAddress), fixtureAddress);
        XCTAssertEqual(atomic_load(&targetSize),
                       (uint64_t)malloc_size((__bridge const void *)fixture));
        XCTAssertGreaterThan(atomic_load(&targetSize), 0);
    }
    XCTAssertEqual(atomic_load(&freedAddress), fixtureAddress);
    XCTAssertGreaterThan(atomic_load(&targetDeallocations), 0);
    XCTAssertEqual(atomic_load(&messagesDuringTeardown), 0);
    XCTAssertGreaterThan(atomic_load(&beforeDeallocations), 0);

    // A later layer must be able to forward through us.
    afterAllocNext = method_getImplementation(allocMethod);
    afterDeallocNext = method_getImplementation(deallocMethod);
    afterAllocNext = method_setImplementation(allocMethod, (IMP)afterAlloc);
    afterDeallocNext = method_setImplementation(deallocMethod, (IMP)afterDealloc);
    uint64_t afterAllocBefore = atomic_load(&afterAllocations);
    uint64_t afterDeallocBefore = atomic_load(&afterDeallocations);
    @autoreleasepool {
        DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
        fixture.payload = 2;
    }
    XCTAssertGreaterThan(atomic_load(&afterAllocations), afterAllocBefore);
    XCTAssertGreaterThan(atomic_load(&afterDeallocations), afterDeallocBefore);
    XCTAssertTrue(dd_objc_alloc_hook_diagnostics().has_outer_alloc_hook);
    XCTAssertTrue(dd_objc_alloc_hook_diagnostics().has_outer_dealloc_hook);

    // Stop leaves the later layer installed and forwarding, without observing.
    uint64_t observedBefore = atomic_load(&targetAllocations);
    dd_objc_alloc_hook_stop();
    XCTAssertEqual(method_getImplementation(allocMethod), (IMP)afterAlloc);
    XCTAssertEqual(method_getImplementation(deallocMethod), (IMP)afterDealloc);
    afterAllocBefore = atomic_load(&afterAllocations);
    @autoreleasepool {
        DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
        fixture.payload = 3;
    }
    XCTAssertGreaterThan(atomic_load(&afterAllocations), afterAllocBefore);
    XCTAssertEqual(atomic_load(&targetAllocations), observedBefore);

    // The outer layer can be removed while our forwarding trampoline remains.
    if (method_getImplementation(allocMethod) == (IMP)afterAlloc) {
        method_setImplementation(allocMethod, afterAllocNext);
    }
    if (method_getImplementation(deallocMethod) == (IMP)afterDealloc) {
        method_setImplementation(deallocMethod, afterDeallocNext);
    }
    XCTAssertEqual(dd_objc_alloc_hook_start(observeAllocation, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED);
    XCTAssertFalse(dd_objc_alloc_hook_diagnostics().has_outer_alloc_hook);

    // An inner layer must be neutralised in place; removing its IMP would
    // break the outer forwarding chain. Our observation continues.
    atomic_store(&beforeEnabled, false);
    beforeCount = atomic_load(&beforeAllocations);
    observedBefore = atomic_load(&targetAllocations);
    @autoreleasepool {
        DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
        fixture.payload = 4;
    }
    XCTAssertEqual(atomic_load(&beforeAllocations), beforeCount);
    XCTAssertGreaterThan(atomic_load(&targetAllocations), observedBefore);

    // Replacing observers waits for a callback from the previous pair.
    observerEntered = dispatch_semaphore_create(0);
    observerRelease = dispatch_semaphore_create(0);
    XCTAssertEqual(dd_objc_alloc_hook_start(observeBlockingAllocation, observeBlockingDeallocation),
                   DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED);
    dispatch_group_t blockedAllocation = dispatch_group_create();
    dispatch_group_async(blockedAllocation, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        @autoreleasepool {
            DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
            fixture.payload = 5;
        }
    });
    XCTAssertEqual(dispatch_semaphore_wait(observerEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);
    dispatch_semaphore_t replacementStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t replacementFinished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        dispatch_semaphore_signal(replacementStarted);
        atomic_store(&replacementStartStatus,
                     dd_objc_alloc_hook_start(observeReplacementAllocation, observeReplacementDeallocation));
        dispatch_semaphore_signal(replacementFinished);
    });
    XCTAssertEqual(dispatch_semaphore_wait(replacementStarted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);
    for (int attempt = 0; attempt < 5000 && dd_objc_alloc_hook_diagnostics().is_enabled; ++attempt) {
        usleep(1000);
    }
    XCTAssertFalse(dd_objc_alloc_hook_diagnostics().is_enabled);
    XCTAssertNotEqual(dispatch_semaphore_wait(replacementFinished,
                                              dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)), 0);
    dispatch_semaphore_signal(observerRelease);
    XCTAssertEqual(dispatch_group_wait(blockedAllocation, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);
    XCTAssertEqual(dispatch_semaphore_wait(replacementFinished, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);
    XCTAssertEqual(atomic_load(&replacementStartStatus), DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED);
    uint64_t replacementCount = atomic_load(&replacementAllocations);
    @autoreleasepool {
        DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
        fixture.payload = 6;
    }
    XCTAssertGreaterThan(atomic_load(&replacementAllocations), replacementCount);
    XCTAssertEqual(dd_objc_alloc_hook_start(observeAllocation, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED);

    // Stop during concurrent allocations must keep both forwarding paths safe.
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_signal(started);
        for (int index = 0; index < 1000; ++index) {
            @autoreleasepool {
                DDObjCAllocFixture *fixture = [DDObjCAllocFixture new];
                fixture.payload = (uint64_t)index;
            }
        }
    });
    XCTAssertEqual(dispatch_semaphore_wait(started, DISPATCH_TIME_FOREVER), 0);
    dd_objc_alloc_hook_stop();
    XCTAssertEqual(dd_objc_alloc_hook_start(observeAllocation, observeDeallocation),
                   DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED);
    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0);
    dd_objc_alloc_hook_stop();

    // Feed actual ARC allocation/deallocation callbacks into the live table.
    dd_memory_live_set_t *table = dd_memory_live_set_create();
    XCTAssertNotEqual(table, NULL);
    if (table == NULL) {
        return;
    }
    uint64_t generation = dd_memory_live_set_start(table);
    atomic_store(&liveTable, table);
    atomic_store(&liveGeneration, generation);
    XCTAssertEqual(dd_objc_alloc_hook_start(observeLiveAllocation, observeLiveDeallocation),
                   DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED);
    __attribute__((objc_precise_lifetime)) DDObjCAllocFixture *first = [DDObjCAllocFixture new];
    __attribute__((objc_precise_lifetime)) DDObjCAllocFixture *second = [DDObjCAllocFixture new];
    __attribute__((objc_precise_lifetime)) DDObjCAllocFixture *third = [DDObjCAllocFixture new];
    dd_memory_live_sample_t liveSamples[3] = {0};
    char firstSnapshotNames[128] = {0};
    char laterSnapshotNames[128] = {0};
    size_t liveCount = 0;
    XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, liveSamples, 3,
                                               firstSnapshotNames, sizeof(firstSnapshotNames),
                                               &liveCount, NULL));
    XCTAssertEqual(liveCount, (size_t)3);
    dd_memory_live_class_name_t className = dd_memory_live_sample_class_name(&liveSamples[0]);
    XCTAssertNotEqual(className.data, NULL);
    if (className.data != NULL) {
        XCTAssertEqual(className.length, (uint64_t)strlen("DDObjCAllocFixture"));
        XCTAssertEqual(strncmp(className.data, "DDObjCAllocFixture", (size_t)className.length), 0);
    }
    first = nil;
    XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, liveSamples, 3,
                                               laterSnapshotNames, sizeof(laterSnapshotNames),
                                               &liveCount, NULL));
    XCTAssertEqual(liveCount, (size_t)2);
    second = nil;
    third = nil;
    XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, liveSamples, 3,
                                               laterSnapshotNames, sizeof(laterSnapshotNames),
                                               &liveCount, NULL));
    XCTAssertEqual(liveCount, (size_t)0);
    dd_objc_alloc_hook_stop();
    atomic_store(&liveTable, NULL);
    dd_memory_live_set_destroy(table);
}

@end

static dd_swift_class_name_t resolveUnusedSwiftName(const HeapMetadata *metadata) {
    return (dd_swift_class_name_t){NULL, 0};
}

@implementation DDObjCAllocFixture
- (Class)class {
    if (atomic_load(&tearingDown)) {
        atomic_fetch_add(&messagesDuringTeardown, 1);
    }
    return [super class];
}

- (void)dealloc {
    // NSObject's dealloc trampoline runs after this subclass body.
    atomic_store(&tearingDown, true);
}
@end

static void observeAllocation(const void *address, uint64_t size, const char *name) {
    if (name != NULL && strcmp(name, "DDObjCAllocFixture") == 0) {
        atomic_store(&targetAddress, (uintptr_t)address);
        atomic_store(&targetSize, size);
        atomic_fetch_add(&targetAllocations, 1);
    }
}

static void observeDeallocation(const void *address) {
    if ((uintptr_t)address == atomic_load(&targetAddress)) {
        atomic_store(&freedAddress, (uintptr_t)address);
        atomic_fetch_add(&targetDeallocations, 1);
    }
}

static void observeBlockingAllocation(const void *address, uint64_t size, const char *name) {
    (void)address;
    (void)size;
    if (name != NULL && strcmp(name, "DDObjCAllocFixture") == 0) {
        dispatch_semaphore_signal(observerEntered);
        dispatch_semaphore_wait(observerRelease, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    }
}

static void observeBlockingDeallocation(const void *address) { (void)address; }

static void observeReplacementAllocation(const void *address, uint64_t size, const char *name) {
    (void)address;
    (void)size;
    if (name != NULL && strcmp(name, "DDObjCAllocFixture") == 0) {
        atomic_fetch_add(&replacementAllocations, 1);
    }
}

static void observeReplacementDeallocation(const void *address) { (void)address; }

static void observeLiveAllocation(const void *address, uint64_t size, const char *name) {
    if (name == NULL || strcmp(name, "DDObjCAllocFixture") != 0) {
        return;
    }
    dd_memory_live_set_t *table = atomic_load(&liveTable);
    dd_memory_live_sample_t sample = {0};
    sample.address = address;
    sample.size = size;
    sample.weight = 1;
    sample.class_name = name;
    sample.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC;
    dd_memory_live_set_insert(table, atomic_load(&liveGeneration), &sample);
}

static void observeLiveDeallocation(const void *address) {
    dd_memory_live_set_t *table = atomic_load(&liveTable);
    dd_memory_live_set_remove(table, atomic_load(&liveGeneration), address);
}

static void *beforeAlloc(Class cls, SEL selector, struct _NSZone *zone) {
    if (atomic_load(&beforeEnabled)) {
        atomic_fetch_add(&beforeAllocations, 1);
    }
    void *object = ((AllocIMP)beforeAllocNext)(cls, selector, zone);
    return object;
}

static void beforeDealloc(__unsafe_unretained id object, SEL selector) {
    if (atomic_load(&beforeEnabled)) {
        atomic_fetch_add(&beforeDeallocations, 1);
    }
    ((DeallocIMP)beforeDeallocNext)(object, selector);
}

static void *afterAlloc(Class cls, SEL selector, struct _NSZone *zone) {
    atomic_fetch_add(&afterAllocations, 1);
    return ((AllocIMP)afterAllocNext)(cls, selector, zone);
}

static void afterDealloc(__unsafe_unretained id object, SEL selector) {
    atomic_fetch_add(&afterDeallocations, 1);
    ((DeallocIMP)afterDeallocNext)(object, selector);
}
