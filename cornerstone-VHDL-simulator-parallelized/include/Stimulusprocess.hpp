// StimulusProcess.hpp — Drives a signal to a specific value
// Created from .stim file entries like "@10 A=1"

#ifndef STIMULUSPROCESS_HPP
#define STIMULUSPROCESS_HPP

#include "Process.hpp"
#include "Signal.hpp"
#include "Simulator.hpp"

using namespace std;

class StimulusProcess : public Process {
private:
    Signal& target;
    int new_value;

public:
    StimulusProcess(Signal& sig, int val)
        : target(sig), new_value(val) {
        process_name = "STIM(" + sig.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        target.scheduleUpdate(new_value);
    }

    vector<Signal*> getInputSignals() const override {
        return {};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&target};
    }
};

#endif
