// Signal.hpp — A single-bit signal with double-buffered updates
// Processes read current_value and write to next_value.
// After all processes run, commit() moves next into current.

#ifndef SIGNAL_HPP
#define SIGNAL_HPP

#include <string>
#include <vector>
#include <omp.h>

using namespace std;

class Process;

class Signal {
private:
    string name;
    int  current_value;
    int  next_value;
    bool pending;

    // processes that wake up when this signal changes
    vector<Process*> sensitive_processes;

    // lock for thread-safe scheduleUpdate() during parallel execution
    omp_lock_t omp_mtx;

public:
    Signal(const string& n, int initial);
    ~Signal();

    void scheduleUpdate(int v);
    bool commit();  // returns true if value actually changed

    int  getValue() const;

    void addSensitiveProcess(Process* p);
    const vector<Process*>& getSensitiveProcesses() const;

    const string& getName() const;
};

#endif
