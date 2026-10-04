-- ============================================================================
-- Predictive Maintenance Platform - Views
-- ============================================================================
-- This script creates views for anomaly detection and feature engineering.
-- Run with: snow --config-file .\config.toml sql -f sql\04_views.sql
-- ============================================================================

USE DATABASE PREDICTIVE_MAINTENANCE;
USE SCHEMA CORE;

-- ============================================================================
-- View: Anomaly_Detection_Input
-- ============================================================================
-- Purpose: Calculates z-scores for sensor readings using a rolling 24-hour
--          window as baseline for anomaly detection.
-- Dependencies: Sensor_Stats_5Min Dynamic Table
-- Used by: Detect_Anomalies stored procedure
-- Requirements: 4.1 - Anomaly detection for significant deviations
-- ============================================================================

CREATE OR REPLACE VIEW Anomaly_Detection_Input AS
SELECT
    equipment_id,
    sensor_type,
    time_bucket,
    avg_value,
    stddev_value,
    rate_of_change_pct,
    -- Calculate z-score for anomaly detection
    -- Z-score = (current value - rolling mean) / rolling standard deviation
    -- Rolling window: 288 x 5-minute buckets = 24 hours
    (avg_value - AVG(avg_value) OVER (
        PARTITION BY equipment_id, sensor_type 
        ORDER BY time_bucket 
        ROWS BETWEEN 288 PRECEDING AND 1 PRECEDING  -- 24 hours of 5-min buckets
    )) / NULLIF(STDDEV(avg_value) OVER (
        PARTITION BY equipment_id, sensor_type 
        ORDER BY time_bucket 
        ROWS BETWEEN 288 PRECEDING AND 1 PRECEDING
    ), 0) AS z_score
FROM Sensor_Stats_5Min
WHERE time_bucket >= DATEADD('hour', -1, CURRENT_TIMESTAMP());

-- ============================================================================
-- View: Failure_Prediction_Features
-- ============================================================================
-- Purpose: Aggregates features from multiple data sources for failure prediction.
--          Joins recent anomalies, sensor trends, and maintenance gap data.
-- Dependencies: Equipment_Master, Anomalies, Sensor_Stats_5Min, Maintenance_Logs
-- Used by: Predict_Failures stored procedure
-- Requirements: 5.1 - Failure prediction using equipment data correlation
-- ============================================================================

CREATE OR REPLACE VIEW Failure_Prediction_Features AS
WITH recent_anomalies AS (
    -- Count anomalies in the last 24 hours per equipment
    SELECT
        equipment_id,
        COUNT(*) AS anomaly_count_24h,
        SUM(CASE WHEN severity = 'High' THEN 1 ELSE 0 END) AS high_anomaly_count,
        MAX(detected_at) AS last_anomaly_time
    FROM Anomalies
    WHERE detected_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
    GROUP BY equipment_id
),
sensor_trends AS (
    -- Calculate sensor rate of change trends in the last 6 hours
    SELECT
        equipment_id,
        AVG(ABS(rate_of_change_pct)) AS avg_rate_of_change,
        MAX(ABS(rate_of_change_pct)) AS max_rate_of_change
    FROM Sensor_Stats_5Min
    WHERE time_bucket >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
    GROUP BY equipment_id
),
maintenance_gap AS (
    -- Calculate days since last maintenance per equipment
    SELECT
        equipment_id,
        DATEDIFF('day', MAX(end_time), CURRENT_TIMESTAMP()) AS days_since_maintenance
    FROM Maintenance_Logs
    GROUP BY equipment_id
)
SELECT
    e.equipment_id,
    e.equipment_type,
    COALESCE(ra.anomaly_count_24h, 0) AS anomaly_count_24h,
    COALESCE(ra.high_anomaly_count, 0) AS high_anomaly_count,
    COALESCE(st.avg_rate_of_change, 0) AS avg_rate_of_change,
    COALESCE(st.max_rate_of_change, 0) AS max_rate_of_change,
    COALESCE(mg.days_since_maintenance, 365) AS days_since_maintenance
FROM Equipment_Master e
LEFT JOIN recent_anomalies ra ON e.equipment_id = ra.equipment_id
LEFT JOIN sensor_trends st ON e.equipment_id = st.equipment_id
LEFT JOIN maintenance_gap mg ON e.equipment_id = mg.equipment_id
WHERE e.is_active = TRUE;
