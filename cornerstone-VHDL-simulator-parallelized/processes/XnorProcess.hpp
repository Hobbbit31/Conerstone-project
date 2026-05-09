// XnorProcess.hpp — 2-input XNOR gate: OUT = ~(A ^ B)

#ifndef XNORPROCESS_HPP
#define XNORPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class XnorProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& OUT;

public:
    XnorProcess(Signal& a, Signal& b, Signal& out)
        : A(a), B(b), OUT(out) {
        process_name = "XNOR(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate((A.getValue() ^ B.getValue()) ^ 1);
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
