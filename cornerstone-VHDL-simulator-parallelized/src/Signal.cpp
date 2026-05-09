// Signal.cpp — Double-buffered signal implementation

#include "../include/Signal.hpp"

using namespace std;

Signal::Signal(const string& n, int initial)
    : name(n), current_value(initial), next_value(initial), pending(false) {
    omp_init_lock(&omp_mtx);
}

Signal::~Signal() {
    omp_destroy_lock(&omp_mtx);
}

void Signal::scheduleUpdate(int v) {
    omp_set_lock(&omp_mtx);
    next_value = v;
    pending = true;
    omp_unset_lock(&omp_mtx);
}

bool Signal::commit() {
    if (pending && next_value != current_value) {
        current_value = next_value;
        pending = false;
        return true;
    }
    pending = false;
    return false;
}

int Signal::getValue() const {
    return current_value;
}

void Signal::addSensitiveProcess(Process* p) {
    sensitive_processes.push_back(p);
}

const vector<Process*>& Signal::getSensitiveProcesses() const {
    return sensitive_processes;
}

const string& Signal::getName() const {
    return name;
}
