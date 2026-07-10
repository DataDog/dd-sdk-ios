/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_AGGREGATION_WORKER_H_
#define DD_PROFILER_AGGREGATION_WORKER_H_

#include "dd_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <pthread.h>
#include <variant>
#include <vector>

namespace dd::profiler {

/**
 * @brief Serialized worker that drains sampled stack-trace batches in-order.
 *
 * The aggregation worker owns the aggregation thread and flush barriers used
 * to decouple sample capture from heavy callback work while preserving ordered
 * profile boundaries.
 *
 * ## Flush Ordering
 * Flush requests are first stored in `requested_flushes`. The producer moves
 * them into `pending_work` only at a safe point, after handing off the active
 * sampling buffer. This places each flush barrier after the in-progress batch
 * in the worker's ordered stream, so the flush action observes a complete
 * sample boundary.
 */
class aggregation_worker {
public:
    using flush_action_t = std::function<void()>;

    aggregation_worker(
        size_t initial_buffer_size,
        uint32_t max_stack_depth,
        stack_trace_callback_t callback,
        void* ctx,
        uint64_t hard_limit_bytes,
        qos_class_t worker_qos = QOS_CLASS_UTILITY);

    ~aggregation_worker();

    aggregation_worker(const aggregation_worker&) = delete;
    aggregation_worker& operator=(const aggregation_worker&) = delete;

    /**
     * @brief Starts the aggregation thread.
     *
     * Resets queued work, diagnostics and lifecycle state before creating a new
     * worker thread. Returns false if the worker is already running or if the
     * thread cannot be created.
     */
    bool start();

    /**
     * @brief Stops the aggregation thread.
     *
     * Marks the producer as finished, wakes the worker, waits for queued work to
     * drain, then joins the worker thread and resets its state.
     *
     * Must be called from a non-worker thread because the stop path joins the
     * worker thread. Profiler-owned callback paths should request an
     * asynchronous stop at the profiler lifecycle layer instead.
     */
    void stop();

    /**
     * @brief Blocks until all queued work before this request has been processed.
     *
     * If provided, `action` runs on the aggregation worker after all earlier
     * work has completed and before later batches are processed.
     *
     * @return true when the flush barrier was processed by the worker.
     */
    bool request_flush(flush_action_t action = {});

    /**
     * @brief Hands off the active sampling buffer without blocking the sampler.
     *
     * Moves the buffer contents into the worker queue and leaves
     * `active_buffer` empty for continued sampling. If queuing the batch would
     * exceed the configured memory limit, the batch is dropped and recorded in
     * diagnostics.
     */
    void enqueue_active_buffer(std::vector<stack_trace_t>& active_buffer);

    /**
     * @brief Completes a pending flush request from a producer safe point.
     */
    void service_pending_flush_request(std::vector<stack_trace_t>& active_buffer);

    /**
     * @brief Flushes the final producer buffer and marks that no more batches will arrive.
     */
    void finish_producer(std::vector<stack_trace_t>& active_buffer);

    /**
     * @brief Returns true when called from the worker thread itself.
     */
    bool is_worker_thread();

    /**
     * @brief Returns true when the given Mach thread belongs to this processor.
     */
    bool is_worker_thread(thread_t thread);

    /**
     * @brief Returns and resets diagnostics accumulated since the last consume.
     */
    void consume_diagnostics(dd_profiler_diagnostics_t& out);

private:
    struct configuration {
        size_t initial_buffer_size;
        uint32_t max_stack_depth;
        qos_class_t worker_qos;
        stack_trace_callback_t callback;
        void* ctx;
        uint64_t hard_limit_bytes;
    };

    struct batch_item {
        std::vector<stack_trace_t> traces;
        uint64_t footprint_bytes = 0;
    };

    struct flush_barrier {
        uint64_t flush_id = 0;
        flush_action_t action;
    };

    using work_item = std::variant<batch_item, flush_barrier>;

    const configuration config;

    pthread_t worker_thread{};
    bool has_worker_thread = false;
    /// Cached Mach thread id for hot-path internal-thread filtering.
    std::atomic<thread_t> worker_mach_thread{MACH_PORT_NULL};

    /// Ordered stream consumed by the worker thread.
    std::deque<work_item> pending_work;
    /// Flush barriers requested by external callers and awaiting a producer safe point.
    std::deque<flush_barrier> requested_flushes;

    /// Protects queued work, flush progress, worker lifecycle flags and diagnostics counters.
    std::mutex work_mutex;
    /// Wakes the aggregation thread when new batches or flush barriers are queued.
    std::condition_variable work_cv;
    /// Wakes flush callers when their requested flush barrier has been completed.
    std::condition_variable flush_cv;
    uint64_t next_flush_id = 0;
    uint64_t completed_flush_id = 0;
    uint64_t pending_bytes = 0;
    dd_profiler_diagnostics_t diagnostics{};
    /// Set once the producer has handed off its final buffer.
    bool producer_finished = true;
    /// Set once the worker has drained all queued work and exited.
    bool worker_finished = true;

    static constexpr size_t sampled_thread_name_capacity = 64;

    static void* worker_thread_entry(void* arg);
    void worker_main();
    void complete_batch(uint64_t footprint_bytes);
    static void free_batch_payloads(std::vector<stack_trace_t>& batch);
    void clear_pending_work_locked();
    uint64_t batch_footprint_bytes(const std::vector<stack_trace_t>& batch) const;
};

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH
#endif // DD_PROFILER_AGGREGATION_WORKER_H_
