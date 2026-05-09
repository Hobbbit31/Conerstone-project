// OrProcess.hpp — 2-input OR gate: OUT = A | B

#ifndef ORPROCESS_HPP
#define ORPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class OrProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& OUT;

public:
    OrProcess(Signal& a, Signal& b, Signal& out)
        : A(a), B(b), OUT(out) {
        process_name = "OR(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate(A.getValue() | B.getValue());
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
