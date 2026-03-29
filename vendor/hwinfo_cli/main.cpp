#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include "hwinfo/hwinfo.h"

// Simple JSON escaping
static std::string escape_json(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out += c; break;
        }
    }
    return out;
}

static std::string q(const std::string& s) { return "\"" + escape_json(s) + "\""; }

int main() {
    std::ostringstream json;
    json << "{\n";

    // --- CPU ---
    json << "  \"cpu\": [";
    auto cpus = hwinfo::getAllCPUs();
    
    // Deduplicate CPUs that are exactly the same (hyperthreading / multi-core artifacts in some hwinfo versions)
    struct CPUKey {
        std::string model;
        std::string vendor;
        int physical_cores;
        int logical_cores;
        int max_clock;
        long long cache_size;
        
        bool operator==(const CPUKey& other) const {
            return model == other.model && vendor == other.vendor &&
                   physical_cores == other.physical_cores &&
                   logical_cores == other.logical_cores &&
                   max_clock == other.max_clock &&
                   cache_size == other.cache_size;
        }
    };
    
    std::vector<CPUKey> unique_cpus;
    
    for (size_t i = 0; i < cpus.size(); ++i) {
        auto& c = cpus[i];
        CPUKey key{
            c.modelName(),
            c.vendor(),
            c.numPhysicalCores(),
            c.numLogicalCores(),
            (int)c.maxClockSpeed_MHz(),
            c.L3CacheSize_Bytes()
        };
        
        bool is_duplicate = false;
        for (const auto& u : unique_cpus) {
            if (u == key) {
                is_duplicate = true;
                break;
            }
        }
        
        if (!is_duplicate) {
            unique_cpus.push_back(key);
            
            if (unique_cpus.size() > 1) json << ",";
            json << "\n    {"
                 << "\"model\": " << q(key.model)
                 << ", \"vendor\": " << q(key.vendor)
                 << ", \"cores_physical\": " << key.physical_cores
                 << ", \"cores_logical\": " << key.logical_cores
                 << ", \"max_clock_mhz\": " << key.max_clock
                 << ", \"cache_size_bytes\": " << key.cache_size
                 << "}";
        }
    }
    json << "\n  ],\n";

    // --- GPU ---
    json << "  \"gpu\": [";
    auto gpus = hwinfo::getAllGPUs();
    for (size_t i = 0; i < gpus.size(); ++i) {
        auto& g = gpus[i];
        if (i > 0) json << ",";
        json << "\n    {"
             << "\"name\": " << q(g.name())
             << ", \"vendor\": " << q(g.vendor())
             << ", \"memory_bytes\": " << g.memory_Bytes()
             << ", \"driver_version\": " << q(g.driverVersion())
             << "}";
    }
    json << "\n  ],\n";

    // --- RAM ---
    json << "  \"ram\": [";
    hwinfo::Memory ram;
    auto rams = ram.modules();
    for (size_t i = 0; i < rams.size(); ++i) {
        auto& r = rams[i];
        if (i > 0) json << ",";
        json << "\n    {"
             << "\"name\": " << q(r.name)
             << ", \"vendor\": " << q(r.vendor)
             << ", \"model\": " << q(r.model)
             << ", \"serial\": " << q(r.serial_number)
             << ", \"total_bytes\": " << r.total_Bytes
             << ", \"frequency_hz\": " << r.frequency_Hz
             << "}";
    }
    json << "\n  ],\n";

    // --- Disks ---
    json << "  \"disk\": [";
    auto disks = hwinfo::getAllDisks();
    for (size_t i = 0; i < disks.size(); ++i) {
        auto& d = disks[i];
        if (i > 0) json << ",";
        json << "\n    {"
             << "\"vendor\": " << q(d.vendor())
             << ", \"model\": " << q(d.model())
             << ", \"serial\": " << q(d.serialNumber())
             << ", \"size_bytes\": " << d.size_Bytes()
             << "}";
    }
    json << "\n  ],\n";

    // --- OS ---
    hwinfo::OS os;
    json << "  \"os\": {"
         << "\"name\": " << q(os.name())
         << ", \"version\": " << q(os.version())
         << ", \"kernel\": " << q(os.kernel())
         << ", \"architecture\": " << q(os.is32bit() ? "32-bit" : "64-bit")
         << ", \"architecture\": " << q(os.is32bit() ? "32-bit" : "64-bit")
         << "},\n";

    // --- Mainboard ---
    hwinfo::MainBoard mb;
    json << "  \"mainboard\": {"
         << "\"vendor\": " << q(mb.vendor())
         << ", \"name\": " << q(mb.name())
         << ", \"version\": " << q(mb.version())
         << ", \"serial\": " << q(mb.serialNumber())
         << "},\n";

    // --- Battery ---
    json << "  \"battery\": [";
    auto bats = hwinfo::getAllBatteries();
    for (size_t i = 0; i < bats.size(); ++i) {
        auto& b = bats[i];
        if (i > 0) json << ",";
        json << "\n    {"
             << "\"vendor\": " << q(b.vendor())
             << ", \"model\": " << q(b.model())
             << ", \"serial\": " << q(b.serialNumber())
             << ", \"technology\": " << q(b.technology())
             << ", \"charging\": " << (b.charging() ? "true" : "false")
             << ", \"capacity\": " << b.capacity()
             << "}";
    }
    json << "\n  ]\n";

    json << "}\n";

    std::cout << json.str();
    return 0;
}
