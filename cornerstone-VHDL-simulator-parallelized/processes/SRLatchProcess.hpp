// SRLatchProcess.hpp — Active-high SR Latch
// S=1,R=0 -> Set, S=0,R=1 -> Reset, S=0,R=0 -> Hold, S=1,R=1 -> Forbidden

#ifndef SRLATCHPROCESS_HPP
#define SRLATCHPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"
#include <iostream>

using namespace std;

class SRLatchProcess : public Process {
private:
    Signal& S;
    Signal& R;
    Signal& Q;
    Signal& Q_NOT;

public:
    SRLatchProcess(Signal& s, Signal& r, Signal& q, Signal& q_not)
        : S(s), R(r), Q(q), Q_NOT(q_not) {
        process_name = "SR(" + q.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        int s = S.getValue();
        int r = R.getValue();

        if (s == 0 && r == 0)
            return;  // hold

        if (s == 1 && r == 0) {
            Q.scheduleUpdate(1);
            Q_NOT.scheduleUpdate(0);
        } else if (s == 0 && r == 1) {
            Q.scheduleUpdate(0);
            Q_NOT.scheduleUpdate(1);
        } else {
            cerr << "[Warning] SR Latch: S=1, R=1 is forbidden. Holding.\n";
        }
    }

    vector<Signal*> getInputSignals() const override {
        return {&S, &R};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&Q, &Q_NOT};
    }
};

#endif
