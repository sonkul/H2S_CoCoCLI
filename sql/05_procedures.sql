-- ============================================================================
-- Predictive Maintenance Platform - Stored Procedures
-- ============================================================================
-- This script creates all stored procedures for data generation, anomaly
-- detection, failure prediction, RCA, alerts, and work orders.
-- Run with: snow --config-file .\config.toml sql -f sql\05_procedures.sql
-- ============================================================================

-- Use the correct schema
USE SCHEMA PREDICTIVE_MAINTENANCE.CORE;


-- ============================================================================
-- Log_Error Stored Procedure
-- ============================================================================
-- Logs errors from platform components to the Error_Log table
-- Task 2.8 - Requirements: Error handling
-- ============================================================================
CREATE OR REPLACE PROCEDURE Log_Error(
    p_component VARCHAR,
    p_error_type VARCHAR,
    p_error_message VARCHAR,
    p_context VARIANT DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO Error_Log (component, error_type, error_message, context)
    VALUES (p_component, p_error_type, p_error_message, p_context);
    RETURN 'Error logged';
END;
$$;


-- ============================================================================
-- Generate_Demo_Data Stored Procedure
-- ============================================================================
-- Creates synthetic demonstration data for the Predictive Maintenance Platform
-- Task 4.1 - Requirements: 9.1, 9.2, 9.3, 9.4, 9.5
-- ============================================================================
CREATE OR REPLACE PROCEDURE Generate_Demo_Data()
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    equipment_count INTEGER := 0;
    sensor_count INTEGER := 0;
    work_order_count INTEGER := 0;
    maintenance_log_count INTEGER := 0;
    anomaly_count INTEGER := 0;
    clear_verification INTEGER := 0;
    result_summary VARIANT;
BEGIN
    -- ========================================================================
    -- STEP 1: Clear all existing data in reverse FK dependency order
    -- ========================================================================
    -- Order matters due to foreign key constraints:
    -- Alerts -> Predictions -> Anomalies -> Work_Orders -> Maintenance_Logs 
    -- -> Sensor_Readings -> Error_Log -> Equipment_Master
    
    DELETE FROM Alerts;
    DELETE FROM Predictions;
    DELETE FROM Anomalies;
    DELETE FROM Work_Orders;
    DELETE FROM Maintenance_Logs;
    DELETE FROM Sensor_Readings;
    DELETE FROM Error_Log;
    DELETE FROM Equipment_Master;
    
    -- ========================================================================
    -- STEP 2: Verify clearing succeeded (Requirement 9.5)
    -- ========================================================================
    SELECT COUNT(*) INTO clear_verification FROM Equipment_Master;
    IF (clear_verification > 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'success', FALSE,
            'error', 'Failed to clear Equipment_Master table',
            'records_remaining', clear_verification
        );
    END IF;
    
    SELECT COUNT(*) INTO clear_verification FROM Sensor_Readings;
    IF (clear_verification > 0) THEN
        RETURN OBJECT_CONSTRUCT(
            'success', FALSE,
            'error', 'Failed to clear Sensor_Readings table',
            'records_remaining', clear_verification
        );
    END IF;
    
    -- ========================================================================
    -- STEP 3: Generate Equipment (15+ units: 5 pumps, 5 motors, 5 compressors)
    -- Requirement 9.1
    -- ========================================================================
    INSERT INTO Equipment_Master (equipment_id, name, equipment_type, location)
    SELECT 
        CONCAT(type_prefix, seq) AS equipment_id,
        CONCAT(type_name, ' ', type_prefix, seq) AS name,
        type_name AS equipment_type,
        CONCAT('Building ', CEIL(seq / 2), ' - Floor ', MOD(seq - 1, 3) + 1) AS location
    FROM (
        -- Generate 5 Pumps (P1-P5)
        SELECT 'P' AS type_prefix, 'Pump' AS type_name, seq 
        FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS seq FROM TABLE(GENERATOR(ROWCOUNT => 5)))
        UNION ALL
        -- Generate 5 Motors (M1-M5)
        SELECT 'M' AS type_prefix, 'Motor' AS type_name, seq 
        FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS seq FROM TABLE(GENERATOR(ROWCOUNT => 5)))
        UNION ALL
        -- Generate 5 Compressors (C1-C5)
        SELECT 'C' AS type_prefix, 'Compressor' AS type_name, seq 
        FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS seq FROM TABLE(GENERATOR(ROWCOUNT => 5)))
    );
    
    SELECT COUNT(*) INTO equipment_count FROM Equipment_Master;
    
    -- ========================================================================
    -- STEP 4: Generate 3 months of sensor time-series data
    -- Requirement 9.2, 9.4
    -- 
    -- Sensor types and their baseline values:
    --   - vibration: base 2.5 mm/s, normal variation ±0.5
    --   - temperature: base 65°C, normal variation ±5
    --   - rpm: base 1750, normal variation ±50
    --
    -- Patterns:
    --   - Normal readings with slight random variation
    --   - Occasional anomaly spikes (0.1% of readings)
    --   - Pre-failure signatures for P3, M2, C4 (days -10 to -7)
    -- ========================================================================
    INSERT INTO Sensor_Readings (equipment_id, sensor_type, reading_timestamp, sensor_value)
    WITH 
    -- Generate time series: 3 months of 5-minute intervals = ~26,000 timestamps
    time_series AS (
        SELECT DATEADD('minute', -seq * 5, CURRENT_TIMESTAMP()) AS ts
        FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS seq 
              FROM TABLE(GENERATOR(ROWCOUNT => 26000)))
    ),
    -- Define sensor types with their characteristics
    equipment_sensors AS (
        SELECT 
            e.equipment_id,
            s.sensor_type,
            CASE s.sensor_type
                WHEN 'vibration' THEN 2.5    -- Base vibration in mm/s
                WHEN 'temperature' THEN 65.0  -- Base temperature in Celsius
                WHEN 'rpm' THEN 1750.0        -- Base RPM
            END AS base_value,
            CASE s.sensor_type
                WHEN 'vibration' THEN 0.5
                WHEN 'temperature' THEN 5.0
                WHEN 'rpm' THEN 50.0
            END AS normal_variation
        FROM Equipment_Master e
        CROSS JOIN (
            SELECT 'vibration' AS sensor_type UNION ALL 
            SELECT 'temperature' UNION ALL 
            SELECT 'rpm'
        ) s
    )
    SELECT
        es.equipment_id,
        es.sensor_type,
        ts.ts AS reading_timestamp,
        -- Calculate sensor value with patterns
        ROUND(
            es.base_value + 
            -- Normal random variation (using hash for deterministic random)
            (MOD(HASH(ts.ts, es.equipment_id, es.sensor_type), 1000000) / 1000000.0 - 0.5) * es.normal_variation +
            -- Pre-failure signature: elevated values for P3, M2, C4 during days -10 to -7
            CASE 
                WHEN es.equipment_id IN ('P3', 'M2', 'C4') 
                     AND ts.ts BETWEEN DATEADD('day', -10, CURRENT_TIMESTAMP()) 
                                  AND DATEADD('day', -7, CURRENT_TIMESTAMP())
                THEN es.normal_variation * 2.5  -- Elevated readings before failure
                ELSE 0
            END +
            -- Random anomaly spikes (~0.1% of readings)
            CASE 
                WHEN MOD(ABS(HASH(ts.ts, es.equipment_id, es.sensor_type, 'spike')), 1000) = 0
                THEN es.normal_variation * (1.5 + MOD(ABS(HASH(ts.ts, es.equipment_id)), 100) / 100.0)
                ELSE 0
            END,
            3  -- Round to 3 decimal places
        ) AS sensor_value
    FROM time_series ts
    CROSS JOIN equipment_sensors es
    -- Sample ~95% of possible readings for realistic data gaps
    WHERE MOD(ABS(HASH(ts.ts, es.equipment_id, es.sensor_type, 'sample')), 100) < 95;
    
    SELECT COUNT(*) INTO sensor_count FROM Sensor_Readings;
    
    -- ========================================================================
    -- STEP 5: Generate Work Orders
    -- Requirement 9.3
    -- Mix of statuses: Open, In Progress, Completed, Cancelled
    -- ========================================================================
    INSERT INTO Work_Orders (equipment_id, description, priority, status, created_at, scheduled_date, completed_at, source)
    SELECT
        e.equipment_id,
        CONCAT(
            CASE MOD(multiplier.n + HASH(e.equipment_id), 4)
                WHEN 0 THEN 'Scheduled maintenance: '
                WHEN 1 THEN 'Repair request: '
                WHEN 2 THEN 'Inspection: '
                ELSE 'Preventive service: '
            END,
            e.name
        ) AS description,
        CASE MOD(multiplier.n + HASH(e.equipment_id), 4)
            WHEN 0 THEN 'Low'
            WHEN 1 THEN 'Medium'
            WHEN 2 THEN 'High'
            ELSE 'Critical'
        END AS priority,
        CASE MOD(multiplier.n + HASH(e.equipment_id, 'status'), 5)
            WHEN 0 THEN 'Open'
            WHEN 1 THEN 'In Progress'
            WHEN 2 THEN 'Completed'
            WHEN 3 THEN 'Completed'
            ELSE 'Cancelled'
        END AS status,
        DATEADD('day', -MOD(ABS(HASH(e.equipment_id, multiplier.n, 'created')), 90), CURRENT_TIMESTAMP()) AS created_at,
        DATEADD('day', -MOD(ABS(HASH(e.equipment_id, multiplier.n, 'scheduled')), 85), CURRENT_TIMESTAMP()) AS scheduled_date,
        CASE 
            WHEN MOD(multiplier.n + HASH(e.equipment_id, 'status'), 5) IN (2, 3)
            THEN DATEADD('day', -MOD(ABS(HASH(e.equipment_id, multiplier.n, 'completed')), 80), CURRENT_TIMESTAMP())
            ELSE NULL
        END AS completed_at,
        CASE MOD(multiplier.n, 3)
            WHEN 0 THEN 'Manual'
            WHEN 1 THEN 'Prediction'
            ELSE 'Alert'
        END AS source
    FROM Equipment_Master e
    CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 3))) multiplier;
    
    SELECT COUNT(*) INTO work_order_count FROM Work_Orders;
    
    -- ========================================================================
    -- STEP 6: Generate Maintenance Logs
    -- Requirement 9.3
    -- Types: Preventive, Corrective, Emergency
    -- ========================================================================
    INSERT INTO Maintenance_Logs (equipment_id, maintenance_type, technician, start_time, end_time, description)
    SELECT
        e.equipment_id,
        CASE MOD(multiplier.n + HASH(e.equipment_id, 'mtype'), 3)
            WHEN 0 THEN 'Preventive'
            WHEN 1 THEN 'Corrective'
            ELSE 'Emergency'
        END AS maintenance_type,
        CONCAT('Tech-', MOD(ABS(HASH(e.equipment_id, multiplier.n, 'tech')), 10) + 1) AS technician,
        DATEADD('day', -MOD(ABS(HASH(e.equipment_id, multiplier.n, 'start')), 90), CURRENT_TIMESTAMP()) AS start_time,
        DATEADD('hour', 
                MOD(ABS(HASH(e.equipment_id, multiplier.n, 'duration')), 8) + 1,
                DATEADD('day', -MOD(ABS(HASH(e.equipment_id, multiplier.n, 'start')), 90), CURRENT_TIMESTAMP())
        ) AS end_time,
        CONCAT(
            CASE MOD(multiplier.n + HASH(e.equipment_id, 'mdesc'), 5)
                WHEN 0 THEN 'Replaced bearings and lubricated'
                WHEN 1 THEN 'Calibrated sensors and checked alignment'
                WHEN 2 THEN 'Emergency repair - replaced failed component'
                WHEN 3 THEN 'Routine inspection - all systems normal'
                ELSE 'Cleaned filters and checked connections'
            END,
            ' for ', e.name
        ) AS description
    FROM Equipment_Master e
    CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 4))) multiplier;
    
    SELECT COUNT(*) INTO maintenance_log_count FROM Maintenance_Logs;
    
    -- ========================================================================
    -- STEP 7: Generate Initial Anomalies for Pre-Failure Equipment
    -- Requirement 9.2 - pre-failure signatures for P3, M2, C4
    -- ========================================================================
    INSERT INTO Anomalies (equipment_id, sensor_type, detected_at, actual_value, expected_value, severity, confidence)
    SELECT
        sr.equipment_id,
        sr.sensor_type,
        sr.reading_timestamp AS detected_at,
        sr.sensor_value AS actual_value,
        CASE sr.sensor_type
            WHEN 'vibration' THEN 2.5
            WHEN 'temperature' THEN 65.0
            ELSE 1750.0
        END AS expected_value,
        CASE 
            WHEN ABS(sr.sensor_value - CASE sr.sensor_type 
                    WHEN 'vibration' THEN 2.5 
                    WHEN 'temperature' THEN 65.0 
                    ELSE 1750.0 END) / 
                 CASE sr.sensor_type 
                    WHEN 'vibration' THEN 0.5 
                    WHEN 'temperature' THEN 5.0 
                    ELSE 50.0 END > 3.5 
            THEN 'High'
            WHEN ABS(sr.sensor_value - CASE sr.sensor_type 
                    WHEN 'vibration' THEN 2.5 
                    WHEN 'temperature' THEN 65.0 
                    ELSE 1750.0 END) / 
                 CASE sr.sensor_type 
                    WHEN 'vibration' THEN 0.5 
                    WHEN 'temperature' THEN 5.0 
                    ELSE 50.0 END > 2.5 
            THEN 'Medium'
            ELSE 'Low'
        END AS severity,
        0.85 + (MOD(ABS(HASH(sr.equipment_id, sr.sensor_type, sr.reading_timestamp)), 100) / 1000.0) AS confidence
    FROM Sensor_Readings sr
    WHERE sr.equipment_id IN ('P3', 'M2', 'C4')
    AND sr.reading_timestamp BETWEEN DATEADD('day', -10, CURRENT_TIMESTAMP()) 
                                  AND DATEADD('day', -7, CURRENT_TIMESTAMP())
    -- Only flag readings that deviate significantly (z-score > 2)
    AND ABS(sr.sensor_value - CASE sr.sensor_type 
            WHEN 'vibration' THEN 2.5 
            WHEN 'temperature' THEN 65.0 
            ELSE 1750.0 END) / 
        CASE sr.sensor_type 
            WHEN 'vibration' THEN 0.5 
            WHEN 'temperature' THEN 5.0 
            ELSE 50.0 END > 2.0
    -- Limit to reasonable number of anomalies per equipment
    QUALIFY ROW_NUMBER() OVER (PARTITION BY sr.equipment_id, sr.sensor_type ORDER BY sr.reading_timestamp) <= 50;
    
    SELECT COUNT(*) INTO anomaly_count FROM Anomalies;
    
    -- ========================================================================
    -- STEP 8: Build and return JSON summary
    -- ========================================================================
    result_summary := OBJECT_CONSTRUCT(
        'success', TRUE,
        'message', 'Demo data generated successfully',
        'summary', OBJECT_CONSTRUCT(
            'equipment_count', equipment_count,
            'sensor_readings_count', sensor_count,
            'work_orders_count', work_order_count,
            'maintenance_logs_count', maintenance_log_count,
            'anomalies_count', anomaly_count
        ),
        'equipment_breakdown', OBJECT_CONSTRUCT(
            'pumps', 5,
            'motors', 5,
            'compressors', 5
        ),
        'pre_failure_equipment', ARRAY_CONSTRUCT('P3', 'M2', 'C4'),
        'data_range', OBJECT_CONSTRUCT(
            'start_date', DATEADD('day', -90, CURRENT_TIMESTAMP())::VARCHAR,
            'end_date', CURRENT_TIMESTAMP()::VARCHAR
        )
    );
    
    RETURN result_summary;
