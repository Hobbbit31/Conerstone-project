// AndProcess.hpp — 2-input AND gate: OUT = A & B

#ifndef ANDPROCESS_HPP
#define ANDPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class AndProcess : public Process {
private:
    Signal& A;
    Signal& B;
    Signal& OUT;

public:
    AndProcess(Signal& a, Signal& b, Signal& out)
        : A(a), B(b), OUT(out) {
        process_name = "AND(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate(A.getValue() & B.getValue());
    }

    vector<Signal*> getInputSignals() const override {
        return {&A, &B};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
