// NandProcess.hpp — 2-input NAND gate: OUT = ~(A & B)

#ifndef NANDPROCESS_HPP
#define NANDPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class NandProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& OUT;

public:
    NandProcess(Signal& a, Signal& b, Signal& out)
        : A(a), B(b), OUT(out) {
        process_name = "NAND(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate((A.getValue() & B.getValue()) ^ 1);
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