END;
$$;


-- ============================================================================
-- Detect_Anomalies Stored Procedure
-- ============================================================================
-- Analyzes sensor data using z-score based anomaly detection
-- Task 7.1 - Requirements: 4.1, 4.2, 4.3
-- 
-- Severity thresholds:
--   - |z_score| > 3: High
--   - |z_score| > 2: Medium  
--   - |z_score| > 2: Low (minimum threshold for detection)
--
-- Confidence calculation: Sigmoid function 1 - (1 / (1 + exp(|z_score| - 2)))
--   - Higher z-score = higher confidence
--   - Centered at z=2 (50% confidence at threshold)
--
-- Duplicate prevention: Checks for existing anomaly records with same
--   equipment_id, sensor_type, and detected_at timestamp
-- ============================================================================
CREATE OR REPLACE PROCEDURE Detect_Anomalies()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    anomaly_count INTEGER;
BEGIN
    -- Insert detected anomalies based on z-score threshold
    -- Only inserts if no existing anomaly record exists for same equipment/sensor/timestamp
    INSERT INTO Anomalies (equipment_id, sensor_type, detected_at, actual_value, expected_value, severity, confidence)
    SELECT
        adi.equipment_id,
        adi.sensor_type,
        adi.time_bucket AS detected_at,
        adi.avg_value AS actual_value,
        -- Calculate expected value as rolling average (same window as z-score calculation)
        AVG(adi.avg_value) OVER (
            PARTITION BY adi.equipment_id, adi.sensor_type 
            ORDER BY adi.time_bucket 
            ROWS BETWEEN 288 PRECEDING AND 1 PRECEDING
        ) AS expected_value,
        -- Severity based on z-score magnitude
        CASE
            WHEN ABS(adi.z_score) > 3 THEN 'High'
            WHEN ABS(adi.z_score) > 2 THEN 'Medium'
            ELSE 'Low'
        END AS severity,
        -- Sigmoid confidence: higher z-score = higher confidence
        -- Formula: 1 - (1 / (1 + exp(|z_score| - 2)))
        1 - (1 / (1 + EXP(ABS(adi.z_score) - 2))) AS confidence
    FROM Anomaly_Detection_Input adi
    WHERE ABS(adi.z_score) > 2  -- Only flag significant deviations
    -- Prevent duplicate entries
    AND NOT EXISTS (
        SELECT 1 FROM Anomalies a
        WHERE a.equipment_id = adi.equipment_id
        AND a.sensor_type = adi.sensor_type
        AND a.detected_at = adi.time_bucket
    );
    
    -- Get count of newly inserted anomalies
    SELECT COUNT(*) INTO anomaly_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    
    RETURN 'Detected ' || anomaly_count || ' new anomalies';
END;
$$;


-- ============================================================================
-- Predict_Failures Stored Procedure
-- ============================================================================
-- Generates failure predictions using a weighted scoring model based on
-- anomaly patterns, sensor trends, and maintenance history.
-- Task 8.2 - Requirements: 5.1, 5.2, 5.3
--
-- Weighted scoring factors:
--   - High severity anomalies: 15 points each
--   - Total anomalies (24h): 5 points each
--   - Rate of change: up to 20 points (capped at rate > 10)
--   - Days since maintenance: 5-15 points based on gap duration
--
-- Prediction triggers:
--   - Any high severity anomaly in last 24h
--   - 3+ total anomalies in last 24h
--   - More than 60 days since last maintenance
--
-- Probability is capped at 95% to reflect inherent uncertainty.
-- Old predictions (>1 hour) are deactivated before generating new ones.
-- ============================================================================
CREATE OR REPLACE PROCEDURE Predict_Failures()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    prediction_count INTEGER;
BEGIN
    -- Deactivate old predictions (older than 1 hour)
    UPDATE Predictions SET is_active = FALSE 
    WHERE is_active = TRUE 
    AND generated_at < DATEADD('hour', -1, CURRENT_TIMESTAMP());
    
    -- Generate new predictions using weighted scoring model
    -- Sources features from Failure_Prediction_Features view
    INSERT INTO Predictions (
        equipment_id, failure_probability, 
        predicted_failure_start, predicted_failure_end, 
        contributing_factors, is_active
    )
    SELECT
        equipment_id,
        -- Weighted probability calculation (capped at 95%)
        LEAST(95, 
            (high_anomaly_count * 15) + 
            (anomaly_count_24h * 5) + 
            (CASE WHEN avg_rate_of_change > 10 THEN 20 ELSE avg_rate_of_change END) +
            (CASE WHEN days_since_maintenance > 90 THEN 15 
                  WHEN days_since_maintenance > 60 THEN 10 
                  WHEN days_since_maintenance > 30 THEN 5 
                  ELSE 0 END)
        ) AS failure_probability,
        -- Prediction window: 2 to 48 hours from now
        DATEADD('hour', 2, CURRENT_TIMESTAMP()) AS predicted_failure_start,
        DATEADD('hour', 48, CURRENT_TIMESTAMP()) AS predicted_failure_end,
        -- Contributing factors as ARRAY of OBJECTs for traceability
        ARRAY_CONSTRUCT(
            OBJECT_CONSTRUCT('factor', 'Anomaly Count', 'value', anomaly_count_24h),
            OBJECT_CONSTRUCT('factor', 'High Severity Anomalies', 'value', high_anomaly_count),
            OBJECT_CONSTRUCT('factor', 'Rate of Change', 'value', ROUND(avg_rate_of_change, 2)),
            OBJECT_CONSTRUCT('factor', 'Days Since Maintenance', 'value', days_since_maintenance)
        ) AS contributing_factors,
        TRUE AS is_active
    FROM Failure_Prediction_Features
    -- Only generate predictions for equipment showing risk indicators
    WHERE (high_anomaly_count > 0 OR anomaly_count_24h >= 3 OR days_since_maintenance > 60);
    
    -- Get count of newly inserted predictions
    SELECT COUNT(*) INTO prediction_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    
    RETURN 'Generated ' || prediction_count || ' predictions';
END;
$$;


-- ============================================================================
-- RCA_Query Stored Procedure
-- ============================================================================
-- Natural language root cause analysis using Cortex LLM
-- Task 10.2 - Requirements: 6.1, 6.2, 6.3, 6.4
--
-- Features:
--   - Extracts equipment ID from natural language query if not provided
--   - Builds context using Build_RCA_Context function
--   - Calls SNOWFLAKE.CORTEX.COMPLETE with llama3.1-70b model
--   - Returns structured VARIANT response with equipment_id and query_time
--
-- Supported query types:
--   - "Why did compressor A3 fail?"
--   - "What sensors were abnormal before the pump shutdown?"
--   - "Show me vibration trends for motor M1"
--
-- Return format (VARIANT/JSON):
--   {
--     "response": "LLM generated response text",
--     "equipment_id": "P1",
--     "query_time": "2024-01-15T10:30:00.000Z"
--   }
--
-- Error handling:
--   - Returns user-friendly message when equipment not found
-- ============================================================================
CREATE OR REPLACE PROCEDURE RCA_Query(p_query VARCHAR, p_equipment_id VARCHAR DEFAULT NULL)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_context_text VARCHAR;
    v_llm_response VARCHAR;
    v_target_equipment VARCHAR;
    v_result_obj VARIANT;
BEGIN
    -- Extract equipment ID from query if not provided
    IF (p_equipment_id IS NULL OR p_equipment_id = '') THEN
        -- Simple extraction: look for equipment patterns like "P1", "M1", "C2"
        -- Matches against both equipment_id and name columns
        SELECT equipment_id INTO :v_target_equipment
        FROM Equipment_Master
        WHERE CONTAINS(UPPER(:p_query), UPPER(name))
           OR CONTAINS(UPPER(:p_query), UPPER(equipment_id))
        LIMIT 1;
    ELSE
        v_target_equipment := p_equipment_id;
    END IF;
    
    -- Handle case when equipment not found
    IF (v_target_equipment IS NULL) THEN
        v_result_obj := OBJECT_CONSTRUCT(
            'response', 'I could not identify which equipment you are asking about. Please specify an equipment ID or name (e.g., P1, M2, C3, or "Pump P1").',
            'equipment_id', NULL,
            'query_time', CURRENT_TIMESTAMP()
        );
        RETURN v_result_obj;
    END IF;
    
    -- Build context using the Build_RCA_Context function
    -- Retrieves last 24 hours of data for the equipment
    SELECT Build_RCA_Context(:v_target_equipment, 24) INTO :v_context_text;
    
    -- Call Cortex LLM with llama3.1-70b model
    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-70b',
        'You are a maintenance engineering assistant analyzing equipment data. ' ||
        'Answer the following question using ONLY the data provided. ' ||
        'Include specific timestamps, values, and measurements in your response. ' ||
        'If the data does not contain enough information to answer, say so.' || CHR(10) || CHR(10) ||
        'DATA:' || CHR(10) || :v_context_text || CHR(10) || CHR(10) ||
        'QUESTION: ' || :p_query || CHR(10) || CHR(10) ||
        'ANSWER:'
    ) INTO :v_llm_response;
    
    -- Return structured response with equipment_id and query_time
    v_result_obj := OBJECT_CONSTRUCT(
        'response', v_llm_response,
        'equipment_id', v_target_equipment,
        'query_time', CURRENT_TIMESTAMP()
    );
    
    RETURN v_result_obj;
END;
$$;


-- ============================================================================
-- Generate_Alerts Stored Procedure
-- ============================================================================
-- Generates alerts for anomalies and high-probability failure predictions
-- Task 11.1 - Requirements: 7.1, 7.2
--
-- Alert triggers:
--   - Medium/High severity anomalies detected in last 5 minutes
--   - Predictions with failure_probability >= 50% generated in last 15 minutes
--
-- Severity mapping for predictions:
--   - failure_probability >= 80%: Critical
--   - failure_probability >= 60%: High
--   - failure_probability >= 50%: Medium
--
-- Deduplication:
--   - Anomaly alerts: No duplicate if non-resolved alert exists within 1 hour
--   - Prediction alerts: No duplicate if non-resolved alert exists within 2 hours
--
-- Return format:
--   Returns message with count of alerts generated
-- ============================================================================
CREATE OR REPLACE PROCEDURE Generate_Alerts()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    anomaly_alert_count INTEGER := 0;
    prediction_alert_count INTEGER := 0;
    total_alert_count INTEGER := 0;
BEGIN
    -- ========================================================================
    -- STEP 1: Create alerts for new Medium/High severity anomalies
    -- ========================================================================
    -- Only alerts for anomalies detected in last 5 minutes
    -- Deduplication: Skip if non-resolved alert exists for same equipment
    -- and alert_type='Anomaly' within the last hour
    INSERT INTO Alerts (equipment_id, alert_type, severity, message, status)
    SELECT
        a.equipment_id,
        'Anomaly' AS alert_type,
        a.severity,
        CONCAT('Anomaly detected in ', a.sensor_type, ': value ', a.actual_value, 
               ' (expected ~', ROUND(a.expected_value, 2), ')') AS message,
        'New' AS status
    FROM Anomalies a
    WHERE a.detected_at >= DATEADD('minute', -5, CURRENT_TIMESTAMP())
    AND a.severity IN ('Medium', 'High')
    -- Deduplication: Check for existing non-resolved anomaly alert within 1 hour
    AND NOT EXISTS (
        SELECT 1 FROM Alerts al 
        WHERE al.equipment_id = a.equipment_id 
        AND al.alert_type = 'Anomaly'
        AND al.created_at >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
        AND al.status != 'Resolved'
    );
    
    -- Get count of anomaly alerts inserted
    SELECT COUNT(*) INTO anomaly_alert_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    
    -- ========================================================================
    -- STEP 2: Create alerts for high-probability failure predictions
    -- ========================================================================
    -- Only alerts for predictions generated in last 15 minutes with probability >= 50%
    -- Severity based on probability:
    --   >= 80%: Critical
    --   >= 60%: High
    --   >= 50%: Medium
    -- Deduplication: Skip if non-resolved prediction alert exists within 2 hours
    INSERT INTO Alerts (equipment_id, alert_type, severity, message, status)
    SELECT
        p.equipment_id,
        'Prediction' AS alert_type,
        CASE 
            WHEN p.failure_probability >= 80 THEN 'Critical'
            WHEN p.failure_probability >= 60 THEN 'High'
            ELSE 'Medium'
        END AS severity,
        CONCAT('Failure predicted with ', p.failure_probability, '% probability between ',
               p.predicted_failure_start::VARCHAR, ' and ', p.predicted_failure_end::VARCHAR) AS message,
        'New' AS status
    FROM Predictions p
    WHERE p.is_active = TRUE
    AND p.generated_at >= DATEADD('minute', -15, CURRENT_TIMESTAMP())
    AND p.failure_probability >= 50
    -- Deduplication: Check for existing non-resolved prediction alert within 2 hours
    AND NOT EXISTS (
        SELECT 1 FROM Alerts al 
        WHERE al.equipment_id = p.equipment_id 
        AND al.alert_type = 'Prediction'
        AND al.created_at >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
        AND al.status != 'Resolved'
    );
    
    -- Get count of prediction alerts inserted
    SELECT COUNT(*) INTO prediction_alert_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    
    -- ========================================================================
    -- STEP 3: Calculate total and return summary
    -- ========================================================================
    total_alert_count := anomaly_alert_count + prediction_alert_count;
    
    RETURN 'Generated ' || total_alert_count || ' new alerts (' || 
           anomaly_alert_count || ' anomaly, ' || 
           prediction_alert_count || ' prediction)';
