// XorProcess.hpp — 2-input XOR gate: OUT = A ^ B

#ifndef XORPROCESS_HPP
#define XORPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class XorProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& OUT;

public:
    XorProcess(Signal& a, Signal& b, Signal& out)
        : A(a), B(b), OUT(out) {
        process_name = "XOR(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate(A.getValue() ^ B.getValue());
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
