# Streamlit in Snowflake - Equipment Overview Page
# Displays equipment list with health status and detailed equipment view

import streamlit as st
from snowflake.snowpark.context import get_active_session

# Page configuration
st.set_page_config(
    page_title="Equipment Overview | Predictive Maintenance",
    page_icon="📊",
    layout="wide"
)

# Get Snowflake session
session = get_active_session()

# Page title and description
st.title("📊 Equipment Overview")
st.markdown("""
View all equipment with health status indicators, anomaly counts, and failure predictions.
Select an equipment to see detailed sensor readings, anomalies, alerts, and maintenance history.
""")

st.divider()

# --- Equipment List Section ---
st.subheader("Equipment List")

# Query equipment with health status, anomaly count, and max prediction probability
equipment_df = session.sql("""
    SELECT 
        e.equipment_id,
        e.name,
        e.equipment_type,
        e.location,
        CASE
            WHEN EXISTS (SELECT 1 FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                         AND p.is_active AND p.failure_probability >= 80) THEN 'Critical'
            WHEN EXISTS (SELECT 1 FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                         AND p.is_active AND p.failure_probability >= 50) THEN 'Warning'
            WHEN EXISTS (SELECT 1 FROM Anomalies a WHERE a.equipment_id = e.equipment_id 
                         AND a.severity = 'High' 
                         AND a.detected_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())) THEN 'Warning'
            ELSE 'Healthy'
        END AS health_status,
        COALESCE((SELECT COUNT(*) FROM Anomalies a WHERE a.equipment_id = e.equipment_id 
                  AND a.detected_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())), 0) AS anomalies_24h,
        COALESCE((SELECT MAX(failure_probability) FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                  AND p.is_active), 0) AS max_failure_prob
    FROM Equipment_Master e
    WHERE e.is_active = TRUE
    ORDER BY 
        CASE 
            WHEN EXISTS (SELECT 1 FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                         AND p.is_active AND p.failure_probability >= 80) THEN 1
            WHEN EXISTS (SELECT 1 FROM Predictions p WHERE p.equipment_id = e.equipment_id 
                         AND p.is_active AND p.failure_probability >= 50) THEN 2
            WHEN EXISTS (SELECT 1 FROM Anomalies a WHERE a.equipment_id = e.equipment_id 
                         AND a.severity = 'High' 
                         AND a.detected_at >= DATEADD('hour', -24, CURRENT_TIMESTAMP())) THEN 2
            ELSE 3
        END,
        e.name
""").to_pandas()

