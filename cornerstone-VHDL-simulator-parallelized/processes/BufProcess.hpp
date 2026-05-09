// BufProcess.hpp — Buffer gate: OUT = A (pass-through)

#ifndef BUFPROCESS_HPP
#define BUFPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class BufProcess : public Process {
private:
    Signal& A;
    Signal& OUT;

public:
    BufProcess(Signal& a, Signal& out)
        : A(a), OUT(out) {
        process_name = "BUF(" + out.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        OUT.scheduleUpdate(A.getValue());
    }

    vector<Signal*> getInputSignals() const override {
        return {&A};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&OUT};
    }
};

#endif
