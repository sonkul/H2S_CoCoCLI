# pages/4_RCA_Assistant.py
# RCA (Root Cause Analysis) Assistant - Natural Language Query Interface

import streamlit as st
from snowflake.snowpark.context import get_active_session
from datetime import datetime
import json

st.set_page_config(
    page_title="RCA Assistant | Predictive Maintenance",
    page_icon="🔍",
    layout="wide"
)

# Get Snowflake session
session = get_active_session()

# Initialize session state for query history
if 'rca_query_history' not in st.session_state:
    st.session_state.rca_query_history = []

# --- Page Header ---
st.title("🔍 Root Cause Analysis Assistant")
st.markdown("""
Ask questions about equipment issues in **natural language**. The AI-powered RCA Assistant 
analyzes sensor data, anomalies, maintenance history, and predictions to help you investigate 
root causes and understand equipment behavior.
""")

st.divider()

# --- Example Queries Section ---
with st.expander("💡 Example Queries", expanded=False):
    st.markdown("""
    Try asking questions like:
    
    - **Failure Investigation**: "Why did Pump P3 fail?" or "What caused the motor M2 issues?"
    - **Sensor Analysis**: "What sensors were abnormal before the motor shutdown?"
    - **Status Queries**: "What is the current status of Pump P1?"
    """)

# --- Query Input Section ---
st.subheader("Ask a Question")

col1, col2 = st.columns([3, 1])

with col2:
    equipment_list = session.sql("""
        SELECT equipment_id, name, equipment_type 
        FROM Equipment_Master 
        WHERE is_active = TRUE
        ORDER BY equipment_type, name
    """).to_pandas()
    
    equipment_options = ["🔄 Auto-detect from query"]
    equipment_mapping = {opt: None for opt in equipment_options}
    
    for _, row in equipment_list.iterrows():
        label = f"{row['EQUIPMENT_ID']} - {row['NAME']}"
        equipment_options.append(label)
        equipment_mapping[label] = row['EQUIPMENT_ID']
    
    selected_equipment_option = st.selectbox(
        "Equipment (optional)",
        equipment_options,
        index=0,
        help="Select specific equipment or let the assistant detect it from your query"
    )
    
    selected_equipment_id = equipment_mapping.get(selected_equipment_option)

with col1:
    user_query = st.text_area(
        "Enter your question",
        placeholder="E.g., Why did Pump P3 fail? What sensors were abnormal before the shutdown?",
        height=100
    )

analyze_clicked = st.button("🔍 Analyze", type="primary", use_container_width=True)

st.divider()

# --- Results Section ---
if analyze_clicked:
    if not user_query or user_query.strip() == "":
        st.warning("⚠️ Please enter a question to analyze.")
    else:
        with st.spinner("🔄 Analyzing data and generating response..."):
            try:
                escaped_query = user_query.replace("'", "''")
                
                if selected_equipment_id:
                    sql_call = f"CALL RCA_Query('{escaped_query}', '{selected_equipment_id}')"
                else:
                    sql_call = f"CALL RCA_Query('{escaped_query}', NULL)"
                
                result_df = session.sql(sql_call).to_pandas()
                
                if not result_df.empty:
                    result_col = result_df.columns[0]
                    result = result_df[result_col].iloc[0]
                    
                    if isinstance(result, dict):
                        result_dict = result
                    elif isinstance(result, str):
                        result_dict = json.loads(result)
                    else:
                        result_dict = result
                    
                    response_text = result_dict.get('response', 'No response generated.')
                    equipment_analyzed = result_dict.get('equipment_id')
                    query_time = result_dict.get('query_time')
                    
                    st.subheader("📋 Analysis Result")
                    
                    meta_col1, meta_col2 = st.columns(2)
                    with meta_col1:
                        if equipment_analyzed:
                            eq_name = session.sql(f"""
                                SELECT name, equipment_type 
                                FROM Equipment_Master 
                                WHERE equipment_id = '{equipment_analyzed}'
                            """).collect()
                            
                            if eq_name:
                                eq_info = f"{equipment_analyzed} - {eq_name[0]['NAME']} ({eq_name[0]['EQUIPMENT_TYPE']})"
                            else:
                                eq_info = equipment_analyzed
                            
                            st.info(f"🔧 **Equipment Analyzed:** {eq_info}")
                        else:
                            st.warning("⚠️ No specific equipment identified")
                    
                    with meta_col2:
                        if query_time:
                            st.info(f"🕐 **Query Time:** {query_time}")
                    
                    st.markdown("### Response")
                    with st.container():
                        st.markdown(response_text)
                    
                    history_entry = {
                        'query': user_query,
                        'equipment_id': equipment_analyzed,
                        'response_preview': response_text[:200] + ('...' if len(response_text) > 200 else ''),
                        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    }
                    st.session_state.rca_query_history.insert(0, history_entry)
                    st.session_state.rca_query_history = st.session_state.rca_query_history[:10]
                    
                    st.success("✅ Analysis completed successfully!")
                else:
                    st.error("❌ No response received from the RCA Assistant.")
                    
            except Exception as e:
                error_message = str(e)
                st.error(f"❌ An error occurred: {error_message}")
                with st.expander("🔧 Technical Details"):
                    st.code(error_message)

# --- Query History Section ---
st.divider()
st.subheader("📜 Recent Queries")

if st.session_state.rca_query_history:
    for i, entry in enumerate(st.session_state.rca_query_history):
        with st.expander(f"🔹 {entry['query'][:60]}{'...' if len(entry['query']) > 60 else ''}", expanded=(i == 0)):
            col1, col2 = st.columns([2, 1])
            with col1:
                st.markdown(f"**Query:** {entry['query']}")
            with col2:
                st.markdown(f"**Time:** {entry['timestamp']}")
                if entry['equipment_id']:
                    st.markdown(f"**Equipment:** {entry['equipment_id']}")
            
            st.markdown("**Response Preview:**")
            st.text(entry['response_preview'])
    
    if st.button("🗑️ Clear History"):
        st.session_state.rca_query_history = []
        st.rerun()
else:
    st.info("No queries yet. Ask a question above to get started!")

# --- Sidebar Section ---
st.sidebar.header("🔍 RCA Assistant")
st.sidebar.markdown("""
The RCA Assistant uses AI to analyze:
- 📊 Sensor readings
- ⚠️ Detected anomalies
- 🔧 Maintenance history
- 🔮 Active predictions
""")

st.sidebar.divider()

st.sidebar.subheader("📈 Quick Stats")
try:
    stats = session.sql("""
        SELECT 
            (SELECT COUNT(*) FROM Equipment_Master WHERE is_active = TRUE) AS total_equipment,
            (SELECT COUNT(*) FROM Anomalies WHERE detected_at >= DATEADD('day', -1, CURRENT_TIMESTAMP())) AS anomalies_24h,
            (SELECT COUNT(*) FROM Predictions WHERE is_active = TRUE) AS active_predictions
    """).collect()[0]
    
    st.sidebar.metric("Active Equipment", stats['TOTAL_EQUIPMENT'])
    st.sidebar.metric("Anomalies (24h)", stats['ANOMALIES_24H'])
    st.sidebar.metric("Active Predictions", stats['ACTIVE_PREDICTIONS'])
except Exception:
    st.sidebar.info("Stats unavailable")

st.divider()
st.caption("RCA Assistant | Powered by Snowflake Cortex LLM | Predictive Maintenance Platform")
