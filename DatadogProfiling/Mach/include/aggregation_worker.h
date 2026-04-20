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
#include <mutex>
#include <pthread.h>
#include <vector>

namespace dd::profiler {

/**
 * @brief Serialized worker that drains sampled stack-trace batches in-order.
 *
 * The aggregation worker owns the aggregation thread, flush barriers, and a
 * small reusable buffer pool used to decouple sample capture from heavy
 * callback work. Under bursty load it can temporarily accept additional
 * overflow buffers, then shrink back to the reusable pool as the worker
 * catches up.
 */
class aggregation_worker {
public:
    using flush_action_t = void (*)(void* ctx);

    aggregation_worker(
        size_t buffer_capacity,
        uint32_t max_stack_depth,
        stack_trace_callback_t callback,
        void* ctx,
        uint64_t hard_limit_bytes,
        qos_class_t worker_qos = QOS_CLASS_UTILITY);

    ~aggregation_worker();

    aggregation_worker(const aggregation_worker&) = delete;
    aggregation_worker& operator=(const aggregation_worker&) = delete;

    bool start();
    void stop();

    /**
     * @brief Blocks until all queued work before this request has been processed.
     *
     * If provided, `action` runs on the aggregation worker after all earlier
     * work has completed and before later batches are processed.
     */
    void request_flush(flush_action_t action = nullptr, void* action_ctx = nullptr);

    /**
     * @brief Hands off the active sampling buffer without blocking the sampler.
     *
     * When no reusable buffer is immediately available, the sampler rotates
     * into a temporary overflow buffer instead of waiting or dropping work.
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
    void consume_diagnostics(dd_profiler_diagnostics_t* out);

private:
    struct work_item {
        enum class kind {
            batch,
            flush_barrier
        };

        kind item_kind;
        std::vector<stack_trace_t> traces;
        uint64_t flush_id = 0;
        flush_action_t action = nullptr;
        void* action_ctx = nullptr;
        uint64_t footprint_bytes = 0;
    };

    size_t buffer_capacity;
    uint32_t max_stack_depth;
    qos_class_t worker_qos;
    stack_trace_callback_t callback;
    void* ctx;
    uint64_t hard_limit_bytes;

    pthread_t worker_thread{};
    bool worker_thread_started = false;
    /// Cached Mach thread id for hot-path internal-thread filtering.
    std::atomic<thread_t> worker_mach_thread{MACH_PORT_NULL};

    /// Ordered stream consumed by the worker thread.
    std::deque<work_item> pending_work;
    /// Flush barriers requested by external callers and awaiting a producer safe point.
    std::deque<work_item> requested_flushes;
    /// Recycled buffers retained for future producer handoff.
    std::vector<std::vector<stack_trace_t>> reusable_buffers;

    std::mutex work_mutex;
    /// Wakes the aggregation thread when new batches or flush barriers are queued.
    std::condition_variable work_cv;
    /// Wakes flush callers when their requested flush barrier has been completed.
    std::condition_variable flush_cv;
    uint64_t next_flush_id = 0;
    uint64_t completed_flush_id = 0;
    uint64_t pending_bytes = 0;
    uint64_t dropped_batch_count = 0;
    uint64_t dropped_sample_count = 0;
    uint64_t max_pending_bytes = 0;
    /// Set once the producer has handed off its final buffer.
    bool producer_finished = true;
    /// Set once the worker has drained all queued work and exited.
    bool worker_finished = true;

    // Keep a small hot pool of reusable buffers; extra overflow buffers are
    // released once the worker drains them so bursty growth stays temporary.
    static constexpr size_t max_reusable_buffers = 4;
    static constexpr size_t sampled_thread_name_capacity = 64;

    static void* worker_thread_entry(void* arg);
    void worker_main();
    void recycle_batch(std::vector<stack_trace_t>&& batch, uint64_t footprint_bytes);
    static void destroy_batch(std::vector<stack_trace_t>& batch);
    void clear_pending_work_locked();
    uint64_t batch_footprint_bytes(const std::vector<stack_trace_t>& batch) const;
};

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH
#endif // DD_PROFILER_AGGREGATION_WORKER_H_
