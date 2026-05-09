// StimParser.hpp — Reads .stim files and schedules stimulus events
// Format: @<time_ns> <signal>=<value>

#ifndef STIMPARSER_HPP
#define STIMPARSER_HPP

#include <string>
#include <fstream>
#include <sstream>
#include <vector>
#include <map>
#include <stdexcept>
#include "../Signal.hpp"
#include "Stimulusprocess.hpp"
#include "../Simulator.hpp"

using namespace std;

class StimParser {
public:
    static void load(const string& filename,
                     map<string, Signal*>& signals_map,
                     Simulator& sim,
                     vector<StimulusProcess*>& owned_stimuli)
    {
        ifstream file(filename);
        if (!file.is_open())
            throw runtime_error("Cannot open stimulus file: " + filename);

        string line;
        int line_num = 0;

        while (getline(file, line)) {
            line_num++;

            // strip comments and whitespace
            auto comment = line.find('#');
            if (comment != string::npos)
                line = line.substr(0, comment);

            line.erase(0, line.find_first_not_of(" \t\r\n"));
            line.erase(line.find_last_not_of(" \t\r\n") + 1);

            if (line.empty()) continue;

            if (line[0] != '@')
                throw runtime_error("Line " + to_string(line_num) +
                    ": expected '@<time>', got: " + line);

            // parse @<time> <signal>=<value>
            istringstream ss(line.substr(1));
            uint64_t time;
            string assignment;

            if (!(ss >> time >> assignment))
                throw runtime_error("Line " + to_string(line_num) +
                    ": bad format, expected '@<time> <signal>=<value>'");

            auto eq = assignment.find('=');
            if (eq == string::npos)
                throw runtime_error("Line " + to_string(line_num) +
                    ": missing '=' in: " + assignment);

            string sig_name = assignment.substr(0, eq);

            int value;
            try {
                string val_str = assignment.substr(eq + 1);
                if (val_str.empty())
                    throw runtime_error("empty value");
                value = stoi(val_str);
            } catch (...) {
                throw runtime_error("Line " + to_string(line_num) +
                    ": invalid value for signal '" + sig_name +
                    "' in: " + assignment);
            }

            if (signals_map.find(sig_name) == signals_map.end())
                throw runtime_error("Line " + to_string(line_num) +
                    ": unknown signal '" + sig_name + "'");

            auto* stim = new StimulusProcess(*signals_map[sig_name], value);
            owned_stimuli.push_back(stim);
            sim.scheduleEvent(time, 0, stim);
        }
    }
};

#endif
