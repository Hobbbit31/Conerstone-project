// Simulator.cpp — Main simulation loop (VHDL delta-cycle semantics)

#include "../include/Simulator.hpp"
#include "../include/Process.hpp"
#include "../include/DebugFlags.hpp"
#include "../include/io_handlers/VCDWriter.hpp"
#include <omp.h>
#include <time.h>
#include <chrono>


using namespace std;
 
const int MAX_DELTA_CYCLES = 1000000;
const int PARALLEL_THRESHOLD = 512;
const int COMMIT_PARALLEL_THRESHOLD = 4096;



void addingDelayForTesting() {
    for(volatile int i = 0 ; i< 10000 ; i++); // adding a delay to make the sequential execution time more noticeable for testing
}

void Simulator::scheduleEvent(uint64_t time, uint32_t delta, Process* process) {
    event_queue.emplace(time, delta, process);
}

void Simulator::addSignal(Signal* sig) {
    all_signals.push_back(sig);
}

void Simulator::addProcess(Process* proc) {
    all_processes.push_back(proc);
}

void Simulator::buildDependencyGraph() {
    dependency_layers = DependencyGraph::buildLayers(all_processes);

    // reverse lookup: process -> layer index, built once at startup
    which_layer.clear();
    for (int layer_num = 0; layer_num < (int)dependency_layers.size(); layer_num++) {
        for (size_t j = 0; j < dependency_layers[layer_num].size(); j++) {
            which_layer[dependency_layers[layer_num][j]] = layer_num;
        }
    }
}

