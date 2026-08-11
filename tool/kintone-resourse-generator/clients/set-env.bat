@echo off

for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"

if not defined KINTONE_BASE_URL set "KINTONE_BASE_URL=https://bm5z6rewq6pg.cybozu.com"
if not defined KINTONE_DOWNLOAD_PATH set "KINTONE_DOWNLOAD_PATH=%BASE_PATH%download"
if not defined KINTONE_CONFIG_PATH set "KINTONE_CONFIG_PATH=%BASE_PATH%config"
if not defined KINTONE_TEMPLATE_PATH set "KINTONE_TEMPLATE_PATH=%BASE_PATH%template"
if not defined KINTONE_CHECK_OUTPUT_PATH set "KINTONE_CHECK_OUTPUT_PATH=%BASE_PATH%checked"
if not defined KINTONE_LOG_PATH set "KINTONE_LOG_PATH=%BASE_PATH%log"

rem KINTONE_LOGIN / KINTONE_PASSWORD を指定すると、実行時のログインID/パスワードの
rem プロンプト入力をスキップする。空のままなら実行時にその場で入力を求められる。
rem 平文でパスワードを保存することになるため、このファイルの共有・コミットには注意すること。
if not defined KINTONE_LOGIN set "KINTONE_LOGIN="
if not defined KINTONE_PASSWORD set "KINTONE_PASSWORD="

rem SpaceId・ConfigNameは各.batの引数で毎回明示的に渡す（環境変数の既定値は持たせていない）。
rem 例: download-kintone-resources.bat 2 NJK-クラス-テクニカル
rem     apply-kintone-resources.bat NJK-クラス-テクニカル
rem     check-kintone-resources.bat NJK-クラス-テクニカル