if not equipment_df.empty:
    # Add health status icons to the dataframe for display
    def get_health_icon(status):
        icons = {
            'Critical': '🔴 Critical',
            'Warning': '🟡 Warning',
            'Healthy': '🟢 Healthy'
        }
        return icons.get(status, '⚪ Unknown')
    
    # Create a display dataframe with icons
    display_df = equipment_df.copy()
    display_df['HEALTH_STATUS'] = display_df['HEALTH_STATUS'].apply(get_health_icon)
    
    # Rename columns for better display
    display_df = display_df.rename(columns={
        'EQUIPMENT_ID': 'Equipment ID',
        'NAME': 'Name',
        'EQUIPMENT_TYPE': 'Type',
        'LOCATION': 'Location',
        'HEALTH_STATUS': 'Health Status',
        'ANOMALIES_24H': 'Anomalies (24h)',
        'MAX_FAILURE_PROB': 'Max Prediction %'
    })
    
    # Display summary counts
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Total Equipment", len(equipment_df))
    with col2:
        healthy_count = len(equipment_df[equipment_df['HEALTH_STATUS'] == 'Healthy'])
        st.metric("🟢 Healthy", healthy_count)
    with col3:
        warning_count = len(equipment_df[equipment_df['HEALTH_STATUS'] == 'Warning'])
        st.metric("🟡 Warning", warning_count)
    with col4:
        critical_count = len(equipment_df[equipment_df['HEALTH_STATUS'] == 'Critical'])
        st.metric("🔴 Critical", critical_count)
    
    st.markdown("")
    
    # Filter options
    col1, col2, col3 = st.columns(3)
    with col1:
        type_filter = st.multiselect(
            "Filter by Type",
            options=equipment_df['EQUIPMENT_TYPE'].unique().tolist(),
            default=equipment_df['EQUIPMENT_TYPE'].unique().tolist()
        )
    with col2:
        status_filter = st.multiselect(
            "Filter by Health Status",
            options=['Healthy', 'Warning', 'Critical'],
            default=['Healthy', 'Warning', 'Critical']
        )
    with col3:
        search_term = st.text_input("Search by Name or ID", "")
    
    # Apply filters to display dataframe
    filtered_df = display_df.copy()
    
    # Filter by type
    if type_filter:
        filtered_df = filtered_df[filtered_df['Type'].isin(type_filter)]
    
    # Filter by status (need to check if the icon string contains the status)
    if status_filter:
        status_mask = filtered_df['Health Status'].apply(
            lambda x: any(s in x for s in status_filter)
        )
        filtered_df = filtered_df[status_mask]
    
    # Filter by search term
    if search_term:
        search_mask = (
            filtered_df['Equipment ID'].str.contains(search_term, case=False, na=False) |
            filtered_df['Name'].str.contains(search_term, case=False, na=False)
        )
        filtered_df = filtered_df[search_mask]
    
    # Display equipment table
    st.dataframe(
        filtered_df,
        column_config={
            "Equipment ID": st.column_config.TextColumn("Equipment ID", width="small"),
            "Name": st.column_config.TextColumn("Name", width="medium"),
            "Type": st.column_config.TextColumn("Type", width="small"),
            "Location": st.column_config.TextColumn("Location", width="medium"),
            "Health Status": st.column_config.TextColumn("Health Status", width="medium"),
            "Anomalies (24h)": st.column_config.NumberColumn("Anomalies (24h)", width="small"),
            "Max Prediction %": st.column_config.ProgressColumn(
                "Max Prediction %", 
                min_value=0, 
                max_value=100,
                format="%.0f%%"
            ),
        },
        hide_index=True,
        use_container_width=True
    )
    
    # --- Equipment Detail Section ---
    st.divider()
    st.subheader("Equipment Details")
    
    # Create options list for selectbox with name and ID
    equipment_options = [
        f"{row['EQUIPMENT_ID']} - {row['NAME']}" 
        for _, row in equipment_df.iterrows()
    ]
    
    selected_option = st.selectbox(
        "Select equipment for detailed view:",
        options=equipment_options,
        index=None,
        placeholder="Choose an equipment..."
    )
    
    if selected_option:
        # Extract equipment ID from selection
        selected_equipment_id = selected_option.split(" - ")[0]
        
        # Get equipment details
        equipment_info = equipment_df[equipment_df['EQUIPMENT_ID'] == selected_equipment_id].iloc[0]
        
        # Display equipment info card
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.markdown(f"**Equipment ID:** {equipment_info['EQUIPMENT_ID']}")
        with col2:
            st.markdown(f"**Name:** {equipment_info['NAME']}")
        with col3:
            st.markdown(f"**Type:** {equipment_info['EQUIPMENT_TYPE']}")
        with col4:
            st.markdown(f"**Location:** {equipment_info['LOCATION']}")
        
        # Health status with icon
        health_icon = get_health_icon(equipment_info['HEALTH_STATUS'])
        st.markdown(f"**Health Status:** {health_icon}")
        
        st.markdown("")
        
        # Tabs for different data views
        tab1, tab2, tab3, tab4 = st.tabs([
            "📈 Sensor Readings", 
            "⚠️ Anomalies", 
            "🚨 Alerts", 
            "🔧 Maintenance History"
        ])
        
        with tab1:
            st.markdown("#### Recent Sensor Readings (Last 24 Hours)")
            
            # Query sensor readings for the selected equipment
            sensor_data = session.sql(f"""
                SELECT 
                    sensor_type,
                    reading_timestamp,
                    sensor_value
                FROM Sensor_Readings
                WHERE equipment_id = '{selected_equipment_id}'
                AND reading_timestamp >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
                ORDER BY reading_timestamp DESC
                LIMIT 500
            """).to_pandas()
            
            if not sensor_data.empty:
                # Get unique sensor types
                sensor_types = sensor_data['SENSOR_TYPE'].unique().tolist()
                
                # Option to select which sensors to display
                selected_sensors = st.multiselect(
                    "Select sensor types to display:",
                    options=sensor_types,
                    default=sensor_types
                )
                
                if selected_sensors:
                    # Filter by selected sensors
                    filtered_sensor_data = sensor_data[
                        sensor_data['SENSOR_TYPE'].isin(selected_sensors)
                    ]
                    
                    # Create line chart
                    # Pivot data for charting
                    try:
                        chart_data = filtered_sensor_data.pivot_table(
                            index='READING_TIMESTAMP', 
                            columns='SENSOR_TYPE', 
                            values='SENSOR_VALUE',
                            aggfunc='mean'
                        ).reset_index()
                        
                        chart_data = chart_data.sort_values('READING_TIMESTAMP')
                        chart_data = chart_data.set_index('READING_TIMESTAMP')
                        
                        st.line_chart(chart_data, use_container_width=True)
                        
                        # Show summary statistics
                        st.markdown("##### Sensor Statistics")
                        stats_df = filtered_sensor_data.groupby('SENSOR_TYPE').agg({
                            'SENSOR_VALUE': ['min', 'max', 'mean', 'std', 'count']
                        }).round(2)
                        stats_df.columns = ['Min', 'Max', 'Mean', 'Std Dev', 'Reading Count']
                        st.dataframe(stats_df, use_container_width=True)
                        
                    except Exception as e:
                        st.warning(f"Unable to create chart: {str(e)}")
                        # Fall back to simple table display
                        st.dataframe(filtered_sensor_data, use_container_width=True)
                else:
                    st.info("Select at least one sensor type to display readings.")
            else:
                st.info("No sensor readings available for the last 24 hours for this equipment.")
        
        with tab2:
            st.markdown("#### Detected Anomalies")
            
            # Query anomalies for the selected equipment
            anomalies_data = session.sql(f"""
                SELECT 
                    severity,
                    sensor_type,
                    detected_at,
                    actual_value,
                    expected_value,
                    confidence
                FROM Anomalies
                WHERE equipment_id = '{selected_equipment_id}'
                ORDER BY detected_at DESC
                LIMIT 50
            """).to_pandas()
            
            if not anomalies_data.empty:
                # Add severity icons
                def get_severity_icon(severity):
                    icons = {
                        'High': '🔴',
                        'Medium': '🟡',
                        'Low': '🟢'
                    }
                    return icons.get(severity, '⚪')
                
                # Display summary
                col1, col2, col3 = st.columns(3)
                with col1:
                    high_count = len(anomalies_data[anomalies_data['SEVERITY'] == 'High'])
                    st.metric("🔴 High Severity", high_count)
                with col2:
                    medium_count = len(anomalies_data[anomalies_data['SEVERITY'] == 'Medium'])
                    st.metric("🟡 Medium Severity", medium_count)
                with col3:
                    low_count = len(anomalies_data[anomalies_data['SEVERITY'] == 'Low'])
                    st.metric("🟢 Low Severity", low_count)
                
                # Display anomalies table
                display_anomalies = anomalies_data.copy()
                display_anomalies['SEVERITY'] = display_anomalies['SEVERITY'].apply(
                    lambda x: f"{get_severity_icon(x)} {x}"
                )
                display_anomalies = display_anomalies.rename(columns={
                    'SEVERITY': 'Severity',
                    'SENSOR_TYPE': 'Sensor Type',
                    'DETECTED_AT': 'Detected At',
                    'ACTUAL_VALUE': 'Actual Value',
                    'EXPECTED_VALUE': 'Expected Value',
                    'CONFIDENCE': 'Confidence'
                })
                
                st.dataframe(
                    display_anomalies,
                    column_config={
                        "Confidence": st.column_config.ProgressColumn(
                            "Confidence",
                            min_value=0,
                            max_value=1,
                            format="%.2f"
                        )
                    },
                    hide_index=True,
                    use_container_width=True
                )
            else:
                st.info("No anomalies detected for this equipment.")
        
        with tab3:
            st.markdown("#### Alerts")
            
            # Query alerts for the selected equipment
            alerts_data = session.sql(f"""
                SELECT 
                    severity,
                    alert_type,
                    message,
                    created_at,
                    status,
                    acknowledged_at,
                    resolved_at
                FROM Alerts
                WHERE equipment_id = '{selected_equipment_id}'
                ORDER BY created_at DESC
                LIMIT 50
            """).to_pandas()
            
            if not alerts_data.empty:
                # Add severity icons
                def get_alert_severity_icon(severity):
                    icons = {
                        'Critical': '🔴',
                        'High': '🟠',
                        'Medium': '🟡',
                        'Low': '🟢'
                    }
                    return icons.get(severity, '⚪')
                
                # Display summary by status
                col1, col2, col3 = st.columns(3)
                with col1:
                    new_count = len(alerts_data[alerts_data['STATUS'] == 'New'])
                    st.metric("🆕 New", new_count)
                with col2:
                    ack_count = len(alerts_data[alerts_data['STATUS'] == 'Acknowledged'])
                    st.metric("✅ Acknowledged", ack_count)
                with col3:
                    resolved_count = len(alerts_data[alerts_data['STATUS'] == 'Resolved'])
                    st.metric("✓ Resolved", resolved_count)
                
                # Display alerts table
                display_alerts = alerts_data.copy()
                display_alerts['SEVERITY'] = display_alerts['SEVERITY'].apply(
                    lambda x: f"{get_alert_severity_icon(x)} {x}"
                )
                display_alerts = display_alerts.rename(columns={
                    'SEVERITY': 'Severity',
                    'ALERT_TYPE': 'Alert Type',
                    'MESSAGE': 'Message',
                    'CREATED_AT': 'Created At',
                    'STATUS': 'Status',
                    'ACKNOWLEDGED_AT': 'Acknowledged At',
                    'RESOLVED_AT': 'Resolved At'
                })
                
                st.dataframe(
                    display_alerts,
                    hide_index=True,
                    use_container_width=True
                )
            else:
                st.info("No alerts for this equipment.")
        
        with tab4:
            st.markdown("#### Maintenance History")
            
            # Query maintenance logs for the selected equipment
            maintenance_data = session.sql(f"""
                SELECT 
                    maintenance_type,
                    technician,
                    start_time,
                    end_time,
                    description
                FROM Maintenance_Logs
                WHERE equipment_id = '{selected_equipment_id}'
                ORDER BY start_time DESC
                LIMIT 50
            """).to_pandas()
            
            if not maintenance_data.empty:
                # Add maintenance type icons
                def get_maintenance_icon(mtype):
                    icons = {
                        'Preventive': '🔧',
                        'Corrective': '🛠️',
                        'Emergency': '🚨'
                    }
                    return icons.get(mtype, '⚙️')
                
                # Display summary by type
                col1, col2, col3 = st.columns(3)
                with col1:
                    preventive_count = len(maintenance_data[maintenance_data['MAINTENANCE_TYPE'] == 'Preventive'])
                    st.metric("🔧 Preventive", preventive_count)
                with col2:
                    corrective_count = len(maintenance_data[maintenance_data['MAINTENANCE_TYPE'] == 'Corrective'])
                    st.metric("🛠️ Corrective", corrective_count)
                with col3:
                    emergency_count = len(maintenance_data[maintenance_data['MAINTENANCE_TYPE'] == 'Emergency'])
                    st.metric("🚨 Emergency", emergency_count)
                
                # Display maintenance table
                display_maintenance = maintenance_data.copy()
                display_maintenance['MAINTENANCE_TYPE'] = display_maintenance['MAINTENANCE_TYPE'].apply(
                    lambda x: f"{get_maintenance_icon(x)} {x}"
                )
                display_maintenance = display_maintenance.rename(columns={
                    'MAINTENANCE_TYPE': 'Type',
                    'TECHNICIAN': 'Technician',
                    'START_TIME': 'Start Time',
                    'END_TIME': 'End Time',
                    'DESCRIPTION': 'Description'
                })
                
                st.dataframe(
                    display_maintenance,
                    hide_index=True,
                    use_container_width=True
                )
            else:
                st.info("No maintenance history available for this equipment.")
    
    else:
        st.info("Select an equipment from the dropdown above to view detailed information.")

else:
    st.warning("No equipment data available. Please ensure the Equipment_Master table has been populated.")
    st.info("Run the Generate_Demo_Data() procedure to populate the database with sample data.")

# --- Footer ---
st.divider()
st.caption("Equipment Overview | Predictive Maintenance Platform | Built on Snowflake")
