# vim: ft=crontab
LOGDIR=/var/log/ubic

* * * * *   root   ubic-watchdog ubic.watchdog    >>$LOGDIR/cron-watchdog.log  2>>$LOGDIR/cron-watchdog.err.log
