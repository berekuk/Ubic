# vim: ft=crontab
LOGDIR=/var/log/ubic

* * * * *   root   ubic-watchdog ubic.watchdog    >>$LOGDIR/watch_watchdog.log  2>>$LOGDIR/watch_watchdog.err.log
