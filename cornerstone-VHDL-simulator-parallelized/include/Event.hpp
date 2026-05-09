// Event.hpp — A scheduled event: "at time T, delta D, run process P"

#ifndef EVENT_HPP
#define EVENT_HPP

#include <cstdint>

class Process;

struct Event {
    uint64_t  time;
    uint32_t  delta;
    Process*  process;

    Event(uint64_t t, uint32_t d, Process* p)
        : time(t), delta(d), process(p) {}
};

// Comparator for min-heap (smallest time first, then smallest delta)
struct EventCompare {
    bool operator()(const Event& a, const Event& b) const {
        if (a.time != b.time)
            return a.time > b.time;
        return a.delta > b.delta;
    }
};

#endif
