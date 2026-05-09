#include "../include/Simulator.hpp"
#include "../include/DependencyGraph.hpp"
#include "../include/Signal.hpp"
#include "../include/DebugFlags.hpp"
#include "../include/io_handlers/VCDWriter.hpp"
#include "../include/io_handlers/StimParser.hpp"
#include "../include/Stimulusprocess.hpp"
#include "../include/io_handlers/NetlistParser.hpp"
#include "../include/vhdl/VHDLCodeGen.hpp"

#include <iostream>
#include <fstream>
#include <cstdio>
#include <vector>
#include <string>
#include <sys/stat.h>

using namespace std;



static bool endsWith(const string &str, const string &suffix) {
    if (suffix.size() > str.size()) return false;
    return str.compare(str.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// prints all signals and gates in the circuit
static void printNetlist(const Circuit& circuit) {
    cout << "\n[Netlist]\n";

    cout << "  Signals:\n";
    for (auto* s : circuit.signal_order) {
        cout << "    " << s->getName() << " = " << s->getValue() << "\n";
    }

    cout << "  Gates:\n";
    for (const auto& p : circuit.processes) {
        cout << "    " << p->getName() << "  :  ";

        vector<Signal*> inputs = p->getInputSignals();
        for (size_t i = 0; i < inputs.size(); i++) {
            if (i > 0) cout << ", ";
            cout << inputs[i]->getName();
        }

        cout << " --> ";

        vector<Signal*> outputs = p->getOutputSignals();
        for (size_t i = 0; i < outputs.size(); i++) {
            if (i > 0) cout << ", ";
            cout << outputs[i]->getName();
        }
        cout << "\n";
    }
}

// prints dependency layers (moved from DependencyGraph.hpp)
void printLayers(const vector<vector<Process*>>& layers) {
    cout << "\n========== DEPENDENCY GRAPH ==========\n";
    int total = 0;
    for (size_t l = 0; l < layers.size(); l++) {
        cout << "\nLayer " << l;
        if (layers[l].size() > 1) cout << " (parallel)";
        cout << ":\n";
        for (size_t p = 0; p < layers[l].size(); p++) {
            Process* proc = layers[l][p];
            cout << "  " << proc->getName() << " : ";
            vector<Signal*> inputs = proc->getInputSignals();
            for (size_t i = 0; i < inputs.size(); i++) {
                if (i > 0) cout << ", ";
                cout << inputs[i]->getName();
            }
            cout << " --> ";
            vector<Signal*> outputs = proc->getOutputSignals();
            for (size_t i = 0; i < outputs.size(); i++) {
                if (i > 0) cout << ", ";
                cout << outputs[i]->getName();
            }
            cout << "\n";
            total++;
        }
    }
    cout << "\nTotal: " << total << " processes in "
         << layers.size() << " layers\n";
    cout << "======================================\n\n";
}

// prints all stimulus events
static void printStimulus(const vector<StimulusProcess*>& stimuli) {
    cout << "\n[Stimulus]\n";
    for (size_t i = 0; i < stimuli.size(); i++) {
        vector<Signal*> outputs = stimuli[i]->getOutputSignals();
        if (!outputs.empty()) {
            cout << "  " << stimuli[i]->getName() << "\n";
        }
    }
}