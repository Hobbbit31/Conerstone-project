// NotProcess.hpp — Inverter: OUT = ~A (using XOR 1 for single-bit)

#ifndef NOTPROCESS_HPP
#define NOTPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class NotProcess : public Process {
private:
    Signal& A;
    Signal& OUT;

public:
    NotProcess(Signal& a, Signal& out)
        : A(a), OUT(out) {
        process_name = "NOT(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate(A.getValue() ^ 1);
    }

    vector<Signal*> getInputSignals() const override {
        return {&A};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
