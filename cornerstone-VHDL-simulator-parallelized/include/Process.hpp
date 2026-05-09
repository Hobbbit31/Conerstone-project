// Process.hpp — Base class for all simulation processes (gates, stimuli)

#ifndef PROCESS_HPP
#define PROCESS_HPP

#include <vector>
#include <string>

using namespace std;

class Simulator;
class Signal;

class Process {
protected:
    string process_name;

public:
    virtual void execute(Simulator& sim) = 0;
    virtual vector<Signal*> getInputSignals() const = 0;
    virtual vector<Signal*> getOutputSignals() const = 0;

    const string& getName() const { return process_name; }

    virtual ~Process() = default;
};

#endif
