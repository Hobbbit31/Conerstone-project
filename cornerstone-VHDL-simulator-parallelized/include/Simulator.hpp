// Simulator.hpp — Discrete event simulation engine
// Processes events from a priority queue sorted by (time, delta)

#ifndef SIMULATOR_HPP
#define SIMULATOR_HPP

#include <queue>
#include <vector>
#include <set>
#include <unordered_map>

using namespace std;

#include "Event.hpp"
#include "Signal.hpp"
#include "DependencyGraph.hpp"

class VCDWriter;

class Simulator {
private:
    uint64_t current_time  = 0;
    uint32_t current_delta = 0;

    // min-heap ordered by (time, delta)
    priority_queue<Event, vector<Event>, EventCompare> event_queue;

    VCDWriter* vcd_writer = nullptr;

    vector<Signal*> all_signals;
    vector<Process*> all_processes;

    // dependency layers for parallel execution ordering
    vector<vector<Process*>> dependency_layers;

    // process -> layer index, for O(1) lookup per batch
    unordered_map<Process*, int> which_layer;

public:
    void scheduleEvent(uint64_t time, uint32_t delta, Process* process);
    void run(bool sequential = false);

    uint64_t getCurrentTime() const;

    void attachVCD(VCDWriter* writer) { vcd_writer = writer; }

    void addSignal(Signal* sig);
    void addProcess(Process* proc);

    // must be called after all processes are added, before run()
    void buildDependencyGraph();

    void logSignalChange(const string& name, int value);

    const vector<vector<Process*>>& getLayers() const;
};

#endif
