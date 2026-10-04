# QSPI Flash Controller (Winbond W25Q512JV 512-Mbit)

## 1. Project Overview
This project implements an RTL design for a QSPI Flash Controller, serving as a bridge between a System-on-Chip and an external Winbond W25Q512JV 512-Mbit flash memory. 

The architecture separates the Control-Plane and Data-Plane to maximize throughput and system stability. It leverages the AMBA APB protocol for static configuration and the AMBA AXI4-Stream protocol for high-speed, continuous data streaming.

## 2. System Architecture

![QSPI Flash Controller Architecture](qspi_flash.png)
*(Figure: Top-Level Architecture of the QSPI Flash Controller)*

## 3. Clock Domain Partitioning
To optimize system performance, the architecture is partitioned into three independent clock domains:
*   **APB Clock Domain (50 MHz):** Manages the Control-Plane. It controls the APB Slave FSM and the Register File, allowing the host CPU to set up transfer configurations and monitor hardware status.
*   **CTRL Clock Domain (133 MHz):** The core operational domain. It contains the main Control FSM responsible for sequencing flash commands, along with the QSPI PHY that physically drives the external flash pins.
*   **AXI Clock Domain (266 MHz):** Dedicated entirely to the high-speed Data-Plane via AXI4-Stream interfaces.

## 4. Key Design Methodologies: CDC & RDC
Operating across multiple asynchronous clock frequencies requires strict signal integrity. The design implements industry-standard Reset Domain Crossing (RDC) and Clock Domain Crossing (CDC) methodologies to prevent metastability and data corruption.

### 4.1. Reset Domain Crossing (RDC)
The system utilizes dedicated reset synchronizer blocks to enforce an "Asynchronous Assert, Synchronous Deassert" strategy. This ensures that while the entire controller can be reset instantly for safety, all internal state machines and physical interfaces exit the reset state cleanly and aligned with their respective clock edges, preventing timing violations during system boot.

### 4.2. Static Signal CDC (2-FF Synchronizers)
Slow-changing hardware status flags originating from the core operational domain are safely passed back to the slower APB control domain using standard 2-Flip-Flop synchronizers. This allows the host processor to continuously poll the controller's status without risking metastability on the system bus.

### 4.3. Command Trigger CDC (Pulse Synchronizers)
To prevent pulse loss when crossing command triggers between asynchronous domains—whether passing from a slow clock to a fast clock, or from a fast clock to a slow one—the design employs toggle-based pulse synchronizers. Single-cycle trigger pulses are converted into static toggles, safely crossed over the domain boundary, and reliably reconstructed back into pulses for the core logic to process.

### 4.4. Multi-bit CDC (Enable-Based Latching)
Standard synchronizers cannot be used for multi-bit configuration buses due to the risk of data incoherence. Instead, the design allows these APB-driven buses to completely stabilize. Once stable, a synchronized command trigger is used as an enable signal to securely latch a private, isolated copy of the data into the core logic, ensuring total data integrity during flash operations.

### 4.5. Data-Plane CDC (Asynchronous FIFOs)
To safely bridge the massive throughput gap between the high-speed AXI data domain and the control domain, custom Asynchronous FIFOs are deployed on both the read and write paths. These FIFOs utilize Gray-code pointers to safely cross domain boundaries, guaranteeing that FIFO full and empty states are evaluated accurately without ever corrupting the high-speed data stream.
