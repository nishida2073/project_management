@echo off

set "BASE_DIR=%~dp0"

if not defined PKG_CONFIG_PATH set "PKG_CONFIG_PATH=%BASE_DIR%config\package_definition.xlsx"
if not defined PKG_WORK_PATH set "PKG_WORK_PATH=%BASE_DIR%work"
if not defined PKG_OUTPUT_PATH set "PKG_OUTPUT_PATH=%BASE_DIR%output"
if not defined PKG_LOG_PATH set "PKG_LOG_PATH=%BASE_DIR%log"
if not defined PKG_SOURCE_BASE set "PKG_SOURCE_BASE=%BASE_DIR%"
if not defined PKG_SHEETS_INCLUDE set "PKG_SHEETS_INCLUDE="
if not defined PKG_SHEETS_EXCLUDE set "PKG_SHEETS_EXCLUDE="
