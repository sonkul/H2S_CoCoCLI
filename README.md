# H2S_CoCoCLI
H2S Competition
# Predictive Maintenance Platform

A comprehensive **Predictive Maintenance Platform** built on Snowflake for manufacturing operations. The platform correlates IT (ERP, maintenance records) and OT (sensor data) to predict equipment failures, enables natural language root cause investigation, and provides a command center experience.

## 🎯 Problem Statement

Manufacturing plants face unexpected equipment failures that lead to:
- Unplanned downtime costing thousands per hour
- Reactive maintenance instead of proactive
- Difficulty correlating sensor data with maintenance history
- Time-consuming root cause analysis

## 💡 Solution

This platform leverages Snowflake's native capabilities to provide:
- **Real-time sensor aggregation** using Dynamic Tables
- **Anomaly detection** to identify abnormal equipment behavior
- **Failure prediction** to forecast equipment issues before they occur
- **Natural language RCA** using Cortex LLM for easy investigation
- **Automated alerting** and work order generation
- **Command Center dashboard** built with Streamlit in Snowflake

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SNOWFLAKE PLATFORM                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Sensors    │    │  ERP Data    │    │ Maintenance  │      │
│  │   (OT Data)  │    │  (IT Data)   │    │    Logs      │      │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│         │                   │                   │               │
│         └───────────────────┼───────────────────┘               │
│                             ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              CORE TABLES & DYNAMIC TABLES                 │  │
│  │  Equipment_Master │ Sensor_Reading │ Sensor_Aggregation  │  │
│  │  Work_Orders │ Maintenance_Logs │ Alerts │ Predictions   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             │                                   │
│         ┌───────────────────┼───────────────────┐              │
│         ▼                   ▼                   ▼              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Anomaly    │    │   Failure    │    │     RCA      │      │
│  │  Detection   │    │  Prediction  │    │  Assistant   │      │
│  │  (Cortex ML) │    │  (Cortex ML) │    │ (Cortex LLM) │      │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│         │                   │                   │               │
│         └───────────────────┼───────────────────┘               │
│                             ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           STREAMLIT COMMAND CENTER DASHBOARD              │  │
│  │  Equipment Overview │ Alerts │ Predictions │ RCA Chat    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Features

### 1. Equipment & Sensor Management
- Store and manage equipment records (pumps, motors, compressors)
- Ingest sensor readings (vibration, temperature, RPM)
- Automatic data validation

### 2. Real-Time Aggregation
- Dynamic Tables compute rolling statistics (avg, min, max, std dev)
- 5-minute interval aggregations
- Rate of change detection for rapid fluctuations

### 3. Anomaly Detection
- ML-based detection of abnormal sensor patterns
- Severity classification (Low, Medium, High)
- Multi-sensor correlation analysis

### 4. Failure Prediction
- Predict equipment failures before they occur
- Probability scoring with contributing factors
- Time window predictions

### 5. Natural Language RCA
- Ask questions like "Why did compressor A3 fail?"
- Correlates sensor data with maintenance history
- Provides specific data references in responses

### 6. Automated Alerting
- Threshold-based alerts
- Automatic work order creation for high-risk predictions
- Duplicate detection to avoid redundant work orders

### 7. Command Center Dashboard
- Equipment health overview with status indicators
- Alert management with acknowledge/resolve actions
- Failure predictions visualization
- Interactive RCA chat interface

## 📁 Project Structure

```
├── sql/
│   ├── 01_database_setup.sql    # Database, schema, warehouse
│   ├── 02_tables.sql            # Core data tables
│   ├── 03_dynamic_tables.sql    # Real-time aggregation
│   ├── 04_views.sql             # Anomaly detection views
│   ├── 05_procedures.sql        # ML & business logic procedures
│   ├── 06_functions.sql         # Utility UDFs
│   ├── 07_tasks.sql             # Scheduled automation
│   ├── 08_tests.sql             # Unit & integration tests
│   └── verify_data.sql          # Data verification queries
│
├── streamlit_app/
│   ├── app.py                   # Main dashboard
│   ├── environment.yml          # Dependencies
│   └── pages/
│       ├── 1_Equipment_Overview.py
│       ├── 2_Alerts_Management.py
│       ├── 3_Predictions.py
│       └── 4_RCA_Assistant.py
│
└── README.md
```

## 🛠️ Setup Instructions

### Prerequisites
- Snowflake account with ACCOUNTADMIN role (or equivalent permissions)
- Warehouse with sufficient compute (COMPUTE_WH recommended)

### Step 1: Deploy Database Objects

Open Snowflake Worksheets and run the SQL files **in order**:

