#include "E01Calibration.h"
#include <pthread.h>
#include <malloc/malloc.h>
int e01_calibrate_queue(dispatch_queue_t queue, E01AllocationResult *out) {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0), start=dispatch_semaphore_create(0), done=dispatch_semaphore_create(0);
    pthread_t owner=pthread_self();
    __block int success=0, distinct=0;
    dispatch_async(queue, ^{
        dispatch_semaphore_signal(ready);
        dispatch_semaphore_wait(start, DISPATCH_TIME_FOREVER);
        distinct=!pthread_equal(owner,pthread_self());
        success=e01_allocation_sentinel();
        dispatch_semaphore_signal(done);
    });
    if(dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) return 0;
    uint64_t epoch=0; int opened=!e01_allocation_epoch_begin(&epoch);
    dispatch_semaphore_signal(start);
    if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) return 0;
    if(!opened || e01_allocation_epoch_end(epoch,out)) return 0;
    return distinct && success && out->process.operations==3 && out->process.requested_bytes==165 && out->caller.operations==0 && out->other.operations==3 && out->other.requested_bytes==165;
}
int e01_calibrate_concurrent(E01AllocationResult *out) {
    dispatch_semaphore_t ready=dispatch_semaphore_create(0), start=dispatch_semaphore_create(0), done=dispatch_semaphore_create(0);
    __block struct { int values[4]; } successes={{0}};
    for(int i=0;i<4;i++) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        dispatch_semaphore_signal(ready);dispatch_semaphore_wait(start,DISPATCH_TIME_FOREVER);
        int good=1;for(int j=0;j<100;j++)good&=e01_allocation_sentinel();successes.values[i]=good;
        dispatch_semaphore_signal(done);
    });
    for(int i=0;i<4;i++)if(dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)))return 0;
    uint64_t epoch=0;int opened=!e01_allocation_epoch_begin(&epoch);
    for(int i=0;i<4;i++)dispatch_semaphore_signal(start);
    for(int i=0;i<4;i++)if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)))return 0;
    if(!opened || e01_allocation_epoch_end(epoch,out))return 0;
    return successes.values[0]&&successes.values[1]&&successes.values[2]&&successes.values[3]&&out->process.operations==1200&&out->process.requested_bytes==66000&&out->caller.operations==0&&out->other.operations==1200;
}
uint64_t e01_live_heap_bytes(void) {malloc_statistics_t s={0};malloc_zone_statistics(NULL,&s);return s.size_in_use;}
