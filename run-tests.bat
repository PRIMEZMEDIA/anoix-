@echo off
cd /d "%~dp0"

set "MYSQL=C:\xampp\mysql\bin\mysql.exe"
set "DB=anoix_test"
set "HOST=127.0.0.1"
set "USER=root"
set "PASS="

echo [1/3] Creating disposable test database...
"%MYSQL%" --user=%USER% --execute "DROP DATABASE IF EXISTS `%DB%`; CREATE DATABASE `%DB%` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

for %%f in (database\migrations\*.sql database\seeds\*.sql) do (
    echo [2/3] Applying %%~nxf
    "%MYSQL%" --user=%USER% --database=%DB% < "%%~ff"
)

echo [3/3] Running tests...
set ANOIX_TEST_ALLOW=1
set DB_HOST=%HOST%
set DB_PORT=3306
set DB_DATABASE=%DB%
set DB_USERNAME=%USER%
set DB_PASSWORD=%PASS%
set "PHP=C:\xampp\php\php.exe"
"%PHP%" -d display_errors=1 -d error_reporting=E_ALL tests\run.php %*