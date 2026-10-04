# Streamlit in Snowflake - Predictive Maintenance Command Center
# Main application entry point

import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Predictive Maintenance Command Center",
    page_icon="🏭",
    layout="wide"
)

# Get Snowflake session
session = get_active_session()

# Main title and description
st.title("🏭 Predictive Maintenance Command Center")
st.markdown('''
Monitor equipment health, track anomalies, view failure predictions, and investigate root causes 
using AI-powered analytics built entirely on Snowflake.
''')

st.divider()

# --- Summary Metrics Section ---
st.subheader("Equipment Health Summary")

# Query equipment health status
equipment_health = session.sql('''
    SELECT 
        COUNT(*) AS total,
        SUM(CASE WHEN health_status = 'Healthy' THEN 1 ELSE 0 END) AS healthy,
        SUM(CASE WHEN health_status = 'Warning' THEN 1 ELSE 0 END) AS warning,
        SUM(CASE WHEN health_status = 'Critical' THEN 1 ELSE 0 END) AS critical
    FROM (
        SELECT 
            e.equipment_id,
            CASE
                WHEN EXISTS (SELECT 1 FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                             AND p.is_active AND p.failure_probability >= 80) THEN 'Critical'
                WHEN EXISTS (SELECT 1 FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                             AND p.is_active AND p.failure_probability >= 50) THEN 'Warning'
                WHEN EXISTS (SELECT 1 FROM Anomalies a WHERE a.equipment_id = e.equipment_id 
                             AND a.severity = 'High' 
                             AND a.detected_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())) THEN 'Warning'
                ELSE 'Healthy'
            END AS health_status
        FROM Equipment_Master e
        WHERE e.is_active = TRUE
    )
''').collect()[0]

# Display metrics in columns
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        label="📊 Total Equipment", 
        value=equipment_health['TOTAL']
    )
with col2:
    st.metric(
        label="🟢 Healthy", 
        value=equipment_health['HEALTHY'],
        help="Equipment with no recent anomalies or active predictions"
    )
with col3:
    st.metric(
        label="🟡 Warning", 
        value=equipment_health['WARNING'],
        help="Equipment with predictions < 80% or recent high-severity anomalies"
    )
with col4:
    st.metric(
        label="🔴 Critical", 
        value=equipment_health['CRITICAL'],
        help="Equipment with failure probability >= 80%"
    )

# --- Sidebar Section ---
# Active alerts count
active_alerts = session.sql('''
    SELECT COUNT(*) AS count FROM Alerts WHERE status = 'New'
''').collect()[0]['COUNT']

acknowledged_alerts = session.sql('''
    SELECT COUNT(*) AS count FROM Alerts WHERE status = 'Acknowledged'
''').collect()[0]['COUNT']

st.sidebar.header("🚨 Alert Status")
st.sidebar.metric("New Alerts", active_alerts)
st.sidebar.metric("Acknowledged", acknowledged_alerts)

st.sidebar.divider()

# Navigation instructions
st.sidebar.header("📌 Navigation")
st.sidebar.info('''
Use the page selector in the sidebar to navigate:
- **Equipment Overview** - View equipment health
- **Alerts Management** - Manage alerts
- **Predictions** - View failure predictions
- **RCA Assistant** - AI-powered analysis
''')

# --- Recent Activity Section ---
st.divider()
st.subheader("Recent Activity")

col1, col2 = st.columns(2)

with col1:
    st.markdown("#### 🚨 Latest Alerts")
    recent_alerts = session.sql('''
        SELECT 
            a.severity,
            a.alert_type,
            e.name AS equipment_name,
            a.message,
            a.created_at,
            a.status
        FROM Alerts a
        JOIN Equipment_Master e ON a.equipment_id = e.equipment_id
        ORDER BY a.created_at DESC
        LIMIT 5
    ''').to_pandas()
    
    if not recent_alerts.empty:
        for _, alert in recent_alerts.iterrows():
            severity_icon = {
                'Critical': '🔴',
                'High': '🟠',
                'Medium': '🟡',
                'Low': '🟢'
            }.get(alert['SEVERITY'], '⚪')
            
            with st.container():
                msg = str(alert['MESSAGE'])[:100]
                ellipsis = '...' if len(str(alert['MESSAGE'])) > 100 else ''
                st.markdown(f'''
                {severity_icon} **{alert['EQUIPMENT_NAME']}** - {alert['ALERT_TYPE']}  
                _{msg}{ellipsis}_  
                <small style="color: gray;">{alert['CREATED_AT']} | Status: {alert['STATUS']}</small>
                ''', unsafe_allow_html=True)
                st.markdown("---")
    else:
        st.info("No recent alerts. Run Generate_Alerts() to create some.")

with col2:
    st.markdown("#### 🔮 Top Failure Predictions")
    top_predictions = session.sql('''
        SELECT 
            e.name AS equipment_name,
            e.equipment_type,
            p.failure_probability,
            p.predicted_failure_start,
            p.generated_at
        FROM Predictions p
        JOIN Equipment_Master e ON p.equipment_id = e.equipment_id
        WHERE p.is_active = TRUE
        ORDER BY p.failure_probability DESC
        LIMIT 5
    ''').to_pandas()
    
    if not top_predictions.empty:
        for _, pred in top_predictions.iterrows():
            prob = pred['FAILURE_PROBABILITY']
            prob_icon = '🔴' if prob >= 80 else ('🟠' if prob >= 60 else '🟡')
            
            with st.container():
                st.markdown(f'''
                {prob_icon} **{pred['EQUIPMENT_NAME']}** ({pred['EQUIPMENT_TYPE']})  
                Failure Probability: **{prob:.0f}%**  
                <small style="color: gray;">Predicted: {pred['PREDICTED_FAILURE_START']}</small>
                ''', unsafe_allow_html=True)
                st.progress(prob / 100)
                st.markdown("---")
    else:
        st.info("No active predictions. Run Predict_Failures() to generate predictions.")

# --- System Status Section ---
st.divider()
st.subheader("System Status")

col1, col2, col3 = st.columns(3)

with col1:
    equipment_count = session.sql("SELECT COUNT(*) AS cnt FROM Equipment_Master WHERE is_active = TRUE").collect()[0]['CNT']
    st.metric("Active Equipment", equipment_count)
    
with col2:
    sensor_count = session.sql("SELECT COUNT(*) AS cnt FROM Sensor_Readings").collect()[0]['CNT']
    st.metric("Total Sensor Readings", f"{sensor_count:,}")

with col3:
    anomaly_count = session.sql('''
        SELECT COUNT(*) AS cnt FROM Anomalies 
        WHERE detected_at >= DATEADD('day', -1, CURRENT_TIMESTAMP())
    ''').collect()[0]['CNT']
    st.metric("Anomalies (24h)", anomaly_count)

# --- Footer ---
st.divider()
st.caption("Predictive Maintenance Platform | Built on Snowflake | Hack2Skill Hackathon")
