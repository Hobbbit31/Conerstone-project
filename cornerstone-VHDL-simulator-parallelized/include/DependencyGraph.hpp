// DependencyGraph.hpp — Groups processes into layers for parallel execution

#ifndef DEPENDENCYGRAPH_HPP
#define DEPENDENCYGRAPH_HPP

#include <vector>
#include <map>
#include <set>
#include <queue>
#include <iostream>
#include "Process.hpp"
#include "Signal.hpp"

using namespace std;

class DependencyGraph {
public:

    // Builds layers of processes that can run in parallel
    // Layer 0 has no dependencies, Layer 1 depends on Layer 0, etc.
    static vector<vector<Process*>> buildLayers(const vector<Process*>& processes)
    {
        //Map each signal to the process that writes it
        map<Signal*, Process*> signal_to_writer;

        for (size_t i = 0; i < processes.size(); i++) {
            vector<Signal*> outputs = processes[i]->getOutputSignals();
            for (size_t j = 0; j < outputs.size(); j++) {
                signal_to_writer[outputs[j]] = processes[i];
            }
        }

        //Build adjacency list and in-degrees
        // If process W writes a signal that process P reads, then W -> P
        map<Process*, vector<Process*>> adj;
        map<Process*, int> in_degree;

        for (size_t i = 0; i < processes.size(); i++) {
            in_degree[processes[i]] = 0;
        }

        for (size_t i = 0; i < processes.size(); i++) {
            Process* curr = processes[i];
            vector<Signal*> inputs = curr->getInputSignals();

            for (size_t j = 0; j < inputs.size(); j++) {
                auto it = signal_to_writer.find(inputs[j]);
                if (it != signal_to_writer.end()) {
                    Process* writer = it->second;
                    if (writer != curr) {
                        adj[writer].push_back(curr);
                        in_degree[curr]++;
                    }
                }
            }
        }

        //layers one by one
        vector<vector<Process*>> layers;
        queue<Process*> ready;

        for (size_t i = 0; i < processes.size(); i++) {
            if (in_degree[processes[i]] == 0)
                ready.push(processes[i]);
        }

        int done = 0;

        while (!ready.empty()) {
            // Take all currently ready processes as one layer
            vector<Process*> layer;
            int count = ready.size();

            for (int i = 0; i < count; i++) {
                Process* p = ready.front();
                ready.pop();
                layer.push_back(p);
                done++;
            }

            // Remove this layer from the graph
            for (size_t i = 0; i < layer.size(); i++) {
                auto it = adj.find(layer[i]);
                if (it != adj.end()) {
                    for (size_t j = 0; j < it->second.size(); j++) {
                        in_degree[it->second[j]]--;
                        if (in_degree[it->second[j]] == 0)
                            ready.push(it->second[j]);
                    }
                }
            }

            layers.push_back(layer);
        }

        //Handle cycles (feedback loops like SR latches)
        if (done < (int)processes.size()) {
            vector<Process*> fallback;
            for (size_t i = 0; i < processes.size(); i++) {
                if (in_degree[processes[i]] != 0)
                    fallback.push_back(processes[i]);
            }
            cout << "[DependencyGraph] Warning: " << fallback.size() << " process(es) in a feedback loop. Adding as fallback layer.\n";
            layers.push_back(fallback);
        }

        return layers;
    }

};

// defined in src/print.cpp
void printLayers(const vector<vector<Process*>>& layers);

#endif
