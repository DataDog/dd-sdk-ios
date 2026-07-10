/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "aggregation_worker.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <algorithm>
#include <new>

namespace dd::profiler {

aggregation_worker::aggregation_worker(
    size_t initial_buffer_size,
    uint32_t max_stack_depth,
    stack_trace_callback_t callback,
    void* ctx,
    uint64_t hard_limit_bytes,
    qos_class_t worker_qos)
    : config{
        initial_buffer_size,
        max_stack_depth,
        worker_qos,
        callback,
        ctx,
        hard_limit_bytes
    } {
}

aggregation_worker::~aggregation_worker() {
    stop();
}

void* aggregation_worker::worker_thread_entry(void* arg) {
    pthread_setname_np("com.datadoghq.profiler.aggregate");
    static_cast<aggregation_worker*>(arg)->worker_main();
    return nullptr;
}

bool aggregation_worker::start() {
    std::lock_guard<std::mutex> lock(work_mutex);

    if (has_worker_thread) {
        return false;
    }

    clear_pending_work_locked();
    next_flush_id = 0;
    completed_flush_id = 0;
    pending_bytes = 0;
    diagnostics = dd_profiler_diagnostics_t{};
    producer_finished = false;
    worker_finished = false;
    worker_mach_thread.store(MACH_PORT_NULL, std::memory_order_relaxed);

    pthread_attr_t worker_attr;
    pthread_attr_init(&worker_attr);
    pthread_attr_set_qos_class_np(&worker_attr, config.worker_qos, 0);

    int result = pthread_create(&worker_thread, &worker_attr, worker_thread_entry, this);
    pthread_attr_destroy(&worker_attr);
    if (result != 0) {
        producer_finished = true;
        worker_finished = true;
        flush_cv.notify_all();
        return false;
    }

    worker_mach_thread.store(pthread_mach_thread_np(worker_thread), std::memory_order_relaxed);
    has_worker_thread = true;
    return true;
}

void aggregation_worker::stop() {
    {
        std::lock_guard<std::mutex> lock(work_mutex);
        if (!has_worker_thread && worker_finished) {
            clear_pending_work_locked();
            worker_mach_thread.store(MACH_PORT_NULL, std::memory_order_relaxed);
            return;
        }

        producer_finished = true;
        work_cv.notify_all();
        flush_cv.notify_all();
    }

    if (has_worker_thread) {
        pthread_join(worker_thread, nullptr);
    }

    {
        std::lock_guard<std::mutex> lock(work_mutex);
        has_worker_thread = false;
        worker_mach_thread.store(MACH_PORT_NULL, std::memory_order_relaxed);
        clear_pending_work_locked();
        worker_finished = true;
        producer_finished = true;
    }
}

bool aggregation_worker::request_flush(flush_action_t action) {
    std::unique_lock<std::mutex> lock(work_mutex);

    if (worker_finished) {
        return false;
    }

    const uint64_t flush_id = ++next_flush_id;

    flush_barrier barrier{
        flush_id,
        std::move(action)
    };

    if (producer_finished) {
        pending_work.emplace_back(std::move(barrier));
        work_cv.notify_one();
    } else {
        requested_flushes.push_back(std::move(barrier));
    }

    flush_cv.wait(lock, [this, flush_id] {
        return completed_flush_id >= flush_id || worker_finished;
    });

    return completed_flush_id >= flush_id;
}

void aggregation_worker::enqueue_active_buffer(std::vector<stack_trace_t>& active_buffer) {
    if (active_buffer.empty()) {
        return;
    }

    std::vector<stack_trace_t> dropped_batch;
    bool did_drop = false;

    {
        std::lock_guard<std::mutex> lock(work_mutex);
        std::vector<stack_trace_t> batch;

        // Transfer ownership of captured traces to the worker queue. The
        // sampler keeps using `active_buffer` after this call returns.
        batch.swap(active_buffer);

        const uint64_t batch_bytes = batch_footprint_bytes(batch);
        if (pending_bytes + batch_bytes > config.hard_limit_bytes) {
            // Enforce a hard queue-memory limit without blocking the sampling
            // loop. Dropped samples are reported through diagnostics.
            diagnostics.dropped_batch_count += 1;
            diagnostics.dropped_sample_count += batch.size();
            diagnostics.max_pending_bytes = std::max(diagnostics.max_pending_bytes, pending_bytes + batch_bytes);
            dropped_batch = std::move(batch);
            did_drop = true;
        } else {
            pending_bytes += batch_bytes;
            diagnostics.max_pending_bytes = std::max(diagnostics.max_pending_bytes, pending_bytes);
            pending_work.emplace_back(batch_item{
                std::move(batch),
                batch_bytes
            });
        }
    }

    if (did_drop) {
        // Destroy trace payloads outside the queue lock; cleanup can release
        // frame and thread-name allocations.
        free_batch_payloads(dropped_batch);
    }

    if (!did_drop) {
        work_cv.notify_one();
    }

    if (active_buffer.capacity() == 0) {
        try {
            // Best effort: restore the sampler's expected batch capacity after
            // handing off the previous buffer.
            active_buffer.reserve(config.initial_buffer_size);
        } catch (const std::bad_alloc&) {
            return;
        }
    }
}

void aggregation_worker::service_pending_flush_request(std::vector<stack_trace_t>& active_buffer) {
    {
        std::lock_guard<std::mutex> lock(work_mutex);
        if (requested_flushes.empty()) {
            return;
        }
    }

    enqueue_active_buffer(active_buffer);

    {
        std::lock_guard<std::mutex> lock(work_mutex);
        while (!requested_flushes.empty()) {
            pending_work.emplace_back(std::move(requested_flushes.front()));
            requested_flushes.pop_front();
        }
    }

    work_cv.notify_one();
}

void aggregation_worker::finish_producer(std::vector<stack_trace_t>& active_buffer) {
    service_pending_flush_request(active_buffer);
    enqueue_active_buffer(active_buffer);

    {
        std::lock_guard<std::mutex> lock(work_mutex);
        while (!requested_flushes.empty()) {
            pending_work.emplace_back(std::move(requested_flushes.front()));
            requested_flushes.pop_front();
        }

        producer_finished = true;
    }

    work_cv.notify_all();
    flush_cv.notify_all();
}

bool aggregation_worker::is_worker_thread() {
    std::lock_guard<std::mutex> lock(work_mutex);
    return has_worker_thread && pthread_equal(pthread_self(), worker_thread);
}

bool aggregation_worker::is_worker_thread(thread_t thread) {
    const thread_t worker_thread_id = worker_mach_thread.load(std::memory_order_relaxed);
    return worker_thread_id != MACH_PORT_NULL && thread == worker_thread_id;
}

void aggregation_worker::consume_diagnostics(dd_profiler_diagnostics_t& out) {
    std::lock_guard<std::mutex> lock(work_mutex);
    out = diagnostics;
    diagnostics = dd_profiler_diagnostics_t{0, 0, pending_bytes};
}

void aggregation_worker::worker_main() {
    while (true) {
        work_item item{flush_barrier{}};

        {
            std::unique_lock<std::mutex> lock(work_mutex);
            work_cv.wait(lock, [this] {
                return !pending_work.empty() || producer_finished;
            });

            if (pending_work.empty()) {
                if (producer_finished) {
                    worker_finished = true;
                    flush_cv.notify_all();
                    return;
                }

                continue;
            }

            item = std::move(pending_work.front());
            pending_work.pop_front();
        }

        if (auto* batch = std::get_if<batch_item>(&item)) {
            if (config.callback && !batch->traces.empty()) {
                config.callback(batch->traces.data(), batch->traces.size(), config.ctx);
            }

            free_batch_payloads(batch->traces);
            complete_batch(batch->footprint_bytes);
            continue;
        }

        auto& barrier = std::get<flush_barrier>(item);
        if (barrier.action) {
            barrier.action();
        }

        {
            std::lock_guard<std::mutex> lock(work_mutex);
            completed_flush_id = std::max(completed_flush_id, barrier.flush_id);
        }

        flush_cv.notify_all();
    }
}

void aggregation_worker::complete_batch(uint64_t footprint_bytes) {
    std::lock_guard<std::mutex> lock(work_mutex);
    pending_bytes = pending_bytes > footprint_bytes ? pending_bytes - footprint_bytes : 0;
}

void aggregation_worker::free_batch_payloads(std::vector<stack_trace_t>& batch) {
    for (auto& trace : batch) {
        stack_trace_destroy(&trace);
    }
}

void aggregation_worker::clear_pending_work_locked() {
    for (auto& item : pending_work) {
        if (auto* batch = std::get_if<batch_item>(&item)) {
            free_batch_payloads(batch->traces);
        }
    }

    pending_work.clear();
    requested_flushes.clear();
    pending_bytes = 0;
}

uint64_t aggregation_worker::batch_footprint_bytes(const std::vector<stack_trace_t>& batch) const {
    const uint64_t trace_storage_bytes = static_cast<uint64_t>(batch.capacity()) * sizeof(stack_trace_t);
    const uint64_t frame_storage_bytes = static_cast<uint64_t>(batch.size()) * config.max_stack_depth * sizeof(stack_frame_t);
    uint64_t thread_name_bytes = 0;

    for (const auto& trace : batch) {
        if (trace.thread_name) {
            thread_name_bytes += sampled_thread_name_capacity;
        }
    }

    return trace_storage_bytes + frame_storage_bytes + thread_name_bytes;
}

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH
