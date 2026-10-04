-- Verify Data Generation Checkpoint
-- This script checks that demo data exists in all required tables

USE DATABASE PREDICTIVE_MAINTENANCE;
USE SCHEMA CORE;

-- 1. Equipment_Master - should have 15 records (5 pumps, 5 motors, 5 compressors)
SELECT '=== Equipment_Master ===' AS verification_section;
SELECT COUNT(*) AS total_equipment FROM Equipment_Master;
SELECT equipment_type, COUNT(*) AS count FROM Equipment_Master GROUP BY equipment_type ORDER BY equipment_type;

-- 2. Sensor_Readings - should have a large number of records
SELECT '=== Sensor_Readings ===' AS verification_section;
SELECT COUNT(*) AS total_sensor_readings FROM Sensor_Readings;
SELECT sensor_type, COUNT(*) AS count FROM Sensor_Readings GROUP BY sensor_type ORDER BY sensor_type;
SELECT MIN(reading_timestamp) AS earliest_reading, MAX(reading_timestamp) AS latest_reading FROM Sensor_Readings;

-- 3. Work_Orders - should have records
SELECT '=== Work_Orders ===' AS verification_section;
SELECT COUNT(*) AS total_work_orders FROM Work_Orders;
SELECT status, COUNT(*) AS count FROM Work_Orders GROUP BY status ORDER BY status;
SELECT source, COUNT(*) AS count FROM Work_Orders GROUP BY source ORDER BY source;

-- 4. Maintenance_Logs - should have records
SELECT '=== Maintenance_Logs ===' AS verification_section;
SELECT COUNT(*) AS total_maintenance_logs FROM Maintenance_Logs;
SELECT maintenance_type, COUNT(*) AS count FROM Maintenance_Logs GROUP BY maintenance_type ORDER BY maintenance_type;

-- 5. Anomalies - should have records for pre-failure equipment (P3, M2, C4)
SELECT '=== Anomalies ===' AS verification_section;
SELECT COUNT(*) AS total_anomalies FROM Anomalies;
SELECT equipment_id, severity, COUNT(*) AS count FROM Anomalies GROUP BY equipment_id, severity ORDER BY equipment_id, severity;

-- Summary
SELECT '=== SUMMARY ===' AS verification_section;
SELECT 
    (SELECT COUNT(*) FROM Equipment_Master) AS equipment_count,
    (SELECT COUNT(*) FROM Sensor_Readings) AS sensor_readings_count,
    (SELECT COUNT(*) FROM Work_Orders) AS work_orders_count,
    (SELECT COUNT(*) FROM Maintenance_Logs) AS maintenance_logs_count,
    (SELECT COUNT(*) FROM Anomalies) AS anomalies_count;
