-- ============================================================================
-- Predictive Maintenance Platform - Table Definitions
-- ============================================================================
-- This script creates all core data tables.
-- Run with: snow --config-file .\config.toml sql -f sql\02_tables.sql
-- ============================================================================

-- Use the correct schema
USE SCHEMA PREDICTIVE_MAINTENANCE.CORE;

-- ============================================================================
-- Equipment_Master Table
-- ============================================================================
-- Primary registry for all equipment being monitored
-- Task 2.1 - Requirements: 1.1
-- ============================================================================
CREATE OR REPLACE TABLE Equipment_Master (
    equipment_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    equipment_type VARCHAR(50) NOT NULL,  -- pump, motor, compressor
    location VARCHAR(100),
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    is_active BOOLEAN DEFAULT TRUE
);

-- Placeholder for additional tables
-- Tables will be added in subsequent tasks


-- ============================================================================
-- Maintenance_Logs Table
-- ============================================================================
-- Historical maintenance records for equipment
-- Task 2.4 - Requirements: 2.2
-- ============================================================================
CREATE OR REPLACE TABLE Maintenance_Logs (
    log_id VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    equipment_id VARCHAR(50) NOT NULL,
    maintenance_type VARCHAR(50) NOT NULL,  -- Preventive, Corrective, Emergency
    technician VARCHAR(100),
    start_time TIMESTAMP_NTZ NOT NULL,
    end_time TIMESTAMP_NTZ,
    description VARCHAR(2000),
    CONSTRAINT fk_ml_equipment FOREIGN KEY (equipment_id) 
        REFERENCES Equipment_Master(equipment_id)
);


-- ============================================================================
-- Sensor_Readings Table
-- ============================================================================
-- Raw sensor data from equipment with time-series readings
-- Task 2.2 - Requirements: 1.2, 1.3
-- ============================================================================
CREATE OR REPLACE TABLE Sensor_Readings (
    reading_id VARCHAR(50) DEFAULT UUID_STRING(),
    equipment_id VARCHAR(50) NOT NULL,
    sensor_type VARCHAR(50) NOT NULL,  -- vibration, temperature, rpm
    reading_timestamp TIMESTAMP_NTZ NOT NULL,
    sensor_value FLOAT NOT NULL,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT fk_equipment FOREIGN KEY (equipment_id) 
        REFERENCES Equipment_Master(equipment_id)
) CLUSTER BY (DATE(reading_timestamp), equipment_id);


-- ============================================================================
-- Work_Orders Table
-- ============================================================================
-- Tracks maintenance work orders for equipment
-- Task 2.3 - Requirements: 2.1, 2.3
-- ============================================================================
CREATE OR REPLACE TABLE Work_Orders (
    work_order_id VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    equipment_id VARCHAR(50) NOT NULL,
    description VARCHAR(1000),
    priority VARCHAR(20) NOT NULL,  -- Low, Medium, High, Critical
    status VARCHAR(20) NOT NULL DEFAULT 'Open',  -- Open, In Progress, Completed, Cancelled
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    scheduled_date TIMESTAMP_NTZ,
    completed_at TIMESTAMP_NTZ,
    source VARCHAR(50) DEFAULT 'Manual',  -- Manual, Prediction, Alert
    CONSTRAINT fk_wo_equipment FOREIGN KEY (equipment_id) 
        REFERENCES Equipment_Master(equipment_id),
    CONSTRAINT chk_status CHECK (status IN ('Open', 'In Progress', 'Completed', 'Cancelled'))
);


-- ============================================================================
-- Predictions Table
-- ============================================================================
-- Failure predictions for equipment based on ML analysis
-- Task 2.6 - Requirements: 5.2
-- ============================================================================
CREATE OR REPLACE TABLE Predictions (
    prediction_id VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    equipment_id VARCHAR(50) NOT NULL,
    failure_probability FLOAT NOT NULL,
    predicted_failure_start TIMESTAMP_NTZ,
    predicted_failure_end TIMESTAMP_NTZ,
    contributing_factors ARRAY,
    generated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT fk_pr_equipment FOREIGN KEY (equipment_id) 
        REFERENCES Equipment_Master(equipment_id),
    CONSTRAINT chk_probability CHECK (failure_probability > 0 AND failure_probability <= 100)
);


-- ============================================================================
-- Anomalies Table
-- ============================================================================
-- Stores detected anomalies from sensor data analysis
-- Task 2.5 - Requirements: 4.2
-- ============================================================================
CREATE OR REPLACE TABLE Anomalies (
    anomaly_id VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    equipment_id VARCHAR(50) NOT NULL,
    sensor_type VARCHAR(50) NOT NULL,
    detected_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    actual_value FLOAT NOT NULL,
    expected_value FLOAT,
    severity VARCHAR(20) NOT NULL,  -- Low, Medium, High
    confidence FLOAT,
    CONSTRAINT fk_an_equipment FOREIGN KEY (equipment_id) 
        REFERENCES Equipment_Master(equipment_id),
    CONSTRAINT chk_severity CHECK (severity IN ('Low', 'Medium', 'High'))
);


-- ============================================================================
-- Alerts Table
-- ============================================================================
-- Stores alerts generated from anomalies and predictions
-- Task 2.7 - Requirements: 7.2
-- ============================================================================
CREATE OR REPLACE TABLE Alerts (
    alert_id VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    equipment_id VARCHAR(50) NOT NULL,
    alert_type VARCHAR(50) NOT NULL,  -- Anomaly, Prediction, Threshold
    severity VARCHAR(20) NOT NULL,  -- Low, Medium, High, Critical
    message VARCHAR(1000),
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    status VARCHAR(20) NOT NULL DEFAULT 'New',  -- New, Acknowledged, Resolved
    acknowledged_at TIMESTAMP_NTZ,
    resolved_at TIMESTAMP_NTZ,
    CONSTRAINT fk_al_equipment FOREIGN KEY (equipment_id) 
        REFERENCES Equipment_Master(equipment_id)
);


-- ============================================================================
-- Error_Log Table
-- ============================================================================
-- Captures errors from platform components for debugging and monitoring
-- Task 2.8 - Requirements: Error handling
-- ============================================================================
CREATE OR REPLACE TABLE Error_Log (
    error_id VARCHAR(50) PRIMARY KEY DEFAULT UUID_STRING(),
    component VARCHAR(100) NOT NULL,  -- Name of the component that generated the error
    error_type VARCHAR(100),
    error_message VARCHAR(4000),
    context VARIANT,  -- JSON context data for debugging
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