END;
$$;


-- ============================================================================
-- Create_Predicted_Work_Orders Stored Procedure
-- ============================================================================
-- Creates work orders for high-probability failure predictions (>= 80%)
-- Task 11.2 - Requirements: 7.3, 7.4
--
-- Priority assignment:
--   - failure_probability >= 90%: Critical
--   - failure_probability >= 80%: High
--
-- Duplicate prevention:
--   - Checks for existing open/in-progress work orders with source = 'Prediction'
--   - Only creates one work order per equipment at a time
--
-- Return format: 'Created N work orders'
-- ============================================================================
CREATE OR REPLACE PROCEDURE Create_Predicted_Work_Orders()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    wo_count INTEGER := 0;
BEGIN
    -- Create work orders for high-probability failure predictions (>= 80%)
    INSERT INTO Work_Orders (equipment_id, description, priority, status, scheduled_date, source)
    SELECT
        p.equipment_id,
        CONCAT('Predicted failure - Probability: ', p.failure_probability, '%. ',
               'Contributing factors: ', p.contributing_factors::VARCHAR),
        CASE 
            WHEN p.failure_probability >= 90 THEN 'Critical'
            ELSE 'High'
        END AS priority,
        'Open' AS status,
        p.predicted_failure_start AS scheduled_date,
        'Prediction' AS source
    FROM Predictions p
    WHERE p.is_active = TRUE
    AND p.failure_probability >= 80
    -- Prevent duplicate work orders (Requirement 7.4)
    AND NOT EXISTS (
        SELECT 1 FROM Work_Orders wo
        WHERE wo.equipment_id = p.equipment_id
        AND wo.source = 'Prediction'
        AND wo.status IN ('Open', 'In Progress')
    );
    
    -- Get count of newly inserted work orders
    SELECT COUNT(*) INTO wo_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    
    RETURN 'Created ' || wo_count || ' work orders';
END;
$$;
