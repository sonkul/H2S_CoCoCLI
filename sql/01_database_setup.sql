-- ============================================================================
-- Predictive Maintenance Platform - Database Setup
-- ============================================================================
-- This script creates the database, schema, and warehouse for the platform.
-- Run with: snow --config-file .\config.toml sql -f sql\01_database_setup.sql
-- ============================================================================

-- Create the main database
CREATE DATABASE IF NOT EXISTS PREDICTIVE_MAINTENANCE;

-- Create the core schema
CREATE SCHEMA IF NOT EXISTS PREDICTIVE_MAINTENANCE.CORE;

-- Set the context to use our schema
USE SCHEMA PREDICTIVE_MAINTENANCE.CORE;

-- Create or use the compute warehouse
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH 
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

-- Verify setup
SELECT 'Database setup complete' AS status;
