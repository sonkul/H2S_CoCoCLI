# Streamlit in Snowflake - Alerts Management Page
# Display and manage alerts with filtering, sorting, and actions

import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Alerts Management - Predictive Maintenance",
    page_icon="🚨",
    layout="wide"
)

# Get Snowflake session
session = get_active_session()

# Page title and description
st.title("🚨 Alerts Management")
st.markdown("""
Monitor, acknowledge, and resolve equipment alerts. Alerts are automatically generated 
when anomalies are detected or failure predictions exceed thresholds.
""")

st.divider()

# --- Summary Metrics Section ---
st.subheader("Alert Summary")

# Query alert counts by status
alert_summary = session.sql("""
    SELECT 
        SUM(CASE WHEN status = 'New' THEN 1 ELSE 0 END) AS new_count,
        SUM(CASE WHEN status = 'Acknowledged' THEN 1 ELSE 0 END) AS acknowledged_count,
        SUM(CASE WHEN status = 'Resolved' THEN 1 ELSE 0 END) AS resolved_count,
        COUNT(*) AS total_count
    FROM Alerts
""").collect()[0]

col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        label="🔴 New",
        value=alert_summary['NEW_COUNT'],
        help="Alerts requiring attention"
    )
with col2:
    st.metric(
        label="🟡 Acknowledged",
        value=alert_summary['ACKNOWLEDGED_COUNT'],
        help="Alerts that have been acknowledged but not resolved"
    )
with col3:
    st.metric(
        label="🟢 Resolved",
        value=alert_summary['RESOLVED_COUNT'],
        help="Alerts that have been resolved"
    )
with col4:
    st.metric(
        label="📊 Total",
        value=alert_summary['TOTAL_COUNT'],
        help="Total alerts in the system"
    )

st.divider()

# --- Filters Section ---
st.subheader("Filters")

filter_col1, filter_col2 = st.columns(2)

with filter_col1:
    status_options = ["All", "New", "Acknowledged", "Resolved"]
    status_filter = st.selectbox(
        "Status",
        options=status_options,
        index=0,
        help="Filter alerts by status"
    )

with filter_col2:
    severity_options = ["All", "Critical", "High", "Medium", "Low"]
    severity_filter = st.selectbox(
        "Severity",
        options=severity_options,
        index=0,
        help="Filter alerts by severity"
    )

# Build the WHERE clause based on filters
where_conditions = []
if status_filter != "All":
    where_conditions.append(f"a.status = '{status_filter}'")
if severity_filter != "All":
    where_conditions.append(f"a.severity = '{severity_filter}'")

where_clause = "WHERE " + " AND ".join(where_conditions) if where_conditions else ""

# --- Alerts Table Section ---
st.divider()
st.subheader("Alerts")

# Query alerts with filtering and sorting
alerts_query = f"""
    SELECT 
        a.alert_id,
        a.equipment_id,
        e.name AS equipment_name,
        a.alert_type,
        a.severity,
        a.message,
        a.created_at,
        a.status,
        a.acknowledged_at,
        a.resolved_at
    FROM Alerts a
    JOIN Equipment_Master e ON a.equipment_id = e.equipment_id
    {where_clause}
    ORDER BY 
        CASE a.severity 
            WHEN 'Critical' THEN 1 
            WHEN 'High' THEN 2 
            WHEN 'Medium' THEN 3 
            WHEN 'Low' THEN 4 
            ELSE 5 
        END,
        a.created_at DESC
"""

alerts_df = session.sql(alerts_query).to_pandas()

