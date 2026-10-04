-- ============================================================================
-- Predictive Maintenance Platform - User-Defined Functions
-- ============================================================================
-- This script creates UDFs for RCA context building and other utilities.
-- Run with: snow --config-file .\config.toml sql -f sql\06_functions.sql
-- ============================================================================

USE SCHEMA PREDICTIVE_MAINTENANCE.CORE;

-- ============================================================================
-- Build_RCA_Context Function
-- ============================================================================
-- Builds a context string with equipment info, recent sensor readings,
-- anomalies, maintenance history, and active predictions for LLM consumption.
-- 
-- Parameters:
--   p_equipment_id: The equipment ID to build context for
--   p_time_hours: Number of hours of history to include for sensor readings and anomalies
--
-- Returns: A formatted string containing all relevant context for RCA queries
-- ============================================================================

CREATE OR REPLACE FUNCTION Build_RCA_Context(p_equipment_id VARCHAR, p_time_hours INTEGER)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    SELECT CONCAT(
        '## Equipment Information\n',
        COALESCE(
            (SELECT CONCAT('Equipment: ', name, ' (', equipment_type, ') at ', location)
             FROM Equipment_Master WHERE equipment_id = p_equipment_id),
            'Equipment not found'
        ),
        '\n\n## Recent Sensor Readings (Last ', p_time_hours::VARCHAR, ' hours)\n',
        COALESCE(
            (SELECT LISTAGG(
                CONCAT(sensor_type, ' at ', reading_timestamp::VARCHAR, ': ', sensor_value::VARCHAR), '\n'
             ) WITHIN GROUP (ORDER BY reading_timestamp DESC)
             FROM (SELECT sensor_type, reading_timestamp, sensor_value 
                   FROM Sensor_Readings 
                   WHERE equipment_id = p_equipment_id 
                   AND reading_timestamp >= DATEADD('hour', -p_time_hours, CURRENT_TIMESTAMP())
                   ORDER BY reading_timestamp DESC
                   LIMIT 50)),
            'No sensor readings available'
        ),
        '\n\n## Detected Anomalies\n',
        COALESCE(
            (SELECT LISTAGG(
                CONCAT(severity, ' severity ', sensor_type, ' anomaly at ', detected_at::VARCHAR, 
                       ': value=', actual_value::VARCHAR, ', expected=', expected_value::VARCHAR), '\n'
             ) WITHIN GROUP (ORDER BY detected_at DESC)
             FROM Anomalies 
             WHERE equipment_id = p_equipment_id 
             AND detected_at >= DATEADD('hour', -p_time_hours, CURRENT_TIMESTAMP())),
            'No anomalies detected'
        ),
        '\n\n## Maintenance History\n',
        COALESCE(
            (SELECT LISTAGG(
                CONCAT(maintenance_type, ' maintenance on ', start_time::VARCHAR, ': ', description), '\n'
             ) WITHIN GROUP (ORDER BY start_time DESC)
             FROM (SELECT maintenance_type, start_time, description
                   FROM Maintenance_Logs 
                   WHERE equipment_id = p_equipment_id 
                   AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
                   ORDER BY start_time DESC
                   LIMIT 10)),
            'No recent maintenance'
        ),
        '\n\n## Active Predictions\n',
        COALESCE(
            (SELECT LISTAGG(
                CONCAT('Failure probability: ', failure_probability::VARCHAR, '%, Window: ', 
                       predicted_failure_start::VARCHAR, ' to ', predicted_failure_end::VARCHAR), '\n'
             )
             FROM Predictions 
             WHERE equipment_id = p_equipment_id AND is_active = TRUE),
            'No active predictions'
        )
    )
$$;
