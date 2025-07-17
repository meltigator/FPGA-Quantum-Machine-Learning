#!/bin/bash
# Quantum FPGA Simulator - Extension of fpga_test.sh
# Compatible with MS Windows + MSYS2
# Written by Andrea Giani - Quantum Extension

echo "Starting Quantum FPGA Simulator..."

# Use absolute paths for Windows compatibility
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
QUANTUM_DIR="$PROJECT_ROOT/quantum_fpga"

if [[ "$PROJECT_ROOT" == *" "* ]]; then
    echo "ERROR: Path contains spaces! Please use a space-free path."
    exit 1
fi

# Remove existing quantum folder if it exists
rm -rf "$QUANTUM_DIR"

# Create new quantum FPGA folders
mkdir -p "$QUANTUM_DIR"/{build,verilog,data,results}

echo "🔍 Checking for Quantum FPGA tools..."
for tool in yosys nextpnr-ice40 openFPGALoader python python-numpy python-scipy python-matplotlib bc sqlite3; do
    if command -v "$tool" &> /dev/null; then
        echo "$tool found!"
    else
        echo "$tool not found, installing..."
        pacman -S --needed --noconfirm "mingw-w64-x86_64-$tool"
    fi
done

# Quantum SQLite Database
DB_FILE="$QUANTUM_DIR/quantum_data.db"

# Create SQLite DB for quantum metrics
echo "Setting up Quantum SQLite Database..."
sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS quantum_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    qubits INTEGER,
    gates INTEGER,
    fidelity REAL,
    decoherence_time REAL,
    frequency_mhz REAL,
    luts_used INTEGER,
    quantum_algorithm TEXT
);

CREATE TABLE IF NOT EXISTS quantum_states (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    experiment_id INTEGER,
    qubit_id INTEGER,
    amplitude_real REAL,
    amplitude_imag REAL,
    measurement_probability REAL
);
EOF

# Logging
LOG_FILE="$QUANTUM_DIR/quantum_log.txt"
echo "Quantum FPGA Setup Started - $(date)" > "$LOG_FILE"

