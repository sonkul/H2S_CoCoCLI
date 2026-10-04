-- ============================================================================
-- Predictive Maintenance Platform - Dynamic Tables
-- ============================================================================
-- This script creates Dynamic Tables for real-time sensor aggregation.
-- Run with: snow --config-file .\config.toml sql -f sql\03_dynamic_tables.sql
-- ============================================================================

USE SCHEMA PREDICTIVE_MAINTENANCE.CORE;

-- ============================================================================
-- Sensor_Stats_5Min Dynamic Table
-- ============================================================================
-- Purpose: Automatically aggregates sensor readings into 5-minute buckets
-- Features:
--   - Rolling averages, min, max, stddev per sensor type and equipment
--   - Rate of change percentage between consecutive time buckets
--   - TARGET_LAG of 1 minute for near real-time updates
--
-- Validates Requirements: 3.1, 3.2, 3.3
-- ============================================================================

CREATE OR REPLACE DYNAMIC TABLE Sensor_Stats_5Min
    TARGET_LAG = '1 minute'
    WAREHOUSE = COMPUTE_WH
AS
WITH time_bucketed AS (
    -- Bucket sensor readings into 5-minute intervals
    -- Only process last 7 days of data for performance
    SELECT
        equipment_id,
        sensor_type,
        TIME_SLICE(reading_timestamp, 5, 'MINUTE') AS time_bucket,
        sensor_value,
        reading_timestamp
    FROM Sensor_Readings
    WHERE reading_timestamp >= DATEADD('day', -7, CURRENT_TIMESTAMP())
),
stats AS (
    -- Compute rolling statistics per equipment and sensor type
    SELECT
        equipment_id,
        sensor_type,
        time_bucket,
        AVG(sensor_value) AS avg_value,
        MIN(sensor_value) AS min_value,
        MAX(sensor_value) AS max_value,
        STDDEV(sensor_value) AS stddev_value,
        COUNT(*) AS reading_count
    FROM time_bucketed
    GROUP BY equipment_id, sensor_type, time_bucket
),
with_lag AS (
    -- Get previous bucket's average value for rate of change calculation
    SELECT
        s.*,
        LAG(avg_value) OVER (
            PARTITION BY equipment_id, sensor_type 
            ORDER BY time_bucket
        ) AS prev_avg_value
    FROM stats s
)
-- Final output with rate of change percentage
SELECT
    equipment_id,
    sensor_type,
    time_bucket,
    avg_value,
    min_value,
    max_value,
    stddev_value,
    reading_count,
    CASE 
        WHEN prev_avg_value IS NOT NULL AND prev_avg_value != 0 
        THEN ((avg_value - prev_avg_value) / prev_avg_value) * 100
        ELSE 0 
    END AS rate_of_change_pct
FROM with_lag;
