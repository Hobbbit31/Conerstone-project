// DFlipFlopProcess.hpp — Rising-edge D Flip-Flop
// On CLK 0->1: Q = D, Q_NOT = ~D

#ifndef DFLIPFLOPPROCESS_HPP
#define DFLIPFLOPPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"

using namespace std;

class DFlipFlopProcess : public Process {
private:
    Signal& CLK;
    Signal& D;
    Signal& Q;
    Signal& Q_NOT;
    int last_clk = 0;

public:
    DFlipFlopProcess(Signal& clk, Signal& d, Signal& q, Signal& q_not)
        : CLK(clk), D(d), Q(q), Q_NOT(q_not) {
        process_name = "DFF(" + q.getName() + ")";
    }

    void execute(Simulator& /*sim*/) override {
        int clk_now = CLK.getValue();

        // rising edge detection
        if (last_clk == 0 && clk_now == 1) {
            int d_val = D.getValue();
            Q.scheduleUpdate(d_val);
            Q_NOT.scheduleUpdate(d_val ^ 1);
        }

        last_clk = clk_now;
    }

    vector<Signal*> getInputSignals() const override {
        return {&CLK, &D};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&Q, &Q_NOT};
    }
};

#endif
