// NetlistParser.hpp — Reads a .net file and builds a circuit
//
// Format:
//   signal <name> <initial_value>
//   <gate_type> <output> <input1> [input2] [input3]
//
// Supported gates: and, or, not, xor, nand, nor, xnor, buf, mux, dff, sr

#ifndef NETLISTPARSER_HPP
#define NETLISTPARSER_HPP

#include <string>
#include <fstream>
#include <sstream>
#include <map>
#include <set>
#include <vector>
#include <memory>
#include <stdexcept>
#include <iostream>
#include <algorithm>

#include "Signal.hpp"
#include "Simulator.hpp"
#include "../../processes/Processses.hpp"

using namespace std;

// Holds all the signals and processes in a circuit
struct Circuit {
    map<string, unique_ptr<Signal>>  signals;
    vector<unique_ptr<Process>>      processes;
    vector<Signal*>                  signal_order;
    set<string>                      driven_signals;

    Signal& sig(const string& name) {
        auto it = signals.find(name);
        if (it == signals.end())
            throw runtime_error("Unknown signal: '" + name + "'");
        return *it->second;
    }
};

class NetlistParser {
public:
    static Circuit load(const string& filename) {
        ifstream file(filename);
        if (!file.is_open())
            throw runtime_error("Cannot open netlist file: " + filename);

        Circuit circuit;
        string line;
        int line_num = 0;

        while (getline(file, line)) {
            line_num++;

            // strip comments
            auto comment = line.find('#');
            if (comment != string::npos) line = line.substr(0, comment);

            // trim whitespace
            line.erase(0, line.find_first_not_of(" \t\r\n"));
            line.erase(line.find_last_not_of(" \t\r\n") + 1);
            if (line.empty()) continue;

            istringstream ss(line);
            string keyword;
            ss >> keyword;

            // make lowercase
            transform(keyword.begin(), keyword.end(), keyword.begin(), ::tolower);

            // --- Signal declaration ---
            if (keyword == "signal") {
                string name; int init = 0;
                if (!(ss >> name >> init))
                    throw runtime_error("Line " + to_string(line_num) +
                        ": expected 'signal <name> <init_value>'");
                circuit.signals[name] = make_unique<Signal>(name, init);
                circuit.signal_order.push_back(circuit.signals[name].get());
                continue;
            }

            // --- Gate parsing ---
            string out, a, b, sel;

            // check for multiple drivers on same signal
            auto warnDriver = [&](const string& out_name) {
                if (circuit.driven_signals.count(out_name)) {
                    cerr << "[Warning] Line " << line_num << ": signal '"
                         << out_name << "' already driven by another gate.\n";
                }
                circuit.driven_signals.insert(out_name);
            };

            if (keyword == "not" || keyword == "buf") {
                // single-input gates
                if (!(ss >> out >> a))
                    throw runtime_error("Line " + to_string(line_num) +
                        ": " + keyword + " needs: <out> <a>");

                warnDriver(out);
                Signal& sOut = circuit.sig(out);
                Signal& sA   = circuit.sig(a);

                Process* p = nullptr;
                if (keyword == "not") p = new NotProcess(sA, sOut);
                else                  p = new BufProcess(sA, sOut);

                sA.addSensitiveProcess(p);
                circuit.processes.emplace_back(p);

            } else if (keyword == "mux") {
                if (!(ss >> out >> a >> b >> sel))
                    throw runtime_error("Line " + to_string(line_num) +
                        ": mux needs: <out> <a> <b> <sel>");

                warnDriver(out);
                Signal& sOut = circuit.sig(out);
                Signal& sA   = circuit.sig(a);
                Signal& sB   = circuit.sig(b);
                Signal& sSel = circuit.sig(sel);

                auto* p = new MuxProcess(sA, sB, sSel, sOut);
                sA.addSensitiveProcess(p);
                sB.addSensitiveProcess(p);
                sSel.addSensitiveProcess(p);
                circuit.processes.emplace_back(p);

            } else if (keyword == "dff") {
                string q_not, clk, d;
                if (!(ss >> out >> q_not >> clk >> d))
                    throw runtime_error("Line " + to_string(line_num) +
                        ": dff needs: <q> <q_not> <clk> <d>");

                warnDriver(out);
                warnDriver(q_not);
                Signal& sQ    = circuit.sig(out);
                Signal& sQnot = circuit.sig(q_not);
                Signal& sClk  = circuit.sig(clk);
                Signal& sD    = circuit.sig(d);

                auto* p = new DFlipFlopProcess(sClk, sD, sQ, sQnot);
                sClk.addSensitiveProcess(p);
                circuit.processes.emplace_back(p);

            } else if (keyword == "sr") {
                string q_not, s, r;
                if (!(ss >> out >> q_not >> s >> r))
                    throw runtime_error("Line " + to_string(line_num) +
                        ": sr needs: <q> <q_not> <s> <r>");

                warnDriver(out);
                warnDriver(q_not);
                Signal& sQ    = circuit.sig(out);
                Signal& sQnot = circuit.sig(q_not);
                Signal& sS    = circuit.sig(s);
                Signal& sR    = circuit.sig(r);

                auto* p = new SRLatchProcess(sS, sR, sQ, sQnot);
                sS.addSensitiveProcess(p);
                sR.addSensitiveProcess(p);
                circuit.processes.emplace_back(p);

            } else {
                // two-input gates: and, or, xor, nand, nor, xnor
                if (!(ss >> out >> a >> b))
                    throw runtime_error("Line " + to_string(line_num) +
                        ": " + keyword + " needs: <out> <a> <b>");

                warnDriver(out);
                Signal& sOut = circuit.sig(out);
                Signal& sA   = circuit.sig(a);
                Signal& sB   = circuit.sig(b);

                Process* p = nullptr;
                if      (keyword == "and")  p = new AndProcess (sA, sB, sOut);
                else if (keyword == "or")   p = new OrProcess  (sA, sB, sOut);
                else if (keyword == "xor")  p = new XorProcess (sA, sB, sOut);
                else if (keyword == "nand") p = new NandProcess(sA, sB, sOut);
                else if (keyword == "nor")  p = new NorProcess (sA, sB, sOut);
                else if (keyword == "xnor") p = new XnorProcess(sA, sB, sOut);
                else throw runtime_error("Line " + to_string(line_num) +
                        ": unknown gate type '" + keyword + "'");

                sA.addSensitiveProcess(p);
                sB.addSensitiveProcess(p);
                circuit.processes.emplace_back(p);
            }
        }

        return circuit;
    }
};

#endif
