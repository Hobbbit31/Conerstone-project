// NorProcess.hpp — 2-input NOR gate: OUT = ~(A | B)

#ifndef NORPROCESS_HPP
#define NORPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class NorProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& OUT;

public:
    NorProcess(Signal& a, Signal& b, Signal& out)
        : A(a), B(b), OUT(out) {
        process_name = "NOR(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate((A.getValue() | B.getValue()) ^ 1);
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
