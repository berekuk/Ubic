# vim: ft=crontab

* * * * *   root   ubic-watchdog >> /var/log/ubic/watchdog.log 2>>/var/log/ubic/watchdog.err.log
* * * * *   root   ubic-update >> /var/log/ubic/update.log 2>>/var/log/ubic/update.err.log