```sql
-- Run each file in sequence:
-- 1. sql/01_database_setup.sql
-- 2. sql/02_tables.sql
-- 3. sql/03_dynamic_tables.sql
-- 4. sql/04_views.sql
-- 5. sql/05_procedures.sql
-- 6. sql/06_functions.sql
-- 7. sql/07_tasks.sql
-- 8. sql/08_tests.sql
```

### Step 2: Generate Demo Data

After deploying procedures, generate synthetic data:

```sql
USE DATABASE PREDICTIVE_MAINTENANCE;
USE SCHEMA CORE;

-- Generate 3 months of demo data
CALL Generate_Demo_Data();

-- Verify data was created
SELECT 'Equipment' as table_name, COUNT(*) as row_count FROM Equipment_Master
UNION ALL
SELECT 'Sensor Readings', COUNT(*) FROM Sensor_Reading
UNION ALL
SELECT 'Work Orders', COUNT(*) FROM Work_Orders
UNION ALL
SELECT 'Maintenance Logs', COUNT(*) FROM Maintenance_Logs;
```

### Step 3: Run Initial Processing

```sql
-- Detect anomalies
CALL Detect_Anomalies();

-- Generate failure predictions
CALL Predict_Failures();

-- Generate alerts
CALL Generate_Alerts();

-- Create work orders for critical predictions
CALL Create_Work_Orders_From_Predictions();
```

### Step 4: Deploy Streamlit App

1. Navigate to **Snowsight → Projects → Streamlit**
2. Click **+ Streamlit App**
3. Configure:
   - **App name:** `PREDICTIVE_MAINTENANCE_COMMAND_CENTER`
   - **Database:** `PREDICTIVE_MAINTENANCE`
   - **Schema:** `CORE`
   - **Warehouse:** `COMPUTE_WH`
4. Copy contents of `streamlit_app/app.py` into the editor
5. Create `pages/` folder and add each page file
6. Upload `environment.yml` for dependencies

### Step 5: Enable Scheduled Tasks (Optional)

```sql
-- Enable automated processing tasks
ALTER TASK PREDICTIVE_MAINTENANCE.CORE.Anomaly_Detection_Task RESUME;
ALTER TASK PREDICTIVE_MAINTENANCE.CORE.Failure_Prediction_Task RESUME;
ALTER TASK PREDICTIVE_MAINTENANCE.CORE.Alert_Generation_Task RESUME;
ALTER TASK PREDICTIVE_MAINTENANCE.CORE.Work_Order_Creation_Task RESUME;
```

## 🧪 Running Tests

```sql
-- Run all platform tests
CALL Run_All_Tests();

-- View test results
SELECT * FROM Test_Results ORDER BY test_timestamp DESC;
```

## 📊 Key Tables

| Table | Description |
|-------|-------------|
| `Equipment_Master` | Equipment registry (pumps, motors, compressors) |
| `Sensor_Reading` | Raw sensor data (vibration, temperature, RPM) |
| `Sensor_Aggregation_5Min` | Dynamic table with rolling statistics |
| `Anomalies` | Detected anomalies with severity |
| `Failure_Predictions` | ML-generated failure forecasts |
| `Alerts` | System alerts for anomalies and predictions |
| `Work_Orders` | Maintenance work orders |
| `Maintenance_Logs` | Historical maintenance records |

## 🔧 Key Procedures

| Procedure | Description |
|-----------|-------------|
| `Generate_Demo_Data()` | Creates synthetic demonstration data |
| `Detect_Anomalies()` | Runs anomaly detection on sensor data |
| `Predict_Failures()` | Generates failure predictions |
| `Generate_Alerts()` | Creates alerts from anomalies/predictions |
| `Create_Work_Orders_From_Predictions()` | Auto-creates work orders |
| `RCA_Query(question, equipment_id)` | Natural language RCA interface |

## 🎨 Dashboard Pages

1. **Equipment Overview** - Health status, sensor trends, equipment details
2. **Alerts Management** - Active alerts, acknowledge/resolve workflow
3. **Predictions** - Failure forecasts with probability and factors
4. **RCA Assistant** - Natural language investigation chat

## 🔑 Technologies Used

- **Snowflake** - Data platform
- **Snowflake Dynamic Tables** - Real-time aggregation
- **Snowflake Cortex ML** - Anomaly detection & failure prediction
- **Snowflake Cortex LLM** - Natural language processing for RCA
- **Snowflake Tasks** - Scheduled automation
- **Streamlit in Snowflake** - Dashboard UI

## 📝 License

This project was created for the Hack2Skill Hackathon.

## 👥 Team

Built with ❄️ Snowflake
