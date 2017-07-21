PS1='[\[\033[$(if [ "$?" != "0" ];then echo "35"; else echo "36"; fi)m\]\t\[\033[00m\] \u@\h \W]$ '
