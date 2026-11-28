// q36_route_side.cuh - STRATA_Q36_ROUTE_SIDE=1: the hybrid MoE's device->host copies of the routing (ids and the MoE
// input h, for the CPU pool) on a side stream, so the resident experts on the main stream need not wait behind them.
//
// Without it the two small copies sit on the main stream between k_route_group and the experts' gate/up kernel: on an
// RX 6900 XT (Ornith IQ4_XS, decode) the gate/up kernel starts a median 20 us after the router ends, 27.5 times a token,
// while the copies themselves take ~2 us each.  The side stream waits on the router, so it copies the same bytes as
// before, and ev_done (the host's ev_route) is recorded after the copies there, so the host reads them as before.
// Nothing on the main stream writes ids or h before the host has waited on ev_done (the next layer's kernels are
// launched after moe_hybrid_cpu), so the copies cannot race.  Off by default; =0 or unset keeps the old order.
#pragma once

#include <cstdio>
#include <cstdlib>

struct Q36RouteSide {
    cudaStream_t s = nullptr;
    cudaEvent_t routed = nullptr;
    int state = 0;   // 0 unknown, 1 off (or setup failed), 2 on

    bool on() {
        if (state == 0) {
            const char* v = std::getenv("STRATA_Q36_ROUTE_SIDE");
            state = (v != nullptr && std::atoi(v) != 0) ? 2 : 1;
            if (state == 2 && (cudaStreamCreateWithFlags(&s, cudaStreamNonBlocking) != cudaSuccess ||
                               cudaEventCreateWithFlags(&routed, cudaEventDisableTiming) != cudaSuccess)) {
                (void) cudaGetLastError();
                state = 1;   // the old order still works
            }
        }
        return state == 2;
    }

    /// Queue the copies after the work already on `st`; ev_done fires when they have landed. False: not handled.
    bool copy(cudaStream_t st, void* h_ids, const void* ids, size_t ids_bytes, void* h_h, const void* h, size_t h_bytes,
              cudaEvent_t ev_done) {
        if (!on()) return false;
        if (cudaEventRecord(routed, st) != cudaSuccess || cudaStreamWaitEvent(s, routed, 0) != cudaSuccess ||
            cudaMemcpyAsync(h_ids, ids, ids_bytes, cudaMemcpyDeviceToHost, s) != cudaSuccess ||
            cudaMemcpyAsync(h_h, h, h_bytes, cudaMemcpyDeviceToHost, s) != cudaSuccess ||
            cudaEventRecord(ev_done, s) != cudaSuccess) {
            std::fprintf(stderr, "strata-q36: STRATA_Q36_ROUTE_SIDE: %s\n", cudaGetErrorString(cudaGetLastError()));
            std::exit(1);   // a half-queued copy would leave the host reading stale ids
        }
        return true;
    }
};
