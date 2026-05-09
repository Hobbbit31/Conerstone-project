// VCDWriter.hpp — Writes waveforms in VCD format (for GTKWave, etc.)

#ifndef VCDWRITER_HPP
#define VCDWRITER_HPP

#include <string>
#include <fstream>
#include <vector>
#include <map>
#include <ctime>
#include <stdexcept>
#include "../Signal.hpp"

using namespace std;

class VCDWriter {
private:
    ofstream file;
    string timescale;
    map<string, char> id_map;
    char next_id = '!';
    uint64_t last_time = UINT64_MAX;

    char assignId(const string& name) {
        char id = next_id++;
        id_map[name] = id;
        return id;
    }

public:
    VCDWriter(const string& filename, const string& ts = "1ns")
        : timescale(ts)
    {
        file.open(filename);
        if (!file.is_open())
            throw runtime_error("Cannot open VCD file: " + filename);
    }

    void registerSignal(Signal& sig) {
        assignId(sig.getName());
    }
    void writeHeader(const vector<Signal*>& signals,
                     const string& module_name = "sim") {
        // time_t now = time(nullptr);
        // file << "$date " << ctime(&now) << "$end\n";
        file << "$version EventDrivenSim 1.0 $end\n";
        file << "$timescale " << timescale << " $end\n\n";

        file << "$scope module " << module_name << " $end\n";
        for (auto* sig : signals) {
            char id = id_map.at(sig->getName());
            file << "  $var wire 1 " << id
                 << " " << sig->getName() << " $end\n";
        }
        file << "$upscope $end\n\n";
        file << "$enddefinitions $end\n\n";

        file << "$dumpvars\n";
        for (auto* sig : signals) {
            char id = id_map.at(sig->getName());
            file << "b" << sig->getValue() << " " << id << "\n";
        }
        file << "$end\n\n";
    }

    void logChange(uint64_t time, const string& sig_name, int value) {
        if (id_map.find(sig_name) == id_map.end()) return;

        if (time != last_time) {
            file << "#" << time << "\n";
            last_time = time;
        }
        file << "b" << value << " " << id_map[sig_name] << "\n";
    }

    void close() {
        if (file.is_open()) file.close();
    }

    ~VCDWriter() { close(); }
};

#endif