if not alerts_df.empty:
    st.caption(f"Showing {len(alerts_df)} alert(s)")
    
    for idx, alert in alerts_df.iterrows():
        severity_icons = {'Critical': '🔴', 'High': '🟠', 'Medium': '🟡', 'Low': '🟢'}
        severity_icon = severity_icons.get(alert['SEVERITY'], '⚪')
        
        status_colors = {'New': 'red', 'Acknowledged': 'orange', 'Resolved': 'green'}
        status_color = status_colors.get(alert['STATUS'], 'gray')
        
        with st.expander(
            f"{severity_icon} **{alert['EQUIPMENT_NAME']}** | {alert['ALERT_TYPE']} | {alert['SEVERITY']} | Status: {alert['STATUS']}",
            expanded=(alert['STATUS'] == 'New')
        ):
            col1, col2 = st.columns([2, 1])
            
            with col1:
                st.markdown(f"**Equipment:** {alert['EQUIPMENT_NAME']} ({alert['EQUIPMENT_ID']})")
                st.markdown(f"**Type:** {alert['ALERT_TYPE']}")
                st.markdown(f"**Severity:** {severity_icon} {alert['SEVERITY']}")
                st.markdown(f"**Message:** {alert['MESSAGE']}")
            
            with col2:
                st.markdown(f"**Status:** :{status_color}[{alert['STATUS']}]")
                st.markdown(f"**Created:** {alert['CREATED_AT']}")
                if alert['ACKNOWLEDGED_AT']:
                    st.markdown(f"**Acknowledged:** {alert['ACKNOWLEDGED_AT']}")
                if alert['RESOLVED_AT']:
                    st.markdown(f"**Resolved:** {alert['RESOLVED_AT']}")
            
            st.markdown("---")
            action_col1, action_col2, action_col3 = st.columns([1, 1, 2])
            
            alert_id = alert['ALERT_ID']
            
            with action_col1:
                if alert['STATUS'] == 'New':
                    if st.button("✅ Acknowledge", key=f"ack_{alert_id}", use_container_width=True):
                        session.sql(f"""
                            UPDATE Alerts 
                            SET status = 'Acknowledged', acknowledged_at = CURRENT_TIMESTAMP()
                            WHERE alert_id = '{alert_id}'
                        """).collect()
                        st.success(f"Alert acknowledged!")
                        st.rerun()
                else:
                    st.button("✅ Acknowledge", key=f"ack_{alert_id}", disabled=True, use_container_width=True)
            
            with action_col2:
                if alert['STATUS'] in ['New', 'Acknowledged']:
                    if st.button("🔒 Resolve", key=f"resolve_{alert_id}", use_container_width=True):
                        session.sql(f"""
                            UPDATE Alerts 
                            SET status = 'Resolved', resolved_at = CURRENT_TIMESTAMP(),
                                acknowledged_at = COALESCE(acknowledged_at, CURRENT_TIMESTAMP())
                            WHERE alert_id = '{alert_id}'
                        """).collect()
                        st.success(f"Alert resolved!")
                        st.rerun()
                else:
                    st.button("🔒 Resolve", key=f"resolve_{alert_id}", disabled=True, use_container_width=True)

else:
    st.info("No alerts found matching the selected filters.")

# --- Bulk Actions Section ---
st.divider()
st.subheader("Bulk Actions")

bulk_col1, bulk_col2, bulk_col3 = st.columns(3)

with bulk_col1:
    new_alert_count = alert_summary['NEW_COUNT']
    if st.button(f"✅ Acknowledge All New ({new_alert_count})", disabled=(new_alert_count == 0), use_container_width=True):
        session.sql("""
            UPDATE Alerts SET status = 'Acknowledged', acknowledged_at = CURRENT_TIMESTAMP()
            WHERE status = 'New'
        """).collect()
        st.success(f"Acknowledged {new_alert_count} alerts!")
        st.rerun()

with bulk_col2:
    ack_alert_count = alert_summary['ACKNOWLEDGED_COUNT']
    if st.button(f"🔒 Resolve All Acknowledged ({ack_alert_count})", disabled=(ack_alert_count == 0), use_container_width=True):
        session.sql("""
            UPDATE Alerts SET status = 'Resolved', resolved_at = CURRENT_TIMESTAMP()
            WHERE status = 'Acknowledged'
        """).collect()
        st.success(f"Resolved {ack_alert_count} alerts!")
        st.rerun()

# --- Footer ---
st.divider()
st.caption("Predictive Maintenance Platform | Built on Snowflake")
