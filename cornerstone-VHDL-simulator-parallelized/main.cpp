#include "Simulator.hpp"
#include "Signal.hpp"
#include "DebugFlags.hpp"
#include "include/io_handlers/VCDWriter.hpp"
#include "include/io_handlers/StimParser.hpp"
#include "Stimulusprocess.hpp"
#include "include/io_handlers/NetlistParser.hpp"
#include "vhdl/VHDLCodeGen.hpp"
#include "src/print.cpp"

#include <iostream>
#include <fstream>
#include <cstdio>
#include <vector>
#include <string>
#include <sys/stat.h>
#define MKDIR(d) mkdir(d, 0755)
#include <sys/stat.h>
#include <chrono>

using namespace std;

// global debug flags (default: off)
namespace DebugFlags {
    bool show_net  = false;
    bool show_stim = false;
    bool show_dep  = false;
    bool show_sim  = false;
    bool seq_mode  = false;
}

// Bison/Flex interface
extern "C" {
    extern FILE *yyin;
    extern int yyparse(void);
    extern VHDLDesign *vhdl_root;
}


int main(int argc, char* argv[]) {
    auto t_start = chrono::high_resolution_clock::now();

    if (argc < 2) {
        cout << "Usage:\n";
        cout << "  ./simulator <circuit.vhd> [output.vcd] [flags]\n";
        cout << "  ./simulator <circuit.net> <stimulus.stim> [output.vcd] [flags]\n";
        cout << "\nFlags: -dep -net -stim -sim -seq -all\n";
        return 1;
    }

    // separate flags from file paths
    vector<string> positional_args;

    for (int i = 1; i < argc; i++) {
        string arg = argv[i];

        if (arg == "-dep")       DebugFlags::show_dep = true;
        else if (arg == "-net")  DebugFlags::show_net = true;
        else if (arg == "-stim") DebugFlags::show_stim = true;
        else if (arg == "-sim")  DebugFlags::show_sim = true;
        else if (arg == "-seq")  DebugFlags::seq_mode = true;
        else if (arg == "-all") {
            DebugFlags::show_dep  = true;
            DebugFlags::show_net  = true;
            DebugFlags::show_stim = true;
            DebugFlags::show_sim  = true;
        } else {
            positional_args.push_back(arg);
        }
    }

    if (positional_args.empty()) {
        cerr << "Error: no input file specified.\n";
        return 1;
    }

    string net_file, stim_file, vcd_file;
    string tmp_net_path, tmp_stim_path;
    bool vhd_mode = endsWith(positional_args[0], ".vhd");

    if (vhd_mode) {
        // VHDL flow: parse .vhd -> generate .net/.stim -> simulate
        string vhd_file = positional_args[0];
        vcd_file = (positional_args.size() > 1) ? positional_args[1] : "output.vcd";

        cout << "\n[Parsing VHDL: " << vhd_file << "]\n";

        FILE *f = fopen(vhd_file.c_str(), "r");
        if (!f) {
            cerr << "Error: cannot open " << vhd_file << "\n";
            return 1;
        }
        yyin = f;
        int parse_result = yyparse();
        fclose(f);

        if (parse_result != 0 || !vhdl_root) {
            cerr << "Error: VHDL parsing failed\n";
            return 1;
        }

        cout << "[Parsed OK: entity=" << vhdl_root->entity_name << "]\n";

        CodeGenResult gen = VHDLCodeGen::generate(vhdl_root);
        cout << "[CodeGen OK]\n";

        // extract base filename
        string basename = vhd_file;
        size_t slash = basename.find_last_of('/');
        if (slash != string::npos) basename = basename.substr(slash + 1);
        basename = basename.substr(0, basename.size() - 4);

        tmp_net_path  = "generated/" + basename + ".net";
        tmp_stim_path = "generated/" + basename + ".stim";

        MKDIR("generated");

        ofstream net_out(tmp_net_path);
        if (!net_out.is_open()) {
            cerr << "Error: cannot write to " << tmp_net_path << "\n";
            return 1;
        }
        net_out << gen.net_content;
        net_out.close();

        ofstream stim_out(tmp_stim_path);
        if (!stim_out.is_open()) {
            cerr << "Error: cannot write to " << tmp_stim_path << "\n";
            return 1;
        }
        stim_out << gen.stim_content;
        stim_out.close();

        net_file  = tmp_net_path;
        stim_file = tmp_stim_path;

        vhdl_design_free(vhdl_root);
        vhdl_root = nullptr;

    } else {
        // Netlist flow: .net + .stim directly
        if (positional_args.size() < 2) {
            cout << "Usage: ./simulator <circuit.net> <stimulus.stim> [output.vcd]\n";
            return 1;
        }
        net_file  = positional_args[0];
        stim_file = positional_args[1];
        vcd_file  = (positional_args.size() > 2) ? positional_args[2] : "output.vcd";
    }

    
        Circuit circuit = NetlistParser::load(net_file);

        if (DebugFlags::show_net) printNetlist(circuit);

        // build signal name map for stimulus parser
        map<string, Signal*> sig_map;
        for (const auto& kv : circuit.signals)
            sig_map[kv.first] = kv.second.get();

        // set up VCD writer
        VCDWriter vcd(vcd_file, "1ns");
        for (auto* s : circuit.signal_order) vcd.registerSignal(*s);
        vcd.writeHeader(circuit.signal_order, "sim");

        // set up simulator
        Simulator sim;
        sim.attachVCD(&vcd);

        for (const auto& kv : circuit.signals)
            sim.addSignal(kv.second.get());

        for (const auto& p : circuit.processes)
            sim.addProcess(p.get());

        // load stimulus
        vector<StimulusProcess*> owned_stimuli;
        StimParser::load(stim_file, sig_map, sim, owned_stimuli);

        if (DebugFlags::show_stim) printStimulus(owned_stimuli);

        sim.buildDependencyGraph();

        if (DebugFlags::show_dep) printLayers(sim.getLayers());

        
        sim.run(DebugFlags::seq_mode);
        
       
        cout << "VCD written to: " << vcd_file << "\n";

        for (auto* s : owned_stimuli) delete s;

        if (vhd_mode) {
            cout << "Generated: " << tmp_net_path << "\n";
            cout << "Generated: " << tmp_stim_path << "\n";
        }

        auto t_end = chrono::high_resolution_clock::now();
        chrono::duration<double> elapsed = t_end - t_start;
         cout << "Simulation time: " << elapsed.count() << " s\n";


    return 0;
}
// main.cpp — Entry point for the VHDL simulator
//
// Two modes:
//   ./simulator circuit.vhd [output.vcd] [flags]
//   ./simulator circuit.net circuit.stim [output.vcd] [flags]