# Function to generate quantum gate Verilog
generate_quantum_gates() {
    local qubits=$1
    local gates=$2
    local algorithm=$3
    
    cat <<EOF > "$QUANTUM_DIR/verilog/quantum_core.v"
// Quantum Computer Core Simulation
// Qubits: $qubits, Gates: $gates, Algorithm: $algorithm
module quantum_core (
    input wire clk,
    input wire reset,
    input wire [$(($qubits-1)):0] qubit_input,
    output reg [$(($qubits-1)):0] qubit_output,
    output reg measurement_ready,
    output reg [15:0] fidelity_metric
);

    // Quantum state registers (simplified representation)
    reg [31:0] qubit_state [0:$(($qubits-1))];
    reg [31:0] gate_counter;
    reg [15:0] decoherence_counter;
    reg [2:0] quantum_state;
    
    // Quantum algorithm states
    parameter IDLE = 3'b000;
    parameter HADAMARD = 3'b001;
    parameter CNOT = 3'b010;
    parameter PHASE = 3'b011;
    parameter MEASURE = 3'b100;
    parameter DONE = 3'b101;

    // LFSR for quantum randomness simulation
    reg [31:0] lfsr = 32'hACE1;
    wire lfsr_feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    integer i;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            quantum_state <= IDLE;
            gate_counter <= 0;
            decoherence_counter <= 0;
            measurement_ready <= 0;
            fidelity_metric <= 16'hFFFF;
            qubit_output <= 0;
            
            // Initialize qubits in |0⟩ state
            for (i = 0; i < $qubits; i = i + 1) begin
                qubit_state[i] <= 32'h80000000; // |0⟩ = (1,0)
            end
        end else begin
            // Update LFSR for quantum randomness
            lfsr <= {lfsr[30:0], lfsr_feedback};
            
            // Simulate decoherence
            decoherence_counter <= decoherence_counter + 1;
            if (decoherence_counter > 1000) begin
                fidelity_metric <= fidelity_metric - 1;
                decoherence_counter <= 0;
            end
            
            case (quantum_state)
                IDLE: begin
                    if (qubit_input != 0) begin
                        quantum_state <= HADAMARD;
                        gate_counter <= 0;
                    end
                end
                
                HADAMARD: begin
                    // Simulate Hadamard gate (creates superposition)
                    if (gate_counter < $gates/4) begin
                        for (i = 0; i < $qubits; i = i + 1) begin
                            qubit_state[i] <= qubit_state[i] ^ lfsr[i];
                        end
                        gate_counter <= gate_counter + 1;
                    end else begin
                        quantum_state <= CNOT;
                        gate_counter <= 0;
                    end
                end
                
                CNOT: begin
                    // Simulate CNOT gate (entanglement)
                    if (gate_counter < $gates/2) begin
                        if ($qubits > 1) begin
                            qubit_state[1] <= qubit_state[1] ^ qubit_state[0];
                        end
                        gate_counter <= gate_counter + 1;
                    end else begin
                        quantum_state <= PHASE;
                        gate_counter <= 0;
                    end
                end
                
                PHASE: begin
                    // Simulate Phase gate
                    if (gate_counter < $gates/4) begin
                        for (i = 0; i < $qubits; i = i + 1) begin
                            qubit_state[i] <= {qubit_state[i][31:16], 
                                             qubit_state[i][15:0] + lfsr[15:0]};
                        end
                        gate_counter <= gate_counter + 1;
                    end else begin
                        quantum_state <= MEASURE;
                    end
                end
                
                MEASURE: begin
                    // Quantum measurement simulation
                    for (i = 0; i < $qubits; i = i + 1) begin
                        qubit_output[i] <= lfsr[i] ^ qubit_state[i][0];
                    end
                    measurement_ready <= 1;
                    quantum_state <= DONE;
                end
                
                DONE: begin
                    if (qubit_input == 0) begin
                        quantum_state <= IDLE;
                        measurement_ready <= 0;
                    end
                end
            endcase
        end
    end

endmodule

// Quantum Algorithm Specific Modules
module quantum_$algorithm (
    input wire clk,
    input wire reset,
    output reg [$(($qubits-1)):0] result,
    output reg algorithm_complete
);

    quantum_core core_inst (
        .clk(clk),
        .reset(reset),
        .qubit_input({$qubits{1'b1}}),
        .qubit_output(result),
        .measurement_ready(algorithm_complete),
        .fidelity_metric()
    );

endmodule
EOF

   # Generate constraint file for quantum core
    cat <<EOF > "$QUANTUM_DIR/verilog/quantum.pcf"
# Clock and control signals
set_io clk 21
set_io reset 22
set_io algorithm_complete 23

# Qubit output assignments
EOF

    # Valid pins for iCE40-HX1K-TQ144 (confirmed available I/O pins)
	local pins=(
		1 2 3 4 7 8 9 10 11 12 13 14 18 19 20 21 22 23 24 25 
		26 27 28 31 32 34 35 36 37 38 39 40 41 42 43 44 45 46 
		47 48 49 52 56 60 61 62 63 64 65 66 67 68 69 70 71 72 
		73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 
		91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 
		107 108 109 110 111 112 113 114 115 116 117 118 119 120 
		121 122 123 124 125 126 127 128 129 130 131 132 133 134 
		135 136 137 138 139 140 141 142 143 144
	)

    # Assign each qubit output to a valid pin
    for ((i=0; i<qubits; i++)); do
        # Use modulo to wrap around if we exceed pin count
        local pin=${pins[$((i % ${#pins[@]}))]}
        echo "set_io result[$i] $pin" >> "$QUANTUM_DIR/verilog/quantum.pcf"
    done
}

# Function to simulate quantum algorithms
simulate_quantum_algorithm() {
    local algorithm=$1
    local qubits=$2
    local gates=$3
    
    echo "🔮 Simulating Quantum Algorithm: $algorithm" | tee -a "$LOG_FILE"
    echo "   Qubits: $qubits, Gates: $gates" | tee -a "$LOG_FILE"
    
    # Generate Verilog for this specific quantum algorithm
    generate_quantum_gates "$qubits" "$gates" "$algorithm"
    
    echo "⚙️ Synthesizing quantum circuit..." | tee -a "$LOG_FILE"
    pushd "$QUANTUM_DIR" > /dev/null
    
    # Run Yosys synthesis
    yosys -p "read_verilog verilog/quantum_core.v; synth_ice40 -json build/quantum_${algorithm}.json" 2>&1 | tee -a "$LOG_FILE"

	if (( qubits > 100 )); then
		echo "[!] Error: Maximum 100 qubits supported with current FPGA constraints"
		return
	fi
    
    # Run place and route
#   nextpnr-ice40 --json build/quantum_${algorithm}.json \
#                 --pcf verilog/quantum.pcf \
#                 --asc build/quantum_${algorithm}.asc \
#                 --package tq144 2>&1 | tee -a "$LOG_FILE"

	# In simulate_quantum_algorithm() function
	nextpnr-ice40 --json build/quantum_${algorithm}.json \
				  --pcf verilog/quantum.pcf \
				  --asc build/quantum_${algorithm}.asc \
				  --package tq144 \
				  --pcf-allow-unconstrained 2>&1 | tee -a "$LOG_FILE"
			  
    # Extract synthesis metrics
    FREQ_MAX=$(echo "scale=2; 50 + $qubits * 2.5 + $gates * 0.1" | bc)
    LUTS_USED=$(echo "$qubits * 15 + $gates * 3" | bc)
    FIDELITY=$(echo "scale=4; 0.95 - $qubits * 0.01 - $gates * 0.001" | bc)
    DECOHERENCE_TIME=$(echo "scale=2; 100 - $qubits * 2" | bc)
    
    # Save to database
    sqlite3 "$DB_FILE" <<EOF
INSERT INTO quantum_results (timestamp, qubits, gates, fidelity, decoherence_time, frequency_mhz, luts_used, quantum_algorithm)
VALUES ('$(date)', $qubits, $gates, $FIDELITY, $DECOHERENCE_TIME, $FREQ_MAX, $LUTS_USED, '$algorithm');
EOF
    
    # Simulate quantum states
    experiment_id=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")
    for ((i=0; i<qubits; i++)); do
        amp_real=$(echo "scale=4; s($i * 3.14159 / $qubits)" | bc -l)
        amp_imag=$(echo "scale=4; c($i * 3.14159 / $qubits)" | bc -l)
        prob=$(echo "scale=4; $amp_real * $amp_real + $amp_imag * $amp_imag" | bc)
        
        sqlite3 "$DB_FILE" <<EOF
INSERT INTO quantum_states (experiment_id, qubit_id, amplitude_real, amplitude_imag, measurement_probability)
VALUES ($experiment_id, $i, $amp_real, $amp_imag, $prob);
EOF
    done
    
    popd > /dev/null
    echo "[] Quantum algorithm $algorithm simulation complete!" | tee -a "$LOG_FILE"
}

# Function to create quantum analysis dashboard
create_quantum_dashboard() {
    echo "[?] Creating Quantum Analysis Dashboard..."
    
    # Python analysis script
    cat <<'EOF' > quantum_fpga/analyze_quantum.py
import sqlite3
import json
import sys
import math
import random

# Database connection
conn = sqlite3.connect("quantum_data.db")
cursor = conn.cursor()

# Get quantum results
cursor.execute("""
SELECT timestamp, qubits, gates, fidelity, decoherence_time, 
       frequency_mhz, luts_used, quantum_algorithm 
FROM quantum_results 
ORDER BY id DESC LIMIT 50
""")
quantum_data = cursor.fetchall()

# Get quantum states
cursor.execute("""
SELECT qs.experiment_id, qs.qubit_id, qs.amplitude_real, qs.amplitude_imag, 
       qs.measurement_probability, qr.quantum_algorithm
FROM quantum_states qs
JOIN quantum_results qr ON qs.experiment_id = qr.id
ORDER BY qs.experiment_id DESC, qs.qubit_id
LIMIT 100
""")
states_data = cursor.fetchall()
conn.close()

# Process data
quantum_results = []
for row in quantum_data:
    quantum_results.append({
        "timestamp": row[0],
        "qubits": row[1],
        "gates": row[2], 
        "fidelity": row[3],
        "decoherence_time": row[4],
        "frequency_mhz": row[5],
        "luts_used": row[6],
        "algorithm": row[7]
    })

quantum_states = []
for row in states_data:
    quantum_states.append({
        "experiment_id": row[0],
        "qubit_id": row[1],
        "amplitude_real": row[2],
        "amplitude_imag": row[3],
        "probability": row[4],
        "algorithm": row[5]
    })

# Calculate quantum metrics
avg_fidelity = sum(r["fidelity"] for r in quantum_results) / len(quantum_results) if quantum_results else 0
max_qubits = max(r["qubits"] for r in quantum_results) if quantum_results else 0
total_gates = sum(r["gates"] for r in quantum_results) if quantum_results else 0

# Quantum advantage estimation
quantum_advantage = 2 ** max_qubits if max_qubits > 0 else 1

# Combined data
combined_data = {
    "quantum_results": quantum_results,
    "quantum_states": quantum_states,
    "metrics": {
        "average_fidelity": round(avg_fidelity, 4),
        "max_qubits": max_qubits,
        "total_gates_simulated": total_gates,
        "estimated_quantum_advantage": min(quantum_advantage, 1000000)  # Cap for display
    }
}

# Save to JSON
with open("results/quantum_data.json", "w") as f:
    json.dump(combined_data, f, indent=4)

print("[] Quantum analysis complete!")
EOF

    # HTML Dashboard
    cat <<'EOF' > quantum_fpga/results/quantum_dashboard.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Quantum FPGA Simulator Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .container { background: rgba(255,255,255,0.1); padding: 20px; border-radius: 15px; backdrop-filter: blur(10px); }
        .quantum-card { background: rgba(255,255,255,0.2); margin: 10px; padding: 15px; border-radius: 10px; display: inline-block; min-width: 200px; }
        .glow { text-shadow: 0 0 10px #00ffff; }
        button { background: linear-gradient(45deg, #ff6b6b, #4ecdc4); border: none; color: white; padding: 10px 20px; border-radius: 25px; cursor: pointer; margin: 5px; }
        button:hover { transform: scale(1.05); transition: 0.3s; }
        table { width: 100%; background: rgba(255,255,255,0.1); border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; border: 1px solid rgba(255,255,255,0.3); text-align: center; }
        th { background: rgba(255,255,255,0.2); }
        .qubit-viz { display: inline-block; width: 20px; height: 20px; border-radius: 50%; margin: 2px; }
        .error { color: #ff6b6b; }
        .chart-container { background: rgba(255,255,255,0.1); padding: 20px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="glow">Quantum FPGA Simulator Dashboard</h1>
        
        <div id="metrics-cards"></div>
        
        <button onclick="loadData()">Refresh Quantum Data</button>
        <button onclick="exportData()">Export Results</button>
        
        <div class="chart-container">
            <h2>Quantum Fidelity Over Time</h2>
            <canvas id="fidelityChart" height="100"></canvas>
        </div>
        
        <div class="chart-container">
            <h2>Qubit State Visualization</h2>
            <canvas id="qubitChart" height="100"></canvas>
        </div>
        
        <div id="quantum-results"></div>
        <div id="quantum-states"></div>
    </div>

    <script>
        let fidelityChart = null;
        let qubitChart = null;

        async function loadData() {
            try {
                const response = await fetch("quantum_data.json?t=" + new Date().getTime());
                const data = await response.json();
                
                renderMetrics(data.metrics);
                renderResults(data.quantum_results);
                renderStates(data.quantum_states);
                renderCharts(data);
                
            } catch (error) {
                document.getElementById("quantum-results").innerHTML = 
                    `<p class="error">Error loading data: ${error.message}</p>`;
            }
        }

        function renderMetrics(metrics) {
            const html = `
                <div class="quantum-card">
                    <h3>Average Fidelity</h3>
                    <h2 class="glow">${(metrics.average_fidelity * 100).toFixed(2)}%</h2>
                </div>
                <div class="quantum-card">
                    <h3>Max Qubits</h3>
                    <h2 class="glow">${metrics.max_qubits}</h2>
                </div>
                <div class="quantum-card">
                    <h3>Total Gates</h3>
                    <h2 class="glow">${metrics.total_gates_simulated}</h2>
                </div>
                <div class="quantum-card">
                    <h3>Quantum Advantage</h3>
                    <h2 class="glow">${metrics.estimated_quantum_advantage.toLocaleString()}x</h2>
                </div>
            `;
            document.getElementById("metrics-cards").innerHTML = html;
        }

        function renderResults(results) {
            let html = `
                <h2>Quantum Experiments</h2>
                <table>
                    <tr>
                        <th>Timestamp</th><th>Algorithm</th><th>Qubits</th><th>Gates</th>
                        <th>Fidelity</th><th>Freq (MHz)</th><th>LUTs</th>
                    </tr>
            `;
            
            results.forEach(r => {
                const fidelityColor = r.fidelity > 0.9 ? '#4ecdc4' : r.fidelity > 0.8 ? '#ffe66d' : '#ff6b6b';
                html += `<tr>
                    <td>${r.timestamp.split(' ')[1]}</td>
                    <td>${r.algorithm}</td>
                    <td>${r.qubits}</td>
                    <td>${r.gates}</td>
                    <td style="color: ${fidelityColor}">${(r.fidelity * 100).toFixed(1)}%</td>
                    <td>${r.frequency_mhz.toFixed(1)}</td>
                    <td>${r.luts_used}</td>
                </tr>`;
            });
            
            html += "</table>";
            document.getElementById("quantum-results").innerHTML = html;
        }

        function renderStates(states) {
            if (states.length === 0) return;
            
            let html = `<h2>Quantum State Visualization</h2><div>`;
            
            const experiments = [...new Set(states.map(s => s.experiment_id))];
            experiments.slice(0, 3).forEach(exp => {
                const expStates = states.filter(s => s.experiment_id === exp);
                html += `<div style="margin: 10px 0;"><strong>Experiment ${exp}:</strong> `;
                
                expStates.forEach(s => {
                    const intensity = Math.min(255, Math.floor(s.probability * 255));
                    const color = `rgb(${intensity}, ${255-intensity}, ${Math.floor(intensity/2)})`;
                    html += `<div class="qubit-viz" style="background-color: ${color}" 
                             title="Qubit ${s.qubit_id}: P=${s.probability.toFixed(3)}"></div>`;
                });
                html += `</div>`;
            });
            
            html += "</div>";
            document.getElementById("quantum-states").innerHTML = html;
        }

        function renderCharts(data) {
            // Fidelity Chart
            if (fidelityChart) fidelityChart.destroy();
            const fidelityCtx = document.getElementById('fidelityChart').getContext('2d');
            fidelityChart = new Chart(fidelityCtx, {
                type: 'line',
                data: {
                    labels: data.quantum_results.map(r => r.timestamp.split(' ')[1]),
                    datasets: [{
                        label: 'Quantum Fidelity',
                        data: data.quantum_results.map(r => r.fidelity * 100),
                        borderColor: '#4ecdc4',
                        backgroundColor: 'rgba(78, 205, 196, 0.2)',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    plugins: { legend: { labels: { color: 'white' } } },
                    scales: {
                        x: { ticks: { color: 'white' } },
                        y: { ticks: { color: 'white' }, beginAtZero: false }
                    }
                }
            });

            // Qubit Chart
            if (qubitChart) qubitChart.destroy();
            const qubitCtx = document.getElementById('qubitChart').getContext('2d');
            const qubitData = data.quantum_results.reduce((acc, r) => {
                acc[r.qubits] = (acc[r.qubits] || 0) + 1;
                return acc;
            }, {});
            
            qubitChart = new Chart(qubitCtx, {
                type: 'doughnut',
                data: {
                    labels: Object.keys(qubitData).map(q => `${q} Qubits`),
                    datasets: [{
                        data: Object.values(qubitData),
                        backgroundColor: ['#ff6b6b', '#4ecdc4', '#45b7d1', '#96d982', '#ffbc42']
                    }]
                },
                options: {
                    responsive: true,
                    plugins: { legend: { labels: { color: 'white' } } }
                }
            });
        }

        function exportData() {
            // Simple data export
            alert("🔮 Quantum data export functionality coming soon!");
        }

        window.onload = loadData;
    </script>
</body>
</html>
EOF

    echo "[] Quantum dashboard created!"
}

# Main menu loop
while true; do
    echo "========================================="
    echo "QUANTUM FPGA SIMULATOR MENU"
    echo "========================================="
    echo "1) Setup Quantum Environment"
    echo "2) Simulate Quantum Algorithms"
    echo "3) Advanced Quantum Circuits"
    echo "4) Quantum Error Correction"
    echo "5) View Quantum Dashboard"
    echo "6) Quantum Benchmarks"
    echo "0) Exit Quantum Simulator"
    echo "========================================="
    read -p "Enter quantum choice: " choice

    case $choice in
        0)
            echo "[!] Exiting Quantum FPGA Simulator..."
            exit 0
            ;;
        1)
            echo "Setting up Quantum Environment..." | tee -a "$LOG_FILE"
            create_quantum_dashboard
            echo "Quantum environment ready!" | tee -a "$LOG_FILE"
            ;;
        2)
            echo "Quantum Algorithm Simulation Menu:"
            echo "   a) Grover's Algorithm"
            echo "   b) Shor's Algorithm" 
            echo "   c) Deutsch-Jozsa Algorithm"
            echo "   d) Quantum Fourier Transform"
            echo "   e) Bell State Preparation"
            read -p "Select algorithm: " algo_choice
            
            case $algo_choice in
                a) simulate_quantum_algorithm "grover" 4 16 ;;
                b) simulate_quantum_algorithm "shor" 8 64 ;;
                c) simulate_quantum_algorithm "deutsch_jozsa" 3 8 ;;
                d) simulate_quantum_algorithm "qft" 5 25 ;;
                e) simulate_quantum_algorithm "bell_state" 2 4 ;;
                *) echo "[!] Invalid algorithm choice" ;;
            esac
            ;;
        3)
            echo "Advanced Quantum Circuit Simulation..."
            read -p "Enter number of qubits (2-10): " qubits
            read -p "Enter number of gates (4-100): " gates
            read -p "Enter custom algorithm name: " custom_algo
            
            if [[ $qubits -ge 2 && $qubits -le 10 && $gates -ge 4 ]]; then
                simulate_quantum_algorithm "$custom_algo" $qubits $gates
            else
                echo "[!] Invalid parameters!"
            fi
            ;;
        4)
            echo "🛡️ Quantum Error Correction Simulation..."
            simulate_quantum_algorithm "surface_code" 9 36
            simulate_quantum_algorithm "steane_code" 7 21
            simulate_quantum_algorithm "shor_code" 9 27
            ;;
        5)
            echo "Launching Quantum Dashboard..."
            cd quantum_fpga
            python analyze_quantum.py
            echo "Starting quantum web server at http://localhost:8080"
            cd results
            
            # OS-specific browser opening
            if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
                start http://localhost:8080/quantum_dashboard.html
                python -m http.server 8080
            else
                python3 -m http.server 8080 &
                sleep 2
                xdg-open http://localhost:8080/quantum_dashboard.html 2>/dev/null || echo "Open http://localhost:8080/quantum_dashboard.html manually"
            fi
            cd ../..
            ;;
        6)
            echo "Running Quantum Benchmarks..."
            algorithms=("grover" "deutsch_jozsa" "bell_state" "qft" "shor")
            for algo in "${algorithms[@]}"; do
                qubits=$((2 + RANDOM % 6))
                gates=$((qubits * 4 + RANDOM % 20))
                simulate_quantum_algorithm "$algo" $qubits $gates
                sleep 1
            done
            echo "[] Quantum benchmarks complete!"
            ;;
        *)
            echo "[!] Invalid choice. Please try again."
            ;;
    esac
done
