param([string]$Device)
& adb -s $Device root | Out-Host
Start-Sleep -Seconds 3
& adb -s $Device shell "sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db 'DELETE FROM sms; DELETE FROM threads;'" | Out-Host
& adb -s $Device shell pm clear com.google.android.apps.messaging | Out-Host
& adb -s $Device shell cmd statusbar collapse | Out-Host
