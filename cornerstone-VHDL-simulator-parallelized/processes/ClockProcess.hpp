// ClockProcess.hpp — Clock generator, toggles every half_period ns

#ifndef CLOCKPROCESS_HPP
#define CLOCKPROCESS_HPP

#include "../include/Process.hpp"
#include "../include/Signal.hpp"
#include "../include/Simulator.hpp"

using namespace std;

class ClockProcess : public Process {
private:
    Signal&  CLK;
    uint64_t half_period;
    uint64_t stop_time;

public:
    ClockProcess(Signal& clk, uint64_t half_period, uint64_t stop_time)
        : CLK(clk), half_period(half_period), stop_time(stop_time) {
        process_name = "CLK(" + clk.getName() + ")";
    }

    void execute(Simulator& sim) override {
        CLK.scheduleUpdate(CLK.getValue() ^ 1);

        uint64_t next_time = sim.getCurrentTime() + half_period;
        if (next_time <= stop_time)
            sim.scheduleEvent(next_time, 0, this);
    }

    vector<Signal*> getInputSignals() const override {
        return {&CLK};
    }

    vector<Signal*> getOutputSignals() const override {
        return {&CLK};
    }
};

#endif
