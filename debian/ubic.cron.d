# vim: ft=crontab
LOGDIR=/var/log/ubic

* * * * *   root   ubic-watchdog    >>$LOGDIR/watchdog.log  2>>$LOGDIR/watchdog.err.log
* * * * *   root   ubic-update      >>$LOGDIR/update.log    2>>$LOGDIR/update.err.log
