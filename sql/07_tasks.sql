-- ============================================================================
-- Predictive Maintenance Platform - Scheduled Tasks
-- ============================================================================
-- This script creates scheduled tasks for automation.
-- Run with: snow --config-file .\config.toml sql -f sql\07_tasks.sql
-- ============================================================================

USE SCHEMA PREDICTIVE_MAINTENANCE.CORE;

-- ============================================================================
-- Task 1: Anomaly Detection Task
-- ============================================================================
-- Runs every 5 minutes to detect anomalies in sensor readings
-- Validates: Requirements 4.1
-- ============================================================================

CREATE OR REPLACE TASK Anomaly_Detection_Task
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL Detect_Anomalies();

-- ============================================================================
-- Task 2: Failure Prediction Task
-- ============================================================================
-- Runs every 15 minutes to generate failure predictions
-- Validates: Requirements 5.3
-- ============================================================================

CREATE OR REPLACE TASK Failure_Prediction_Task
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '15 MINUTE'
AS
    CALL Predict_Failures();

-- ============================================================================
-- Task 3: Alert Generation Task
-- ============================================================================
-- Runs every 5 minutes to generate alerts for anomalies and predictions
-- Validates: Requirements 7.1
-- ============================================================================

CREATE OR REPLACE TASK Alert_Generation_Task
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL Generate_Alerts();

-- ============================================================================
-- Task 4: Work Order Creation Task
-- ============================================================================
-- Runs every 5 minutes to create work orders for high-probability failures
-- Validates: Requirements 7.3
-- ============================================================================

CREATE OR REPLACE TASK Work_Order_Creation_Task
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL Create_Predicted_Work_Orders();

-- ============================================================================
-- NOTE: Tasks are created in SUSPENDED state by default.
-- To enable tasks for production, run the following commands:
--   ALTER TASK Anomaly_Detection_Task RESUME;
--   ALTER TASK Failure_Prediction_Task RESUME;
--   ALTER TASK Alert_Generation_Task RESUME;
--   ALTER TASK Work_Order_Creation_Task RESUME;
-- 
-- This will be done in deployment task 17.3.
-- ============================================================================

-- Verify tasks were created (informational query)
-- SHOW TASKS IN SCHEMA PREDICTIVE_MAINTENANCE.CORE;
