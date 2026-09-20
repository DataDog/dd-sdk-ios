import Foundation
import UIKit
import ObjectiveC
@_spi(Internal) @testable import DatadogInternal

private struct FixtureFailure: Error { let reason: String }
private func demand(_ good: Bool, _ reason: String) throws { if !good { throw FixtureFailure(reason: reason) } }
private func wait(_ signal: DispatchSemaphore, _ reason: String) throws { try demand(signal.wait(timeout: .now()+5) == .success, reason) }
private final class WeakSlot { weak var value: AnyObject? }
private final class OutstandingTracker {
    private let lock = NSLock()
    private var current = 0
    private var maximum = 0
    func reset() { lock.lock(); current = 0; maximum = 0; lock.unlock() }
    func enter() { lock.lock(); current += 1; maximum = max(maximum, current); lock.unlock() }
    func leave() { lock.lock(); current -= 1; lock.unlock() }
    func observedMaximum() -> Int { lock.lock(); defer { lock.unlock() }; return maximum }
    func balanced() -> Bool { lock.lock(); defer { lock.unlock() }; return current == 0 }
}
private struct ReceiverSnapshot { let mutations: Int; let starts: Int; let completions: Int; let bodyBytes: Int; let lastBodyBytes: Int; let metrics: Int }
private struct ChannelSnapshot {
    let preparedHeader: String?
    let bodyBytes: Int
    let metrics: Int
    let completionCalls: Int
    let protocolStarts: Int
    let protocolCompletions: Int
    let invalidations: Int
    let errors: Int
    let taskMetrics: URLSessionTaskMetrics?
}
private struct LifecycleTally {
    var operations = 0, nativeTaskLifecycles = 0, resumeCalls = 0, mutations = 0, starts = 0, completions = 0, nativeCompletions = 0
    var protocolStarts = 0, protocolCompletions = 0, invalidations = 0, errors = 0, dataBytes = 0, metrics = 0, outstandingEnters = 0, outstandingLeaves = 0
    mutating func append(channel: ChannelSnapshot) {
        operations += 1; nativeTaskLifecycles += 1
        protocolStarts += channel.protocolStarts; protocolCompletions += channel.protocolCompletions
        nativeCompletions += channel.completionCalls; invalidations += channel.invalidations; errors += channel.errors; dataBytes += channel.bodyBytes; metrics += channel.metrics
    }
    func json(outstandingMax: Int = 0) -> [String: Int] { ["operations":operations,"native_task_lifecycles":nativeTaskLifecycles,"resume_calls":resumeCalls,"mutations":mutations,"starts":starts,"completions":completions,"native_completions":nativeCompletions,"protocol_starts":protocolStarts,"protocol_completions":protocolCompletions,"invalidations":invalidations,"errors":errors,"data_bytes":dataBytes,"metrics":metrics,"outstanding_enters":outstandingEnters,"outstanding_leaves":outstandingLeaves,"outstanding_max":outstandingMax] }
}
private final class Channel {
    let lock=NSLock()
    let started=DispatchSemaphore(value:0), completed=DispatchSemaphore(value:0), invalidated=DispatchSemaphore(value:0)
    var transport: LocalProtocol?
    var preparedHeader: String?
    var bodyBytes=0, metrics=0, completionCalls=0
    // This is captured from an untimed, real registered-delegate delivery and
    // used only as the concrete metrics input for the held-task entry row.
    var taskMetrics: URLSessionTaskMetrics?
    func snapshot() -> ChannelSnapshot {
        lock.lock(); defer { lock.unlock() }
        return ChannelSnapshot(preparedHeader:preparedHeader,bodyBytes:bodyBytes,metrics:metrics,completionCalls:completionCalls,protocolStarts:protocolStarts,protocolCompletions:protocolCompletions,invalidations:invalidations,errors:errors,taskMetrics:taskMetrics)
    }
    var protocolStarts=0, protocolCompletions=0, invalidations=0, errors=0
}
private final class LocalProtocol: URLProtocol {
    static let lock=NSLock()
    static var channels=[String:Channel]()
    static let chunk=Data(repeating: 7,count:256)
    static var bodyBytes=1024
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "e01.fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock();let channel=Self.channels[request.url!.path];Self.lock.unlock()
        guard let channel else { return }
        channel.lock.lock();channel.preparedHeader=request.value(forHTTPHeaderField:"X-E01-Prepared");channel.transport=self;channel.protocolStarts += 1;channel.lock.unlock();channel.started.signal()
    }
    override func stopLoading() {}
    func finish() {
        let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json","Content-Length":String(Self.bodyBytes)])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        if Self.bodyBytes>0 {for _ in 0..<4 { client?.urlProtocol(self,didLoad:Self.chunk) }}
        client?.urlProtocolDidFinishLoading(self)
        Self.lock.lock();let channel=Self.channels[request.url!.path];Self.lock.unlock();channel?.lock.lock();channel?.protocolCompletions += 1;channel?.lock.unlock()
    }
}
private final class Receiver: DatadogURLSessionHandler {
    let firstPartyHosts=FirstPartyHosts(["e01.fixture.invalid":Set([TracingHeaderType.datadog])])
    let lock=NSLock()
    var mutations=0, starts=0, completions=0, bodyBytes=0, lastBodyBytes=0, metricCompletions=0
    var interceptionSlot: WeakSlot?
    var onModify: (() -> Void)?
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest,TraceContext?,URLSessionHandlerCapturedState?) {
        lock.lock();mutations+=1;let callback=onModify;lock.unlock()
        callback?()
        var request=request;request.setValue("1",forHTTPHeaderField:"X-E01-Prepared");return(request,nil,nil)
    }
    func interceptionDidStart(interception: URLSessionTaskInterception, capturedStates: [any URLSessionHandlerCapturedState]) {
        lock.lock();starts+=1;lock.unlock();interceptionSlot?.value=interception
    }
    func interceptionDidComplete(interception: URLSessionTaskInterception) {
        lock.lock();completions+=1;lastBodyBytes=interception.data?.count ?? 0;bodyBytes += lastBodyBytes;if interception.metrics != nil {metricCompletions+=1};lock.unlock()
    }
}
private final class Delegate: NSObject, URLSessionDataDelegate {
    let channel:Channel
    init(_ channel:Channel){self.channel=channel}
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data){channel.lock.lock();channel.bodyBytes+=data.count;channel.lock.unlock()}
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics){channel.lock.lock();channel.metrics+=1;channel.taskMetrics=metrics;channel.lock.unlock()}
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?){channel.lock.lock();channel.completionCalls+=1;if error != nil {channel.errors += 1};channel.lock.unlock();channel.completed.signal()}
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?){channel.lock.lock();channel.invalidations += 1;if error != nil {channel.errors += 1};channel.lock.unlock();channel.invalidated.signal()}
}
private final class AutomaticDelegate: NSObject, URLSessionDelegate {
    let channel:Channel
    init(_ channel:Channel){self.channel=channel}
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?){channel.lock.lock();channel.invalidations += 1;if error != nil {channel.errors += 1};channel.lock.unlock();channel.invalidated.signal()}
}
private final class Operation {
    let path:String, channel:Channel, session:URLSession, task:URLSessionDataTask
    let delegateQueue:OperationQueue
    init(sequence:Int,registered:Bool) {
        path="/task-"+String(sequence);channel=Channel()
        LocalProtocol.lock.lock();LocalProtocol.channels[path]=channel;LocalProtocol.lock.unlock()
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[LocalProtocol.self]
        let queue=OperationQueue();queue.maxConcurrentOperationCount=1;delegateQueue=queue
        if registered {
            session=URLSession(configuration:config,delegate:Delegate(channel),delegateQueue:queue)
            task=session.dataTask(with:URL(string:"https://e01.fixture.invalid"+path)!)
        } else {
            session=URLSession(configuration:config,delegate:AutomaticDelegate(channel),delegateQueue:queue)
            let receipt=channel
            task=session.dataTask(with:URL(string:"https://e01.fixture.invalid"+path)!) { data,_,error in receipt.lock.lock();receipt.bodyBytes=data?.count ?? 0;receipt.completionCalls+=1;if error != nil {receipt.errors += 1};receipt.lock.unlock();receipt.completed.signal() }
        }
    }
    func start() throws {task.resume();try wait(channel.started,"native URLProtocol start missing")}
    func finish() throws {
        channel.lock.lock();let transport=channel.transport;channel.transport=nil;channel.lock.unlock();transport?.finish()
        try wait(channel.completed,"native completion missing")
        try invalidate()
    }
    func invalidate() throws {
        session.finishTasksAndInvalidate();try wait(channel.invalidated,"session invalidation missing");delegateQueue.waitUntilAllOperationsAreFinished()
        LocalProtocol.lock.lock();LocalProtocol.channels[path]=nil;LocalProtocol.lock.unlock()
    }
}
final class E01Fixture {
    private var sequence=0
    private var result=[String:Any]()
    private var modeData=[String:Any]()
    private var feature:NetworkInstrumentationFeature?
    private var receiver:Receiver?
    private var provider:NetworkContextCoreProvider?
    private var registered=false
    private var unbound=false
    private var arm="missing"
    private let outstanding = OutstandingTracker()
    private var rowReceiptStart: ReceiverSnapshot?
    private var phaseReceiptStarts = [String: ReceiverSnapshot?]()
    private var phaseReceiptEnds = [String: ReceiverSnapshot?]()
    private var phaseReceipts = [String: LifecycleTally]()
    private var activeTally = LifecycleTally()
    private var activePhase = "unscoped"
    private var trackedStarts=0, trackedFinishes=0, manualResumeCalls=0
    private let warmTask=WeakSlot()
    private let terminalPreparation=WeakSlot()
    private enum CallbackRow: String, CaseIterable { case data, metrics, completion, state }
    private static let timingWarmupOperations = 1_000
    private static let measuredBatches = 7
    private static let operationsPerBatch = 1_000
    private static let individualSamples = 2_000
    private static let nativeOutstandingLimit = 64
    private struct Inventory { var reflectionAvailable=false, interceptions=0, truncated=0, raw=0, keys=0, values=0, events=0, continuations=0, terminalRaw=0, terminalLive=0, lastSequence=0, phases=[String]() }
    private func next() -> Operation {sequence+=1;return Operation(sequence:sequence,registered:registered)}
    private func featureQueue() throws -> DispatchQueue {
        let queue=Mirror(reflecting:feature!).children.first(where:{$0.label=="queue"})?.value as? DispatchQueue
        try demand(queue != nil,"feature queue unavailable");return queue!
    }
    private func constructFeature() {
        guard feature == nil else { return }
        let provider=NetworkContextCoreProvider();self.provider=provider
        let feature=NetworkInstrumentationFeature(networkContextProvider:provider,messageReceiver:provider);self.feature=feature
        let receiver=Receiver();self.receiver=receiver;feature.handlers=[receiver]
    }
    private func bind() throws {
        constructFeature()
        guard let feature else { throw FixtureFailure(reason:"feature construction failed") }
        try feature.bind(configuration:nil)
        if registered {try feature.bind(configuration:.init(delegateClass:Delegate.self))}
    }
    private func flushFeature() { feature?.flush() }
    private func receiverSnapshot() -> ReceiverSnapshot? {
        guard let receiver else { return nil }; receiver.lock.lock(); defer { receiver.lock.unlock() }
        return ReceiverSnapshot(mutations:receiver.mutations,starts:receiver.starts,completions:receiver.completions,bodyBytes:receiver.bodyBytes,lastBodyBytes:receiver.lastBodyBytes,metrics:receiver.metricCompletions)
    }
    private func startTracked(_ operation: Operation) throws {
        outstanding.enter(); trackedStarts += 1; activeTally.resumeCalls += 1; activeTally.outstandingEnters += 1; try operation.start();try demandRunning(operation)
    }
    private func demandRunning(_ operation: Operation) throws {
        let receipt=operation.channel.snapshot()
        try demand(operation.task.state == .running && receipt.protocolStarts==1 && receipt.protocolCompletions==0 && receipt.completionCalls==0 && receipt.invalidations==0,"native task was not running and quiet before callback entry")
    }
    private func markManualResume(_ operation: Operation, entersOutstanding: Bool) {
        manualResumeCalls += 1; activeTally.resumeCalls += 1
        if entersOutstanding { outstanding.enter(); trackedStarts += 1; activeTally.outstandingEnters += 1 }
    }
    private func resetObservedLifecycle() {
        outstanding.reset(); trackedStarts=0; trackedFinishes=0;manualResumeCalls=0;phaseReceipts.removeAll(keepingCapacity:true);phaseReceiptStarts.removeAll(keepingCapacity:true);phaseReceiptEnds.removeAll(keepingCapacity:true);activeTally=LifecycleTally();activePhase="unscoped";rowReceiptStart=receiverSnapshot()
    }
    private func beginPhase(_ name: String) {
        if activePhase != "unscoped" {
            closeActivePhase()
        }
        activePhase=name;phaseReceiptStarts[name]=receiverSnapshot();activeTally=LifecycleTally()
    }
    private func closeActivePhase() {
        let end=receiverSnapshot();let before=phaseReceiptStarts[activePhase] ?? nil
        activeTally.mutations += (end?.mutations ?? 0)-(before?.mutations ?? 0)
        activeTally.starts += (end?.starts ?? 0)-(before?.starts ?? 0)
        activeTally.completions += (end?.completions ?? 0)-(before?.completions ?? 0)
        phaseReceiptEnds[activePhase]=end;phaseReceipts[activePhase]=activeTally
    }
    private func observedLifecycle(_ expected: Int) throws -> [String: Any] {
        try demand(outstanding.balanced(), "outstanding native tasks did not settle")
        if activePhase != "unscoped" { closeActivePhase() }
        let phaseData=phaseReceipts.mapValues { tally -> [String:Int] in tally.json(outstandingMax: outstanding.observedMaximum()) }
        let phaseDeltas=Dictionary(uniqueKeysWithValues: phaseReceiptStarts.map { name, start -> (String, [String:Int]) in
            let end=phaseReceiptEnds[name] ?? receiverSnapshot();let before=start ?? nil
            return (name, ["mutations":(end?.mutations ?? 0)-(before?.mutations ?? 0),"starts":(end?.starts ?? 0)-(before?.starts ?? 0),"completions":(end?.completions ?? 0)-(before?.completions ?? 0),"body_bytes":(end?.bodyBytes ?? 0)-(before?.bodyBytes ?? 0),"metrics":(end?.metrics ?? 0)-(before?.metrics ?? 0)])
        })
        return ["expected_measurement_operations":expected,"phase_receipts":phaseData,"phase_receiver_deltas":phaseDeltas,"native_resume_observed":trackedStarts,"manual_resume_observed":manualResumeCalls,"native_completion_observed":trackedFinishes,"native_outstanding_observed_max":outstanding.observedMaximum()]
    }
    private func phase(_ lifecycle: [String: Any], _ name: String, _ expected: Int, label: String? = nil, batches: [UInt64]? = nil, samples: [UInt64]? = nil) -> [String: Any] {
        let all=lifecycle["phase_receipts"] as? [String:[String:Int]] ?? [:]
        let deltas=lifecycle["phase_receiver_deltas"] as? [String:[String:Int]] ?? [:]
        var output:[String:Any] = ["expected_operations":expected,"receipts":all[name] ?? [:],"receiver_delta":deltas[name] ?? [:]]
        if let label { output["label"]=label }
        if let batches { output["batch_ns"]=batches }
        if let samples { output["samples_ns"]=samples }
        return output
    }
    private func allocationBatches(_ raw: [[String:Any]], _ lifecycle: [String:Any]) -> [[String:Any]] {
        let all=lifecycle["phase_receipts"] as? [String:[String:Int]] ?? [:]
        return raw.enumerated().map { index, batch in
            ["expected_operations":batch["operations"] ?? batch["tasks"] ?? 0,"receipts":all["allocation_batch_\(index)"] ?? [:],"windows":batch["windows"] ?? [],"window_denominators":batch["window_denominators"] ?? []]
        }
    }
    private func aggregateReceipts(_ lifecycle: [String:Any], prefix: String) -> [String:Int] {
        let all=lifecycle["phase_receipts"] as? [String:[String:Int]] ?? [:]
        var total=[String:Int]()
        for (name, receipt) in all where name.hasPrefix(prefix) {
            for (key, value) in receipt { if key == "outstanding_max" { total[key]=max(total[key] ?? 0,value) } else { total[key, default:0] += value } }
        }
        return total
    }
    private func finishTracked(_ operation: Operation) throws {
        let quiet=operation.channel.snapshot();try demand(quiet.protocolStarts==1 && quiet.protocolCompletions==0 && quiet.completionCalls==0 && quiet.invalidations==0 && quiet.bodyBytes==0 && quiet.metrics==0 && quiet.errors==0,"native task was not quiet before held transport release");try operation.finish(); outstanding.leave();trackedFinishes += 1;activeTally.outstandingLeaves += 1;let receipt=operation.channel.snapshot();try demand(receipt.protocolStarts==1 && receipt.protocolCompletions==1 && receipt.completionCalls==1 && receipt.invalidations==1 && receipt.errors==0,"native task callback receipt was not exactly once after window");activeTally.append(channel:receipt)
    }
    private func roundtrip() throws -> [String:Any] {
        resetObservedLifecycle();beginPhase("roundtrip")
        let before=receiverSnapshot();let op=next();warmTask.value=op.task;try startTracked(op);flushFeature();try finishTracked(op);flushFeature();let after=receiverSnapshot();let channel=op.channel.snapshot()
        let receiverDelta:[String:Int] = ["mutations":(after?.mutations ?? 0)-(before?.mutations ?? 0),"starts":(after?.starts ?? 0)-(before?.starts ?? 0),"completions":(after?.completions ?? 0)-(before?.completions ?? 0),"body_bytes":(after?.bodyBytes ?? 0)-(before?.bodyBytes ?? 0),"metrics":(after?.metrics ?? 0)-(before?.metrics ?? 0)]
        let lifecycle=try observedLifecycle(1)
        let receipts=(lifecycle["phase_receipts"] as? [String:[String:Int]])?["roundtrip"] ?? [:]
        let expected=unbound ? 0 : 1
        try demand(receiverDelta["mutations"]==expected && receiverDelta["starts"]==expected && receiverDelta["completions"]==expected,"native lifecycle not exactly once")
        try demand(channel.preparedHeader==(unbound ? nil : "1") && channel.bodyBytes==LocalProtocol.bodyBytes && receiverDelta["body_bytes"]==(unbound ? 0:LocalProtocol.bodyBytes),"native header/body mismatch")
        try demand(!registered || unbound || (channel.metrics==1 && (receiverDelta["metrics"] ?? 0)>=1),"registered metrics missing")
        return ["task_identity":op.path,"prepared_header":channel.preparedHeader ?? NSNull(),"receipts":receipts,"native_completions":channel.completionCalls,"native_errors":channel.errors,"native_body_bytes":channel.bodyBytes,"receiver_body_bytes":receiverDelta["body_bytes"] ?? 0,"receiver_delta":receiverDelta,"metrics_applicability":registered ? "registered_observed":"automatic_inapplicable"]
    }
    private func counts(_ r:E01AllocationResult)->[String:Any]{["process_operations":r.process.operations,"process_bytes":r.process.requested_bytes,"caller_operations":r.caller.operations,"caller_bytes":r.caller.requested_bytes,"other_operations":r.other.operations,"other_bytes":r.other.requested_bytes]}
    private func calibrate() throws {
        let queue=try featureQueue();queue.sync{}
        let install=e01_allocation_install();try demand(install.error==E01_ALLOCATION_OK && install.lock_free==1,"all-thread logger unavailable or occupied")
        defer {_=e01_allocation_uninstall()}
        var a=E01AllocationResult(), b=E01AllocationResult(), c=E01AllocationResult(), d=E01AllocationResult()
        let caller=e01_allocation_caller_calibrate(&a)
        let actualQueue=e01_calibrate_queue(queue,&b)
        let worker=e01_calibrate_queue(DispatchQueue.global(qos:.utility),&c)
        let concurrent=e01_calibrate_concurrent(&d)
        modeData["calibration"]=["completed":true,"calibration_before_unbound":true,"lock_free":true,"caller":counts(a),"feature_queue":counts(b),"worker":counts(c),"concurrent":counts(d),"passes":["caller":caller==1,"feature_queue":actualQueue==1,"worker":worker==1,"concurrent":concurrent==1,"caller_only_negative_rejected":b.caller.operations==0 && b.other.operations==3]]
        try demand(caller==1 && a.process.operations==3 && a.process.requested_bytes==165 && actualQueue==1 && worker==1 && concurrent==1,"all-thread sentinel calibration failed")
    }
    private func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private func invoke(_ row: CallbackRow, task: URLSessionTask, metrics: URLSessionTaskMetrics?) throws {
        guard let feature else { throw FixtureFailure(reason:"feature unavailable") }
        switch row {
        case .data:
            feature.task(task, didReceive: LocalProtocol.chunk)
        case .metrics:
            guard let metrics else { throw FixtureFailure(reason:"real registered metrics seed unavailable") }
            feature.task(task, didFinishCollecting: metrics)
        case .completion:
            feature.task(task, didCompleteWithError: nil)
        case .state:
            feature.task(task, didChangeToState: URLSessionTask.State.completed.rawValue)
        }
    }
    private func withHeldTask<T>(_ body: (URLSessionTask) throws -> T) throws -> T {
        let released=WeakSlot()
        let answer:T = try autoreleasepool {
            let op=next();released.value=op.task
            try startTracked(op)
            let ready=op.channel.snapshot()
            try demand(op.task.state == .running && ready.protocolStarts==1 && ready.protocolCompletions==0 && ready.completionCalls==0 && ready.invalidations==0,"held native task was not running and quiet before callback entry")
            // This establishes instrumentation before the measured entry point;
            // LocalProtocol holds the native transport through teardown.
            flushFeature()
            do {
                let answer=try body(op.task)
                try finishTracked(op);flushFeature()
                let receipt=op.channel.snapshot()
                try demand(receipt.protocolStarts==1 && receipt.protocolCompletions==1 && receipt.completionCalls==1 && receipt.invalidations==1 && receipt.errors==0,"held native task callback receipt was not exactly once")
                return answer
            } catch {
                try? op.finish();flushFeature();throw error
            }
        }
        try settle([released])
        return answer
    }
    private func metricsSeed() throws -> URLSessionTaskMetrics? {
        guard registered else { return nil }
        let witness=WeakSlot();var metrics:URLSessionTaskMetrics?
        try autoreleasepool {
            let op=next();witness.value=op.task
            try startTracked(op); flushFeature(); try finishTracked(op); flushFeature()
            metrics=op.channel.snapshot().taskMetrics
        }
        try settle([witness])
        return metrics
    }
    private func timingRow(_ row: CallbackRow, metrics: URLSessionTaskMetrics?) throws -> [String:Any] {
        resetObservedLifecycle()
        if row == .metrics && !registered {
            return ["row":row.rawValue,"applicability":"registered_delegate_only"]
        }
        // Sample buffers and batch denominators are allocated before the first
        // warm-up operation.  A task is prepared and held before every entry;
        // at most one native request is outstanding (well below the 64 limit).
        var callerSamples=[UInt64](repeating:0,count:Self.individualSamples)
        var flushSamples=[UInt64](repeating:0,count:Self.individualSamples)
        var callerBatchNs=[UInt64](repeating:0,count:Self.measuredBatches)
        var flushBatchNs=[UInt64](repeating:0,count:Self.measuredBatches)
        func one(flush: Bool) throws -> UInt64 {
            try withHeldTask { task in
                // Registered completion/state samples need the normal companion
                // metrics before the destructive measured callback.
                if registered && (row == .completion || row == .state) {
                    try invoke(.metrics,task:task,metrics:metrics);flushFeature()
                }
                let start=now()
                try invoke(row,task:task,metrics:metrics)
                if flush { flushFeature() }
                return now()-start
            }
        }
        beginPhase("warmup")
        for _ in 0..<Self.timingWarmupOperations { _=try one(flush:false) }
        beginPhase("caller_return")
        for batch in 0..<Self.measuredBatches {
            var total:UInt64=0
            for operation in 0..<Self.operationsPerBatch {
                let value=try one(flush:false)
                total+=value
                let sample=batch*Self.operationsPerBatch+operation
                if sample<Self.individualSamples { callerSamples[sample]=value }
            }
            callerBatchNs[batch]=total
        }
        // This is a distinct entry-through-flush loop, rather than a flush of
        // caller-return work left by the preceding loop.
        beginPhase("through_flush")
        for batch in 0..<Self.measuredBatches {
            var total:UInt64=0
            for operation in 0..<Self.operationsPerBatch {
                let value=try one(flush:true)
                total+=value
                let sample=batch*Self.operationsPerBatch+operation
                if sample<Self.individualSamples { flushSamples[sample]=value }
            }
            flushBatchNs[batch]=total
        }
        let lifecycle=try observedLifecycle(Self.measuredBatches * Self.operationsPerBatch)
        return ["row":row.rawValue,"instrumentation":"instrumented","workload":["discarded_warmup_operations":Self.timingWarmupOperations,"measured_batches":Self.measuredBatches,"operations_per_batch":Self.operationsPerBatch,"measured_operations":Self.measuredBatches*Self.operationsPerBatch,"individual_samples":Self.individualSamples,"outstanding_limit":Self.nativeOutstandingLimit],"warmup":phase(lifecycle,"warmup",Self.timingWarmupOperations),"caller_return":phase(lifecycle,"caller_return",Self.measuredBatches*Self.operationsPerBatch,label:"caller entry to return",batches:callerBatchNs,samples:callerSamples),"through_flush":phase(lifecycle,"through_flush",Self.measuredBatches*Self.operationsPerBatch,label:"entry through immediate feature.flush()",batches:flushBatchNs,samples:flushSamples),"native_outstanding_observed_max":outstanding.observedMaximum()]
    }
    private func resumeTimingRow(_ name: String, secondResume: Bool) throws -> [String:Any] {
        resetObservedLifecycle()
        var callerSamples=[UInt64](repeating:0,count:Self.individualSamples)
        var flushSamples=[UInt64](repeating:0,count:Self.individualSamples)
        var callerBatchNs=[UInt64](repeating:0,count:Self.measuredBatches)
        var flushBatchNs=[UInt64](repeating:0,count:Self.measuredBatches)
        func one(flush: Bool) throws -> UInt64 {
            let released=WeakSlot()
            let elapsed:UInt64 = try autoreleasepool {
                let op=next();released.value=op.task
                if secondResume { try startTracked(op);flushFeature() }
                markManualResume(op, entersOutstanding: !secondResume); let started=now();op.task.resume();if flush { flushFeature() }
                let elapsed=now()-started
                if !secondResume { try wait(op.channel.started,"native URLProtocol start missing");try demandRunning(op) }
                try finishTracked(op);flushFeature()
                return elapsed
            }
            try settle([released])
            return elapsed
        }
        beginPhase("warmup")
        for _ in 0..<Self.timingWarmupOperations { _=try one(flush:false) }
        beginPhase("caller_return")
        for batch in 0..<Self.measuredBatches {
            var total:UInt64=0
            for operation in 0..<Self.operationsPerBatch {
                let sample=batch*Self.operationsPerBatch+operation, value=try one(flush:false)
                total+=value
                if sample<Self.individualSamples { callerSamples[sample]=value }
            }
            callerBatchNs[batch]=total
        }
        beginPhase("through_flush")
        for batch in 0..<Self.measuredBatches {
            var total:UInt64=0
            for operation in 0..<Self.operationsPerBatch {
                let sample=batch*Self.operationsPerBatch+operation, value=try one(flush:true)
                total+=value
                if sample<Self.individualSamples { flushSamples[sample]=value }
            }
            flushBatchNs[batch]=total
        }
        let lifecycle=try observedLifecycle(Self.measuredBatches * Self.operationsPerBatch)
        return ["row":name,"instrumentation":unbound ? "sdk_unbound":"instrumented","resume_ordinal":secondResume ? 2:1,"workload":["discarded_warmup_operations":Self.timingWarmupOperations,"measured_batches":Self.measuredBatches,"operations_per_batch":Self.operationsPerBatch,"measured_operations":Self.measuredBatches*Self.operationsPerBatch,"individual_samples":Self.individualSamples,"outstanding_limit":Self.nativeOutstandingLimit],"warmup":phase(lifecycle,"warmup",Self.timingWarmupOperations),"caller_return":phase(lifecycle,"caller_return",Self.measuredBatches*Self.operationsPerBatch,label:"caller entry to return",batches:callerBatchNs,samples:callerSamples),"through_flush":phase(lifecycle,"through_flush",Self.measuredBatches*Self.operationsPerBatch,label:secondResume ? "second resume through immediate feature flush":"resume through immediate feature flush (already-enqueued SDK work); held start and final flush outside timer",batches:flushBatchNs,samples:flushSamples),"native_outstanding_observed_max":outstanding.observedMaximum()]
    }
    private func allocationRow(_ row: CallbackRow, metrics: URLSessionTaskMetrics?) throws -> [String:Any] {
        resetObservedLifecycle()
        if row == .metrics && !registered {
            return ["row":row.rawValue,"applicability":"registered_delegate_only"]
        }
        // Results are preallocated before logger installation. A measured batch
        // is split into native-held windows of at most 64 tasks: every window's
        // task setup finishes before its epoch begins, and its epoch ends only
        // after the feature queue drains. The raw window results are retained
        // rather than subtracting process noise or collapsing it into a verdict.
        let windowsPerBatch=(Self.operationsPerBatch+Self.nativeOutstandingLimit-1)/Self.nativeOutstandingLimit
        var windows=[E01AllocationResult](repeating:E01AllocationResult(),count:Self.measuredBatches*windowsPerBatch)
        var denominators=[Int](repeating:0,count:Self.measuredBatches*windowsPerBatch)
        func warmup() throws { try withHeldTask { task in
            if registered && (row == .completion || row == .state) { try invoke(.metrics,task:task,metrics:metrics);flushFeature() }
            try invoke(row,task:task,metrics:metrics);flushFeature()
        } }
        let installation=e01_allocation_install()
        try demand(installation.error==E01_ALLOCATION_OK && installation.lock_free==1,"all-thread allocation counter unavailable for raw row")
        defer { _=e01_allocation_uninstall() }
        // Required discarded warm-up is inside an active all-thread counter epoch.
        beginPhase("warmup")
        var discardedEpoch: UInt64 = 0
        try demand(e01_allocation_epoch_begin(&discardedEpoch)==E01_ALLOCATION_OK,"discarded warm-up epoch did not begin")
        for _ in 0..<Self.timingWarmupOperations { try warmup() }
        var discardedResult = E01AllocationResult()
        try demand(e01_allocation_epoch_end(discardedEpoch,&discardedResult)==E01_ALLOCATION_OK,"discarded warm-up epoch did not end")
        for batch in 0..<Self.measuredBatches {
            beginPhase("allocation_batch_\(batch)")
            var remaining=Self.operationsPerBatch
            for window in 0..<windowsPerBatch {
                let count=min(Self.nativeOutstandingLimit,remaining)
                let released=(0..<count).map { _ in WeakSlot() }
                try autoreleasepool {
                    var operations=[Operation]();operations.reserveCapacity(count)
                    for index in 0..<count { let operation=next();released[index].value=operation.task;try startTracked(operation);flushFeature();operations.append(operation) }
                    // Completion and completed-state rows require real metrics,
                    // but their companion setup/drain is outside the epoch.
                    if registered && (row == .completion || row == .state) {
                        for operation in operations { try invoke(.metrics,task:operation.task,metrics:metrics) }
                        flushFeature()
                    }
                    var epoch:UInt64=0
                    try demand(e01_allocation_epoch_begin(&epoch)==E01_ALLOCATION_OK,"allocation epoch did not begin")
                    for operation in operations {
                        try invoke(row,task:operation.task,metrics:metrics)
                    }
                    flushFeature()
                    let index=batch*windowsPerBatch+window
                    try demand(e01_allocation_epoch_end(epoch,&windows[index])==E01_ALLOCATION_OK,"allocation epoch did not end")
                    denominators[index]=count
                    for operation in operations { try finishTracked(operation) }
                    flushFeature();operations.removeAll(keepingCapacity:false)
                }
                try settle(released)
                remaining-=count
            }
        }
        let batches=(0..<Self.measuredBatches).map { batch -> [String:Any] in
            let start=batch*windowsPerBatch
            let end=start+windowsPerBatch
            return ["operations":Self.operationsPerBatch,"windows":Array(windows[start..<end]).map { self.counts($0) },"window_denominators":Array(denominators[start..<end])]
        }
        let lifecycle=try observedLifecycle(Self.measuredBatches * Self.operationsPerBatch)
        return ["row":row.rawValue,"instrumentation":"instrumented","workload":["discarded_warmup_operations":Self.timingWarmupOperations,"measured_batches":Self.measuredBatches,"operations_per_batch":Self.operationsPerBatch,"measured_operations":Self.measuredBatches*Self.operationsPerBatch,"outstanding_limit":Self.nativeOutstandingLimit],"warmup":["expected_operations":Self.timingWarmupOperations,"receipts":(lifecycle["phase_receipts"] as? [String:[String:Int]])?["warmup"] ?? [:],"counter":counts(discardedResult)],"allocation":["expected_operations":Self.measuredBatches*Self.operationsPerBatch,"receipts":aggregateReceipts(lifecycle,prefix:"allocation_batch_"),"batches":allocationBatches(batches,lifecycle)],"native_outstanding_observed_max":outstanding.observedMaximum()]
    }
    private func fullTaskAllocationRow() throws -> [String:Any] {
        resetObservedLifecycle()
        let windowsPerBatch=(Self.operationsPerBatch+Self.nativeOutstandingLimit-1)/Self.nativeOutstandingLimit
        var windows=[E01AllocationResult](repeating:E01AllocationResult(),count:Self.measuredBatches*windowsPerBatch)
        var denominators=[Int](repeating:0,count:Self.measuredBatches*windowsPerBatch)
        // Task/session construction is explicitly outside each epoch. Keeping
        // only a 64-task window prevents the fixture's own retained inputs from
        // growing with a 1,000-operation batch.
        func warmup() throws { try withHeldTask { _ in flushFeature() } }
        let installation=e01_allocation_install()
        try demand(installation.error==E01_ALLOCATION_OK && installation.lock_free==1,"all-thread allocation counter unavailable for full task row")
        defer { _=e01_allocation_uninstall() }
        // Required discarded warm-up is inside an active all-thread counter epoch.
        beginPhase("warmup")
        var discardedEpoch: UInt64 = 0
        try demand(e01_allocation_epoch_begin(&discardedEpoch)==E01_ALLOCATION_OK,"discarded warm-up epoch did not begin")
        for _ in 0..<Self.timingWarmupOperations { try warmup() }
        var discardedResult = E01AllocationResult()
        try demand(e01_allocation_epoch_end(discardedEpoch,&discardedResult)==E01_ALLOCATION_OK,"discarded warm-up epoch did not end")
        for batch in 0..<Self.measuredBatches {
            beginPhase("allocation_batch_\(batch)")
            var remaining=Self.operationsPerBatch
            for window in 0..<windowsPerBatch {
                let count=min(Self.nativeOutstandingLimit,remaining)
                let released=(0..<count).map { _ in WeakSlot() }
                try autoreleasepool {
                    var operations=[Operation]();operations.reserveCapacity(count)
                    for _ in 0..<count { operations.append(next()) }
                    var epoch:UInt64=0
                    try demand(e01_allocation_epoch_begin(&epoch)==E01_ALLOCATION_OK,"full task allocation epoch did not begin")
                    for index in 0..<count { let operation=operations[index];released[index].value=operation.task;try startTracked(operation);flushFeature();try finishTracked(operation);flushFeature() }
                    let index=batch*windowsPerBatch+window
                    try demand(e01_allocation_epoch_end(epoch,&windows[index])==E01_ALLOCATION_OK,"full task allocation epoch did not end")
                    denominators[index]=count
                }
                try settle(released);remaining-=count
            }
        }
        let batches=(0..<Self.measuredBatches).map { batch -> [String:Any] in
            let start=batch*windowsPerBatch,end=start+windowsPerBatch
            return ["tasks":Self.operationsPerBatch,"windows":Array(windows[start..<end]).map { self.counts($0) },"window_denominators":Array(denominators[start..<end])]
        }
        let lifecycle=try observedLifecycle(Self.measuredBatches * Self.operationsPerBatch)
        return ["row":"full_task_cycle","denominator":"successful_tasks","workload":["discarded_warmup_operations":Self.timingWarmupOperations,"measured_batches":Self.measuredBatches,"operations_per_batch":Self.operationsPerBatch,"measured_operations":Self.measuredBatches*Self.operationsPerBatch],"warmup":["expected_operations":Self.timingWarmupOperations,"receipts":(lifecycle["phase_receipts"] as? [String:[String:Int]])?["warmup"] ?? [:],"counter":counts(discardedResult)],"allocation":["expected_operations":Self.measuredBatches*Self.operationsPerBatch,"receipts":aggregateReceipts(lifecycle,prefix:"allocation_batch_"),"batches":allocationBatches(batches,lifecycle)],"budget_applies":true]
    }
    private func fullLifetimeChurnRow() throws -> [String:Any] {
        resetObservedLifecycle()
        let windowsPerBatch=(Self.operationsPerBatch+Self.nativeOutstandingLimit-1)/Self.nativeOutstandingLimit
        var windows=[E01AllocationResult](repeating:E01AllocationResult(),count:Self.measuredBatches*windowsPerBatch)
        var denominators=[Int](repeating:0,count:Self.measuredBatches*windowsPerBatch)
        func warmup() throws { try withHeldTask { _ in flushFeature() } }
        let installation=e01_allocation_install()
        try demand(installation.error==E01_ALLOCATION_OK && installation.lock_free==1,"all-thread allocation counter unavailable for lifetime churn")
        defer { _=e01_allocation_uninstall() }
        // Required discarded warm-up is inside an active all-thread counter epoch.
        beginPhase("warmup")
        var discardedEpoch: UInt64 = 0
        try demand(e01_allocation_epoch_begin(&discardedEpoch)==E01_ALLOCATION_OK,"discarded warm-up epoch did not begin")
        for _ in 0..<Self.timingWarmupOperations { try warmup() }
        var discardedResult = E01AllocationResult()
        try demand(e01_allocation_epoch_end(discardedEpoch,&discardedResult)==E01_ALLOCATION_OK,"discarded warm-up epoch did not end")
        for batch in 0..<Self.measuredBatches {
            beginPhase("allocation_batch_\(batch)")
            var remaining=Self.operationsPerBatch
            for window in 0..<windowsPerBatch {
                let count=min(Self.nativeOutstandingLimit,remaining)
                let released=(0..<count).map { _ in WeakSlot() }
                var epoch:UInt64=0
                try demand(e01_allocation_epoch_begin(&epoch)==E01_ALLOCATION_OK,"lifetime churn epoch did not begin")
                try autoreleasepool {
                    // Unlike the dispatcher row, construction is deliberately
                    // within this diagnostic's epoch.
                    for index in 0..<count {
                        let operation=next();released[index].value=operation.task
                        try startTracked(operation);flushFeature();try finishTracked(operation);flushFeature()
                    }
                }
                let index=batch*windowsPerBatch+window
                denominators[index]=count
                try settle(released)
                try demand(e01_allocation_epoch_end(epoch,&windows[index])==E01_ALLOCATION_OK,"lifetime churn epoch did not end")
                remaining-=count
            }
        }
        let batches=(0..<Self.measuredBatches).map { batch -> [String:Any] in
            let start=batch*windowsPerBatch,end=start+windowsPerBatch
            return ["tasks":Self.operationsPerBatch,"windows":Array(windows[start..<end]).map { self.counts($0) },"window_denominators":Array(denominators[start..<end])]
        }
        let lifecycle=try observedLifecycle(Self.measuredBatches * Self.operationsPerBatch)
        return ["row":"full_lifetime_churn_including_construction","diagnostic":true,"workload":["discarded_warmup_operations":Self.timingWarmupOperations,"measured_batches":Self.measuredBatches,"operations_per_batch":Self.operationsPerBatch,"measured_operations":Self.measuredBatches*Self.operationsPerBatch],"warmup":["expected_operations":Self.timingWarmupOperations,"receipts":(lifecycle["phase_receipts"] as? [String:[String:Int]])?["warmup"] ?? [:],"counter":counts(discardedResult)],"allocation":["expected_operations":Self.measuredBatches*Self.operationsPerBatch,"receipts":lifecycle["phase_receipts"] ?? [:],"batches":allocationBatches(batches,lifecycle)]]
    }
    private func idleAllocationRow() throws -> [String:Any] {
        let durationNs:UInt64=100_000_000
        var windows=[E01AllocationResult](repeating:E01AllocationResult(),count:Self.measuredBatches)
        let signal=DispatchSemaphore(value:0)
        func idle() { _=signal.wait(timeout: .now() + .nanoseconds(Int(durationNs))) }
        let installation=e01_allocation_install()
        try demand(installation.error==E01_ALLOCATION_OK && installation.lock_free==1,"all-thread allocation counter unavailable for idle row")
        defer { _=e01_allocation_uninstall() }
        beginPhase("warmup")
        var discardedEpoch: UInt64=0, discardedResult=E01AllocationResult()
        try demand(e01_allocation_epoch_begin(&discardedEpoch)==E01_ALLOCATION_OK,"idle discarded epoch did not begin")
        idle();try demand(e01_allocation_epoch_end(discardedEpoch,&discardedResult)==E01_ALLOCATION_OK,"idle discarded epoch did not end")
        for index in 0..<Self.measuredBatches {
            var epoch:UInt64=0
            try demand(e01_allocation_epoch_begin(&epoch)==E01_ALLOCATION_OK,"idle allocation epoch did not begin")
            idle()
            try demand(e01_allocation_epoch_end(epoch,&windows[index])==E01_ALLOCATION_OK,"idle allocation epoch did not end")
        }
        return ["row":"fixed_duration_idle_control","diagnostic":true,"warmup_windows":1,"measured_windows":Self.measuredBatches,"duration_ns":durationNs,"counter_active_discarded_warmup":counts(discardedResult),"batches":windows.map { self.counts($0) }]
    }
    private func resumeAllocationRow(_ name: String, secondResume: Bool) throws -> [String:Any] {
        resetObservedLifecycle()
        let windowsPerBatch=(Self.operationsPerBatch+Self.nativeOutstandingLimit-1)/Self.nativeOutstandingLimit
        var windows=[E01AllocationResult](repeating:E01AllocationResult(),count:Self.measuredBatches*windowsPerBatch)
        var denominators=[Int](repeating:0,count:Self.measuredBatches*windowsPerBatch)
        func warmup() throws {
            let released=WeakSlot()
            try autoreleasepool {
                let operation=next();released.value=operation.task
                if secondResume { try startTracked(operation);flushFeature() }
                markManualResume(operation, entersOutstanding: !secondResume); operation.task.resume()
                if !secondResume { try wait(operation.channel.started,"native URLProtocol start missing");try demandRunning(operation) }
                try finishTracked(operation);flushFeature()
            }
            try settle([released])
        }
        let installation=e01_allocation_install()
        try demand(installation.error==E01_ALLOCATION_OK && installation.lock_free==1,"all-thread allocation counter unavailable for resume row")
        defer { _=e01_allocation_uninstall() }
        // Required discarded warm-up is inside an active all-thread counter epoch.
        beginPhase("warmup")
        var discardedEpoch: UInt64 = 0
        try demand(e01_allocation_epoch_begin(&discardedEpoch)==E01_ALLOCATION_OK,"discarded warm-up epoch did not begin")
        for _ in 0..<Self.timingWarmupOperations { try warmup() }
        var discardedResult = E01AllocationResult()
        try demand(e01_allocation_epoch_end(discardedEpoch,&discardedResult)==E01_ALLOCATION_OK,"discarded warm-up epoch did not end")
        for batch in 0..<Self.measuredBatches {
            beginPhase("allocation_batch_\(batch)")
            var remaining=Self.operationsPerBatch
            for window in 0..<windowsPerBatch {
                let count=min(Self.nativeOutstandingLimit,remaining)
                let released=(0..<count).map { _ in WeakSlot() }
                try autoreleasepool {
                    var operations=[Operation]();operations.reserveCapacity(count)
                    for index in 0..<count {
                        let operation=next()
                        released[index].value=operation.task
                        if secondResume { try startTracked(operation);flushFeature() }
                        operations.append(operation)
                    }
                    var epoch:UInt64=0
                    try demand(e01_allocation_epoch_begin(&epoch)==E01_ALLOCATION_OK,"resume allocation epoch did not begin")
                    for operation in operations { markManualResume(operation, entersOutstanding: !secondResume); operation.task.resume() }
                    // The first native start can enqueue a state observation after
                    // resume returns. Include the held-start receipt before the
                    // final feature drain and epoch close; this scope includes
                    // process startup allocations and is labeled as such below.
                    if !secondResume { for operation in operations { try wait(operation.channel.started,"native URLProtocol start missing");try demandRunning(operation) } }
                    flushFeature()
                    let index=batch*windowsPerBatch+window
                    try demand(e01_allocation_epoch_end(epoch,&windows[index])==E01_ALLOCATION_OK,"resume allocation epoch did not end")
                    denominators[index]=count
                    for operation in operations { try finishTracked(operation) }
                    flushFeature();operations.removeAll(keepingCapacity:false)
                }
                try settle(released)
                remaining-=count
            }
        }
        let batches=(0..<Self.measuredBatches).map { batch -> [String:Any] in
            let start=batch*windowsPerBatch,end=start+windowsPerBatch
            return ["operations":Self.operationsPerBatch,"windows":Array(windows[start..<end]).map { self.counts($0) },"window_denominators":Array(denominators[start..<end])]
        }
        let lifecycle=try observedLifecycle(Self.measuredBatches * Self.operationsPerBatch)
        return ["row":name,"instrumentation":unbound ? "sdk_unbound":"instrumented","resume_ordinal":secondResume ? 2:1,"allocation_scope":secondResume ? "second_resume_through_feature_flush":"first_resume_through_held_start_and_final_feature_flush_includes_process_startup","workload":["discarded_warmup_operations":Self.timingWarmupOperations,"measured_batches":Self.measuredBatches,"operations_per_batch":Self.operationsPerBatch,"measured_operations":Self.measuredBatches*Self.operationsPerBatch,"outstanding_limit":Self.nativeOutstandingLimit],"warmup":["expected_operations":Self.timingWarmupOperations,"receipts":(lifecycle["phase_receipts"] as? [String:[String:Int]])?["warmup"] ?? [:],"counter":counts(discardedResult)],"allocation":["expected_operations":Self.measuredBatches*Self.operationsPerBatch,"receipts":aggregateReceipts(lifecycle,prefix:"allocation_batch_"),"batches":allocationBatches(batches,lifecycle)],"native_outstanding_observed_max":outstanding.observedMaximum()]
    }
    private func fullUnboundFirstResumeRow(mode: String) throws {
        unbound = true
        defer { unbound = false }
        let row: [String: Any]
        if mode == "e01-timing" { row = try resumeTimingRow("unbound_first_resume",secondResume:false) }
        else { row = try resumeAllocationRow("unbound_first_resume",secondResume:false) }
        var output=row;output["before_binding"]=true;output["prepared_header"]="absent";output["sdk_receiver_expected_zero"]=true;output["ordering"]="unbound_before_bind_before_bound_rows";modeData["unbound_first_resume"]=output
    }
    private func entryTimingRows() throws {
        var resume=[[String:Any]]();let seed=try metricsSeed();var timing=[[String:Any]]()
        var rows:[String:Any]=["unbound_first_resume":modeData["unbound_first_resume"] as Any];modeData["timing_progress"]=["rows":rows]
        let first=try resumeTimingRow("first_resume",secondResume:false);resume.append(first);rows["first_resume"]=first;modeData["timing_progress"]=["rows":rows]
        let second=try resumeTimingRow("second_resume_ready",secondResume:true);resume.append(second);rows["second_resume_ready"]=second;modeData["timing_progress"]=["rows":rows]
        for callbackRow in CallbackRow.allCases { let row=try timingRow(callbackRow,metrics:seed);timing.append(row);if let name=row["row"] as? String { rows[name]=row;modeData["timing_progress"]=["rows":rows] } }
        modeData["timing"]=["rows":rows,"raw_resume_timing":resume,"raw_callback_rows":timing]
    }
    private func entryAllocationRows() throws {
        var allocations=[[String:Any]]();let seed=try metricsSeed();var rows:[String:Any]=["unbound_first_resume":modeData["unbound_first_resume"] as Any];modeData["allocation_progress"]=["rows":rows]
        let acceptanceNames=Set(["unbound_first_resume","first_resume","second_resume_ready","data","metrics","completion","state","full_task_cycle"])
        let first=try resumeAllocationRow("first_resume",secondResume:false);allocations.append(first);rows["first_resume"]=first;modeData["allocation_progress"]=["rows":rows]
        let second=try resumeAllocationRow("second_resume_ready",secondResume:true);allocations.append(second);rows["second_resume_ready"]=second;modeData["allocation_progress"]=["rows":rows]
        for callbackRow in CallbackRow.allCases { let row=try allocationRow(callbackRow,metrics:seed);allocations.append(row);if let name=row["row"] as? String,acceptanceNames.contains(name) { rows[name]=row;modeData["allocation_progress"]=["rows":rows] } }
        let fullTask=try fullTaskAllocationRow();allocations.append(fullTask);rows["full_task_cycle"]=fullTask;modeData["allocation_progress"]=["rows":rows]
        let lifetime=try fullLifetimeChurnRow();modeData["full_lifetime_churn"]=lifetime
        let idle=try idleAllocationRow();modeData["idle_control"]=idle
        modeData["allocation"]=["rows":rows,"raw_rows":allocations,"diagnostics":["full_lifetime_churn":lifetime,"idle_control":idle],"callback_rows":"included"]
    }
    private func settle(_ slots:[WeakSlot]) throws {
        let deadline=DispatchTime.now().uptimeNanoseconds+5_000_000_000
        while true {
            autoreleasepool {flushFeature()}
            let released=autoreleasepool { () -> Bool in for slot in slots { if slot.value != nil {return false} };return true }
            if released{return}
            try demand(DispatchTime.now().uptimeNanoseconds<deadline,"native weak objects did not settle within5seconds")
            Thread.sleep(forTimeInterval:0.001)
        }
    }
    private func inventory() throws -> Inventory {
        guard let feature else { throw FixtureFailure(reason:"feature reflection unavailable") }
        let fields=Array(Mirror(reflecting:feature).children)
        guard let interceptions=fields.first(where:{$0.label=="interceptions"}),
              let truncated=fields.first(where:{$0.label=="truncatedInterceptions"}) else { throw FixtureFailure(reason:"required owning-state reflection missing") }
        var answer=Inventory(reflectionAvailable:true)
        let interceptionsMirror=Mirror(reflecting:interceptions.value), truncatedMirror=Mirror(reflecting:truncated.value)
        try demand(interceptionsMirror.displayStyle == .dictionary && truncatedMirror.displayStyle == .set,"owning collection shape changed")
        answer.interceptions=interceptionsMirror.children.count
        answer.truncated=truncatedMirror.children.count
        let preparationLockField=fields.first(where:{$0.label=="preparationLock"}), preparationField=fields.first(where:{$0.label=="preparations"}), terminalField=fields.first(where:{$0.label=="terminalTasks"})
        if arm == "A" {
            try demand(preparationLockField == nil && preparationField == nil && terminalField == nil,"baseline unexpectedly exposed candidate ownership collections")
            return answer
        }
        guard let lock=preparationLockField?.value as? NSLock,
              let table=preparationField?.value as? NSMapTable<AnyObject,AnyObject> else { throw FixtureFailure(reason:"candidate preparation map reflection missing") }
        lock.lock(); defer { lock.unlock() }
        answer.raw=table.count
        let keys=table.keyEnumerator().allObjects;answer.keys=keys.count
        for key in keys {if let task=key as? URLSessionTask {answer.lastSequence=max(answer.lastSequence,Int(task.originalRequest?.url?.lastPathComponent.replacingOccurrences(of:"task-",with:"") ?? "0") ?? 0)}}
        let values=table.objectEnumerator()?.allObjects ?? [];answer.values=values.count
        for value in values {
            let fields=Mirror(reflecting:value).children
            guard let phase=fields.first(where:{$0.label=="phase"}) else { throw FixtureFailure(reason:"preparation phase reflection missing") }
            let phaseValue=String(describing:phase.value);try demand(phaseValue == "preparing" || phaseValue == "ready","unexpected candidate preparation phase")
            answer.phases.append(phaseValue)
            guard let events=fields.first(where:{$0.label=="events"}),let continuations=fields.first(where:{$0.label=="continuations"}) else { throw FixtureFailure(reason:"preparation payload reflection missing") }
            try demand(Mirror(reflecting:events.value).displayStyle == .collection && Mirror(reflecting:continuations.value).displayStyle == .collection,"preparation payload shape changed")
            answer.events += Mirror(reflecting:events.value).children.count
            answer.continuations += Mirror(reflecting:continuations.value).children.count
        }
        if arm == "B" {
            guard let terminals=terminalField?.value as? NSHashTable<AnyObject> else { throw FixtureFailure(reason:"candidate terminalTasks reflection missing") }
            answer.terminalRaw=terminals.count; answer.terminalLive=terminals.allObjects.count
        }
        return answer
    }
    private func retention() throws {
        // Reuse already allocated weak slots and demand release before reuse, so
        // observation storage does not expand along with the task count.
        let task=WeakSlot(), interception=WeakSlot();let slots=[task,interception]
        var heaps=[UInt64](repeating:0,count:3), snapshots=[Inventory](repeating:Inventory(),count:3)
        var verifiedCycles=0, boundary=0, interceptionLivenessVerifiedCycles=0
        let cohortBefore=receiverSnapshot()
        receiver!.interceptionSlot=interception
        for i in 0..<220 {
            try autoreleasepool {
                let op=next();task.value=op.task;try startTracked(op);flushFeature();try demand(interception.value != nil,"retention interception was not live while task was held");interceptionLivenessVerifiedCycles += 1;try finishTracked(op);flushFeature()
            }
            try settle(slots);verifiedCycles+=1
            if i==19 || i==119 || i==219 {
                heaps[boundary]=e01_live_heap_bytes()
                snapshots[boundary]=try autoreleasepool {try featureQueue().sync{try autoreleasepool {try inventory()}}}
                boundary+=1
            }
        }
        let cohortAfter=receiverSnapshot()
        let receiverDelta=["mutations":(cohortAfter?.mutations ?? 0)-(cohortBefore?.mutations ?? 0),"starts":(cohortAfter?.starts ?? 0)-(cohortBefore?.starts ?? 0),"completions":(cohortAfter?.completions ?? 0)-(cohortBefore?.completions ?? 0)]
        try demand(receiverDelta["mutations"]==220 && receiverDelta["starts"]==220 && receiverDelta["completions"]==220,"retention cohort receiver lifecycle was not exactly 220/220/220")
        try demand(interceptionLivenessVerifiedCycles==220,"retention interception liveness was incomplete")
        receiver!.interceptionSlot=nil
        let encoded=snapshots.enumerated().map { index, x -> [String:Any] in
            var value:[String:Any] = ["boundary":[20,120,220][index],"interceptions":x.interceptions,"truncatedInterceptions":x.truncated,"task_weak_members":0,"interception_weak_members":0,"reflection_available":x.reflectionAvailable]
            if arm == "B" {
                value["preparations"] = ["raw_count_before_enumeration":x.raw,"live_weak_keys":x.keys,"remaining_values":x.values,"phase_payloads":x.events,"events":x.events,"continuations":x.continuations,"remaining_key_sequence":x.lastSequence,"phases":x.phases];value["weak_terminal_tasks"] = ["raw_count_before_enumeration":x.terminalRaw,"live_members":x.terminalLive]
            }
            return value
        }
        let first=Int64(heaps[1])-Int64(heaps[0]),second=Int64(heaps[2])-Int64(heaps[1])
        // Weak-table raw slots are diagnostic allocator/capacity evidence only.
        // Live weak members and task-owned records are the ownership invariant.
        let recordsEmpty=snapshots.allSatisfy{$0.interceptions==0 && $0.truncated==0 && $0.keys==0 && $0.values==0 && $0.events==0 && $0.continuations==0 && $0.terminalLive==0}
        modeData["retention"]=["fresh_cohort":true,"heap_bytes":heaps,"first_100_growth":first,"second_100_growth":second,"remaining_tasks":task.value == nil ? 0:1,"remaining_interceptions":interception.value == nil ? 0:1,"verified_cycles":verifiedCycles,"receiver_delta":receiverDelta,"interception_liveness_verified_cycles":interceptionLivenessVerifiedCycles,"inventories":encoded,"numeric_budget_pass":first<=65536 && second<=16384,"records_empty":recordsEmpty]
        try demand(recordsEmpty,"task records remained at settled boundaries")
    }
    private func preparationOwnership() throws {
        let task=WeakSlot()
        var captured=false, terminal=false, emptyPayloads=false, preparationMapAvailable=false, terminalTasksAvailable=false
        try autoreleasepool {
            let op=next();task.value=op.task;try startTracked(op);flushFeature();try finishTracked(op);flushFeature()
            try demand(op.task.state == .completed,"native task state not completed before terminal witness")
            let fields=Mirror(reflecting:feature!).children
            terminalTasksAvailable=fields.contains(where:{$0.label=="terminalTasks"})
            if let lock=fields.first(where:{$0.label=="preparationLock"})?.value as? NSLock,
               let table=fields.first(where:{$0.label=="preparations"})?.value as? NSMapTable<AnyObject,AnyObject> {
                preparationMapAvailable=true
                lock.lock()
                if let value=table.object(forKey:op.task) {
                    terminalPreparation.value=value;captured=true
                    let state=Mirror(reflecting:value).children
                    terminal=state.contains(where:{$0.label=="phase" && (String(describing:$0.value)=="preparing" || String(describing:$0.value)=="ready")})
                    emptyPayloads=state.filter({$0.label=="events" || $0.label=="continuations"}).allSatisfy{Mirror(reflecting:$0.value).children.isEmpty}
                }
                lock.unlock()
            }
        }
        try settle([task])
        // EXP-199 removes terminal values from preparations and uses weak task
        // tombstones.  Both shapes are observations, not a fixture failure.
        let alive=autoreleasepool{terminalPreparation.value != nil}
        modeData["terminal_preparation_ownership"]=["preparation_map_available":preparationMapAvailable,"weak_terminal_tasks_available":terminalTasksAvailable,"captured_final_terminal_legacy":captured,"legacy_payloads_empty":emptyPayloads,"legacy_terminal_phase":terminal,"task_released":task.value == nil,"legacy_preparation_alive_after_task_release":alive]
    }
    private func ownershipNegativeControl() throws {
        let witness=WeakSlot()
        var deliberatelyRetained:URLSessionTask?
        try autoreleasepool {
            let op=next();witness.value=op.task
            try startTracked(op);flushFeature();try finishTracked(op);flushFeature()
            deliberatelyRetained=op.task
        }
        let holdDetected=witness.value != nil
        deliberatelyRetained=nil
        try settle([witness])
        modeData["ownership_negative_control"]=["deliberate_strong_task_hold_detected":holdDetected,"release_after_control":witness.value == nil,"terminal_payload_control":"candidate_has_no_terminal_preparation_value; owned-record inventory remains the control"]
        try demand(holdDetected,"negative strong task hold was not observable")
    }
    private func completedTaskControl() throws -> [String:Any] {
        guard feature != nil else { throw FixtureFailure(reason:"completed-task control feature unavailable") }
        beginPhase("completed_control")
        let witness=WeakSlot()
        let control:[String:Any] = try autoreleasepool {
            let op=next();witness.value=op.task
            let before=receiverSnapshot();try startTracked(op);flushFeature();try finishTracked(op);flushFeature()
            try demand(op.task.state == .completed,"native task was not completed before repeated resume")
            let completed=receiverSnapshot()
            let beforeInvalidation=op.channel.snapshot()
            let repeatBefore=completed
            op.task.resume();flushFeature()
            let repeated=receiverSnapshot();let after=op.channel.snapshot()
            let preDelta:[String:Int] = ["mutations":(completed?.mutations ?? 0)-(before?.mutations ?? 0),"starts":(completed?.starts ?? 0)-(before?.starts ?? 0),"completions":(completed?.completions ?? 0)-(before?.completions ?? 0)]
            let postDelta:[String:Int] = ["mutations":(repeated?.mutations ?? 0)-(repeatBefore?.mutations ?? 0),"starts":(repeated?.starts ?? 0)-(repeatBefore?.starts ?? 0),"completions":(repeated?.completions ?? 0)-(repeatBefore?.completions ?? 0)]
            let expectedA=arm == "A";let valid=expectedA ? (postDelta["mutations"] == 1 && postDelta["starts"] == 1 && postDelta["completions"] == 0) : postDelta.values.allSatisfy { $0 == 0 }
            try demand(valid,"completed-task repeat classification mismatch")
            try demand(beforeInvalidation.protocolStarts==1 && beforeInvalidation.protocolCompletions==1 && beforeInvalidation.completionCalls==1 && beforeInvalidation.invalidations==1 && beforeInvalidation.errors==0,"completed-task native receipts were not exactly once before repeat")
            try demand(after.protocolStarts==1 && after.protocolCompletions==1 && after.completionCalls==1 && after.invalidations==1 && after.errors==0,"completed-task native receipts changed after repeat")
            let dedicatedRelease=try releaseFeature()
            return ["isolated_feature":true,"completed_before_repeat":true,"repeat_resume_attempted":true,"native_receipts_before":["protocol_starts":beforeInvalidation.protocolStarts,"protocol_completions":beforeInvalidation.protocolCompletions,"native_completions":beforeInvalidation.completionCalls,"invalidations":beforeInvalidation.invalidations,"errors":beforeInvalidation.errors],"native_receipts_after":["protocol_starts":after.protocolStarts,"protocol_completions":after.protocolCompletions,"native_completions":after.completionCalls,"invalidations":after.invalidations,"errors":after.errors],"pre_completion_receiver_delta":preDelta,"post_completion_receiver_delta":postDelta,"classification":expectedA ? "EXPECTED_BASELINE_NEGATIVE":"CANDIDATE_PASS","numeric_credit":false,"dedicated_feature_release":dedicatedRelease]
        }
        try settle([witness])
        var output=control;output["task_released"]=witness.value == nil
        try demand(witness.value == nil,"completed-task control task remained retained")
        return output
    }
    private func postTeardownNativeForwarding() throws -> [String:Any] {
        let witness=WeakSlot()
        let receipt:[String:Any] = try autoreleasepool {
            let op=next();witness.value=op.task
            try startTracked(op);try finishTracked(op)
            let channel=op.channel.snapshot()
            return ["native_completions":channel.completionCalls,"native_body_bytes":channel.bodyBytes,"native_invalidation":channel.invalidations]
        }
        try settle([witness])
        let forwarded=(receipt["native_completions"] as? Int)==1 && (receipt["native_body_bytes"] as? Int)==LocalProtocol.bodyBytes && (receipt["native_invalidation"] as? Int)==1
        try demand(forwarded,"post-teardown unrelated native task did not forward once")
        return receipt
    }
    private func captureResumeIMP() throws -> [String: Any] {
        let witness=WeakSlot()
        let output:[String:Any] = try autoreleasepool {
            let operation=next();witness.value=operation.task
            let taskClass: AnyClass = type(of:operation.task);let selector=#selector(URLSessionTask.resume);let imp=class_getMethodImplementation(taskClass,selector);let pointer=unsafeBitCast(imp,to:UInt.self)
            try demand(pointer != 0,"resume IMP capture failed")
            try operation.start();try operation.finish()
            return ["task_class":NSStringFromClass(taskClass),"selector":NSStringFromSelector(selector),"imp":"0x"+String(pointer,radix:16)]
        }
        try settle([witness]);try demand(witness.value == nil,"IMP probe task did not settle");return output
    }
    private func releaseFeature() throws -> [String: Any] {
        weak var weakFeature=feature; weak var weakProvider=provider; weak var weakReceiver=receiver
        let featureAlive=weakFeature != nil, providerAlive=weakProvider != nil, handlerAlive=weakReceiver != nil
        try demand(featureAlive && providerAlive && handlerAlive,"release witnesses were vacuous")
        flushFeature(); feature=nil; receiver=nil; provider=nil
        let released=weakFeature==nil && weakProvider==nil && weakReceiver==nil
        try demand(released,"feature/provider/handler retained")
        return ["feature_alive_before_release":featureAlive,"provider_alive_before_release":providerAlive,"handler_alive_before_release":handlerAlive,"feature_released":weakFeature==nil,"provider_released":weakProvider==nil,"handler_released":weakReceiver==nil,"terminal_preparation_released":terminalPreparation.value==nil]
    }
    private func coordinatorPayloadContinuationControl() throws {
        guard arm == "B" else { modeData["payload_continuation_control"]=["applicability":"unsupported_on_A"]; return }
        guard let receiver, let feature else { throw FixtureFailure(reason:"candidate coordinator control unavailable") }
        let entered=DispatchSemaphore(value:0), release=DispatchSemaphore(value:0), started=DispatchSemaphore(value:0)
        let op=next(); let task=op.task
        receiver.onModify = {
            feature.task(task,didReceive:LocalProtocol.chunk)
            task.resume()
            entered.signal()
            _=release.wait(timeout:.now()+5)
        }
        DispatchQueue.global(qos:.userInitiated).async { [self] in
            do { try startTracked(op); started.signal() } catch { started.signal() }
        }
        try wait(entered,"candidate preparation gate was not entered")
        let held=try inventory()
        try demand(held.events > 0 && held.continuations > 0,"candidate preparation did not retain both actual payload and continuation")
        release.signal();try wait(started,"candidate preparation did not resume native start")
        try finishTracked(op);flushFeature();receiver.onModify=nil
        let drained=try inventory()
        try demand(drained.events==0 && drained.continuations==0,"candidate preparation payload or continuation remained after drain")
        modeData["payload_continuation_control"]=["applicability":"candidate_B","actual_data":true,"duplicate_resume":true,"nonzero_while_blocked":held.events > 0 || held.continuations > 0,"zero_after_drain":drained.events == 0 && drained.continuations == 0,"held_events":held.events,"held_continuations":held.continuations,"drained_events":drained.events,"drained_continuations":drained.continuations]
    }
    private func featureAndTaskHoldControls() throws {
        let taskWitness=WeakSlot(); var taskBox: URLSessionTask?
        try autoreleasepool { let op=next();taskWitness.value=op.task;try startTracked(op);flushFeature();try finishTracked(op);flushFeature();taskBox=op.task }
        try withExtendedLifetime(taskBox) { try demand(taskWitness.value != nil,"task hold negative was not observed") }
        taskBox=nil;try settle([taskWitness])
        weak var featureWitness=feature; var featureBox=feature
        feature=nil;receiver=nil;provider=nil
        try withExtendedLifetime(featureBox) { try demand(featureWitness != nil,"feature hold negative was not observed") }
        featureBox=nil;try demand(featureWitness==nil,"feature did not release after hold control")
        modeData["task_hold"]=["held":true,"released":taskWitness.value==nil]
        modeData["feature_hold"]=["held":true,"released":featureWitness==nil]
    }
    private func budgetNegativeControls() {
        modeData["evaluator_negative_controls"]=["first_100_growth":65537,"second_100_growth":16385,"expected":"evaluator_rejects","caller_only_counter_negative":"reused_calibrated_counter_control"]
    }
    func run() {
        let args=ProcessInfo.processInfo.arguments
        func arg(_ name:String)->String? {guard let i=args.firstIndex(of:name),i+1<args.count else{return nil};return args[i+1]}
        registered=arg("--tracking")=="registered"; arm=arg("--arm") ?? "missing"; LocalProtocol.bodyBytes=args.contains("--zero-body") ? 0:1024;let mode=arg("--mode") ?? "qualify"
        modeData=[:]
        result=["schema_version":5,"status":"INCONCLUSIVE","identity":["run_id":arg("--run-id") ?? "missing","nonce":arg("--nonce") ?? "missing","arm":arm,"tracking":registered ? "registered":"automatic","mode":mode,"os":UIDevice.current.systemVersion,"source_revision":arg("--source-revision") ?? "missing","source_sha256":arg("--source-fingerprint") ?? "missing","fixture_sha256":arg("--fixture-fingerprint") ?? "missing","build_sha256":arg("--build-fingerprint") ?? "missing","contract_sha256":arg("--contract-fingerprint") ?? "missing"]]
        do {
            constructFeature()
            let impBefore=try captureResumeIMP()
            if mode=="e01-alloc-retention" { try calibrate() }
            if mode=="e01-timing" || mode=="e01-alloc-retention" { try fullUnboundFirstResumeRow(mode:mode) }
            try bind()
            result["native_roundtrip"]=try autoreleasepool{try roundtrip()};try settle([warmTask])
            if mode=="qualify" {
                try preparationOwnership(); try coordinatorPayloadContinuationControl(); budgetNegativeControls(); try featureAndTaskHoldControls();constructFeature();try bind();result["completed_task_control"]=try completedTaskControl();constructFeature();try bind();result["final_release"]=try releaseFeature()
            } else if mode=="e01-timing" { try entryTimingRows() }
            else if mode=="e01-alloc-retention" {
                try entryAllocationRows()
                // Numeric cohort starts with a new feature and fresh fixture ownership state.
                modeData["entry_feature_release"]=try releaseFeature();constructFeature();try bind();try retention();try releaseFeature();constructFeature();try bind();result["completed_task_control"]=try completedTaskControl();constructFeature();try bind();result["final_release"]=try releaseFeature()
            }
            if mode=="e01-timing" { try releaseFeature();constructFeature();try bind();result["completed_task_control"]=try completedTaskControl();constructFeature();try bind();result["final_release"]=try releaseFeature() }
            let impAfter=try captureResumeIMP()
            let impEqual=(impBefore["imp"] as? String)==(impAfter["imp"] as? String) && (impBefore["task_class"] as? String)==(impAfter["task_class"] as? String)
            try demand(impEqual,"resume IMP did not restore after final release")
            result["teardown"] = ["class":impBefore["task_class"] as Any,"selector":impBefore["selector"] as Any,"imp_before":impBefore["imp"] as Any,"imp_after":impAfter["imp"] as Any,"equal":impEqual,"native_receipt":try postTeardownNativeForwarding()]
            let finalModeData: [String: Any]
            if mode == "qualify" {
                var qualification = modeData
                qualification["controls"] = ["task_hold":modeData["task_hold"] ?? [:],"feature_hold":modeData["feature_hold"] ?? [:],"payload_continuation":modeData["payload_continuation_control"] ?? [:]]
                qualification.removeValue(forKey:"task_hold");qualification.removeValue(forKey:"feature_hold");qualification.removeValue(forKey:"payload_continuation_control")
                finalModeData = ["qualification": qualification]
            } else if mode == "e01-timing" {
                finalModeData = ["timing": modeData["timing"] ?? [:]]
            } else {
                var allocation = modeData["allocation"] as? [String: Any] ?? [:]
                for (key, value) in modeData where key != "allocation" && key != "unbound_first_resume" && key != "allocation_progress" {
                    allocation[key] = value
                }
                finalModeData = ["allocation": allocation]
            }
            result["mode_data"]=finalModeData;result["status"]="LOCAL_COMPLETE"
        } catch {result["status"]="INCONCLUSIVE";result["failure"]=(error as? FixtureFailure)?.reason ?? String(describing:type(of:error));result["partial_mode_data"]=modeData;result["partial_result_preserved"]=true}
        let path=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.json")
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:path,options:.atomic)}
    }

}
