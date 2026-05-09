// MuxProcess.hpp — 2-to-1 Multiplexer: SEL=0 -> A, SEL=1 -> B

#ifndef MUXPROCESS_HPP
#define MUXPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class MuxProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& SEL;
    Signal& OUT;

public:
    MuxProcess(Signal& a, Signal& b, Signal& sel, Signal& out)
        : A(a), B(b), SEL(sel), OUT(out) {
        process_name = "MUX(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        int result = (SEL.getValue() == 1) ? B.getValue() : A.getValue();
        OUT.scheduleUpdate(result);
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B, &SEL};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