void Simulator::run(bool sequential) {


    // // warmup: force OS to fully initialize all threads before timing starts
    volatile int warmup = 0;
    #pragma omp parallel reduction(+:warmup)
    {
        warmup += 1;
    }
    
    // struct timespec start_time;
    // clock_gettime(CLOCK_MONOTONIC, &start_time);

    auto start = chrono::high_resolution_clock::now();
    
    // schedule every process to run once at time 0
    for (size_t i = 0; i < all_processes.size(); i++) {
        scheduleEvent(0, 0, all_processes[i]);
    }

    while (!event_queue.empty()) {

        uint64_t batch_time  = event_queue.top().time;
        uint32_t batch_delta = event_queue.top().delta;

        if (batch_delta > MAX_DELTA_CYCLES) {
            cerr << "Error: delta cycle limit (" << MAX_DELTA_CYCLES
                 << ") exceeded at time " << batch_time
                 << ". Possible combinational loop.\n";
            break;
        }

        current_time  = batch_time;
        current_delta = batch_delta;

        // collect all events at the same (time, delta)
        vector<Process*> batch;
        set<Process*> already_added;

        while (!event_queue.empty()) {
            Event top = event_queue.top();
            if (top.time != batch_time || top.delta != batch_delta)
                break;
            event_queue.pop();
            if (already_added.find(top.process) == already_added.end()) {
                batch.push_back(top.process);
                already_added.insert(top.process);
            }
        }

        // bucket batch processes by layer; ungraphed (stimulus, clock) go to leftover
        vector<vector<Process*>> my_layer_buckets(dependency_layers.size());
        vector<Process*> leftover_processes;

        for (size_t i = 0; i < batch.size(); i++) {
            Process* current_process = batch[i];
            auto found = which_layer.find(current_process);
            if (found != which_layer.end()) {
                int layer_num = found->second;
                my_layer_buckets[layer_num].push_back(current_process);
            } else {
                // not in dependency graph (stimulus, clock)
                leftover_processes.push_back(current_process);
            }
        }

        if (sequential) {
            // -seq flag: run every layer on one thread, no OpenMP
            for (size_t layer_idx = 0; layer_idx < my_layer_buckets.size(); layer_idx++) {
                for (size_t i = 0; i < my_layer_buckets[layer_idx].size(); i++) {
                    my_layer_buckets[layer_idx][i]->execute(*this);
                    //adding a delay for each gate execution and connsidering the gate execution to same for all (i know this part is not okay but for simulation purpose doingthis)
                    addingDelayForTesting();
                }
            }
        } else {
            // parallel: run layers in order; within a layer processes are independent
            // omp for has an implicit barrier between layers
           
                for (size_t layer_idx = 0; layer_idx < my_layer_buckets.size(); layer_idx++) {
                    const auto& layer = my_layer_buckets[layer_idx];
                    if (layer.empty()) continue;

                    if (layer.size() < PARALLEL_THRESHOLD) {
                        
                            for (size_t i = 0; i < layer.size(); i++) {
                                layer[i]->execute(*this);
                                //adding a delay for each gate execution and connsidering the gate execution to same for all (i know this part is not okay but for simulation purpose doingthis)
                                addingDelayForTesting();
                            }
                        
                    } else {
                        //adding a delay for each gate execution and connsidering the gate execution to same for all (i know this part is not okay but for simulation purpose doingthis)
                        
                        #pragma omp parallel for schedule(dynamic, 16)
                        for (size_t i = 0; i < layer.size(); i++) {
                            layer[i]->execute(*this);
                            addingDelayForTesting();
                            
                        }                       
                    }
                }
            
        }

        // leftover processes run sequentially
        for (size_t i = 0; i < leftover_processes.size(); i++) {
            leftover_processes[i]->execute(*this);
            //adding a delay for each gate execution and connsidering the gate execution to same for all (i know this part is not okay but for simulation purpose doingthis)
            addingDelayForTesting();
        }

        // commit signals and schedule next delta if anything changed

        //below is the sequential commit code, which is simpler
        if(sequential){
        for (size_t i = 0; i < all_signals.size(); i++) {
            bool changed = all_signals[i]->commit();

            if (changed) {
                logSignalChange(all_signals[i]->getName(),all_signals[i]->getValue());

                vector<Process*> sensitive = all_signals[i]->getSensitiveProcesses();
                for (size_t j = 0; j < sensitive.size(); j++) {
                    scheduleEvent(current_time, current_delta + 1, sensitive[j]);
                }
            }
        }
        } else {
            // Parallel commit phase 
            // basically cheking parallelly if signals have changed, but doing the logging and scheduling sequential

            if (all_signals.size() < PARALLEL_THRESHOLD) {
                for (size_t i = 0; i < all_signals.size(); i++) {
                    bool changed = all_signals[i]->commit();

                    if (changed) {
                        logSignalChange(all_signals[i]->getName(),all_signals[i]->getValue());

                        vector<Process*> sensitive = all_signals[i]->getSensitiveProcesses();
                        for (size_t j = 0; j < sensitive.size(); j++) {
                            scheduleEvent(current_time, current_delta + 1, sensitive[j]);
                        }
                    }
                }
                
            }else{
            static vector<char> changed_flags;
            if (changed_flags.size() != all_signals.size()) {
                changed_flags.assign(all_signals.size(), 0);
            }

            #pragma omp parallel for schedule(dynamic , 16)
            for (size_t i = 0; i < (int)all_signals.size(); i++) {
                changed_flags[i] = (char)all_signals[i]->commit();
            }

            // sequentially log changes and schedule next events to avoid contention on locks and VCDWriter
            for (size_t i = 0; i < all_signals.size(); i++) {
                if (changed_flags[i]) {
                    logSignalChange(all_signals[i]->getName(), all_signals[i]->getValue());
                    const vector<Process*>& sensitive = all_signals[i]->getSensitiveProcesses();
                    for (size_t j = 0; j < sensitive.size(); j++) {
                        scheduleEvent(current_time, current_delta + 1, sensitive[j]);
                    }
                }
            }
            }
        }
        
       
    }
    auto end = chrono::high_resolution_clock::now();
    chrono::duration<double> elapsed = (end - start);
    
    printf("Elapsed: %.6f ms\n", elapsed.count() * 1000);
    
}

uint64_t Simulator::getCurrentTime() const {
    return current_time;
}

void Simulator::logSignalChange(const string& name, int value) {
    if (DebugFlags::show_sim) {
        cout << "Time " << current_time
             << " (delta " << current_delta << ") : "
             << name << " = " << value << endl;
    }

    if (vcd_writer) {
        vcd_writer->logChange(current_time, name, value);
    }
}

const std::vector<std::vector<Process*>>& Simulator::getLayers() const {
    return dependency_layers;
}
