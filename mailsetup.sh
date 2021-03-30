#!/bin/bash

apt install postfix dovecot-imapd dovecot-sieve opendkim opendkim-tools spamassassin spamc fail2ban postfix-policyd-spf-python

domain="$(cat /etc/mailname)"
subdomain="mail"
hostname="$subdomain.$domain"

postfix-version=$(postconf mail_version)
dovecot-version=$(dovecot --version)

postconf -e "myhostname = $subdomain.$domain"
mydestination = $myhostname, localhost.$mydomain, $mydomain
myorigin = $mydomain

certdir="/etc/letsencrypt/live/$domain"

# Change the cert/key files to the default locations of the Let's Encrypt cert/key.
postconf -e "smtpd_tls_key_file=$certdir/privkey.pem"
postconf -e "smtpd_tls_cert_file=$certdir/fullchain.pem"
# TODO postconf -e "stmpd_tls_dh1024_param_file=/etc/letsencrypt/ssl-dhparams.pem"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_auth_only = yes"
postconf -e "smtp_tls_security_level = may"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_loglevel = 1"
postconf -e "smtp_tls_CAfile=$certdir/cert.pem"
postconf -e "relay_domains = $mydestination"

postconf -e "mailbox_size_limit = 0"
postconf -e "message_size_limit = 0"
postconf -e "disable_vrfy_command = yes"
postconf -e "mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"

# Here we tell Postfix to look to Dovecot for authenticating users/passwords.
# Dovecot will be putting an authentication socket in /var/spool/postfix/private/auth
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"

# Postfix postscreen config.
postconf -e "postscreen_access_list = permit_mynetworks"
postconf -e "postscreen_greet_banner ="
postconf -e "postscreen_dnsbl_threshold = 5"
postconf -e "postscreen_dnsbl_sites = zen.spamhaus.org*3 bl.spamcop.net*2 b.barracudacentral.org*2"

postconf -e "postscreen_dnsbl_action = enforce"
postconf -e "postscreen_greet_action = enforce"

postconf -e "postscreen_dnsbl_whitelist_threshold = -2"

# Policyd config (python).
postconf -e "policyd-spf_time_limit = 3600s"
postconf -e "smtpd_relay_restrictions = permit_mynetworks
    permit_sasl_authenticated
    reject_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks
    permit_sasl_authenticated
    reject_unauth_destination
    check_policy_service unix:private/policyd-spf"

# NOTE: the trailing slash here, or for any directory name in the home_mailbox
# command, is necessary as it distinguishes a Maildir (which is the actual
# directories that what we want) from a spoolfile.
postconf -e "home_mailbox = Maildir/"

# Postfix master.cf integration of postscreen and spamassassin confirmation from
# Postfix postsreen README http://www.postfix.org/POSTSCREEN_README.html
sed -i "/^\s*-o/d;/^\s*submission/d;/^\s*smtp/d;/^\s*cleanup/d" /etc/postfix/master.cf

echo -n "# Postfix master.cg configuration.
smtp unix -             -       y       -       -       smtp
smtp inet n             -       n       -       1       postscreen
smtpd pass -            -       n       -       -       smtpd
  -o content_filter=spamassassin

dnsblog unix -          -       n       -       0       dnsblog
tlsproxy unix -         -       n       -       0       tlsproxy
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes

smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes

spamassassin unix -     n       n       -       -       pipe
  user=spamd argv=/usr/bin/spamc -f -e /usr/sbin/sendmail -oi -f \${sender} \${recipient}

policyd-spf unix  -     n       n       -       0       spawn
  user=policyd-spf argv=/usr/bin/policyd-spf" >> /etc/postfix/master.cf

# By default, dovecot has a configs in /etc/dovecot/conf.d/ These files are
# heavily commented and are great documentation if you want to read it, but
# there are many options most of which do not pertain to this situation.
# Instead, we simply overwrite /etc/dovecot/dovecot.conf because it's easier to
# manage. The original is located at /usr/share/dovecot if you want to check
# the defaults.

echo "Creating Dovecot config..."
echo "# %u for username
# %n for the name in name@domain.com
# %d for the domain
# %h the user's home directory

ssl = required
ssl_prefer_server_ciphers = yes

ssl_cert = <$certdir/fullchain.pem
ssl_key = <$certdir/privkey.pem
# Plaintext login. This is safe do to SSL further encryption is not warranted.
auth_mechanisms = plain login

protocols = \$protocols imap

imap_capability = +SPECIAL-USE

userdb {
	driver = passwd
}
passdb {
	driver = pam
}

# Our mail for each user will be in ~/Mail, and the inbox will be ~/Mail/Inbox
# The LAYOUT option is also important because otherwise, the boxes will be \`.Sent\` instead of \`Sent\`.
mail_location = maildir:~/Mail:INBOX=~/Mail/Inbox:LAYOUT=fs
namespace inbox {
	inbox = yes
	mailbox Drafts {
	special_use = \\Drafts
	auto = subscribe
}
	mailbox Junk {
	special_use = \\Junk
	auto = subscribe
	autoexpunge = 30d
}
	mailbox Sent {
	special_use = \\Sent
	auto = subscribe
}
	mailbox Trash {
	special_use = \\Trash
	auto = subscribe
}
	mailbox Archive {
	special_use = \\Archive
	auto = subscribe
}
}

# Allow Postfix to use Dovecot's authentication system.
service auth {
  unix_listener /var/spool/postfix/private/auth {
	mode = 0660
	user = postfix
	group = postfix
}
}

protocol lda {
  mail_plugins = \$mail_plugins sieve
}

protocol lmtp {
  mail_plugins = \$mail_plugins sieve
}

plugin {
    # The location of the user's main script storage. The active script
    # in this storage is used as the main user script executed during
    # delivery. The include extension fetches the :personal scripts
    # from this location. When ManageSieve is used, this is also where
    # scripts are uploaded. This example uses the file system as
    # storage, with all the user's scripts located in the directory
    # ~/sieve and the active script (symbolic link) located at
    # ~/.dovecot.sieve.
    sieve = file:~/sieve;active=~/.dovecot.sieve

    # If the user has no personal active script (i.e. if the location
    # indicated in sieve= does not exist or has no active script), use
    # this one:
    sieve_default = /var/lib/dovecot/sieve/default.sieve

    # The include extension fetches the :global scripts from this
    # location.
    sieve_global = /var/lib/dovecot/sieve/global/
}
" > /etc/dovecot/dovecot.conf


# Setting aliases these aliases assume you will have one main account to receive
# system mail as well as your personal mail.  You can also add additional accounts
# if you want more but one will be your main account this is safer then using
# the root account and retrieving mail with a root login. (SEE COMMENT AT END OF
# ALIAS SECTION)
echo "
mailer-daemon: root
postmaster:	root
hostmaster:	root
webmaster: root
usenet:	root
nobody:	root
abuse: root
mail: root
news: root
www: root
ftp: root
dmarc: root
root: $USER
" > /etc/aliases
# newaliases command must be run whenever the aliases file is changed.
newaliases

mkdir -p /var/lib/dovecot/sieve/

echo "require [\"fileinto\", \"mailbox\"];
if header :contains \"X-Spam-Flag\" \"YES\"
	{
		fileinto \"Junk\";
	}" > /var/lib/dovecot/sieve/default.sieve

cut -d: -f1 /etc/passwd | grep -q "^vmail" || useradd vmail
chown -R vmail:vmail /var/lib/dovecot
sievec /var/lib/dovecot/sieve/default.sieve

echo "Preparing user authentication..."
grep -q nullok /etc/pam.d/dovecot ||
echo "auth    required        pam_unix.so nullok
account required        pam_unix.so" >> /etc/pam.d/dovecot

echo "Setting up fail2ban jails..."
echo "[DEFAULT]
bantime = 24h
findtime = 20m
maxretry = 3
destemail root@localhost
sendername = fail2ban
mta = sendmail
action = %(action_mw)s
# action = %(action_mwl)s


[sshd]
enabled = true
#mode = normal
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
action = %(action_)s


[postfix]
enabled = true
mode = aggressive
port = smtp,465,submission
logpath = %(postfix_log)s
backend = %(postfix_backend)s
action = %(action_)s


# postfix-postscreen is independent of postifx aggressive mode
[postfix-postscreen]
enabled = true
findtime = 90m
port = smtp,465,submission,imap,imaps,pop3,pop3s
logpath = %(postfix_log)s
backend = %(postfix_backend)s
action = %(action_)s


[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps,submission,465,sieve
logpath = %(dovecot_log)s
backend = %(dovecot_backend)s
action = %(action_)s


[recidive]
enabled = true
findtime = 604800
bantime = 31557600
logpath = /var/log/fail2ban.log
backend = auto
action = %(action_)s
" > /etc/fail2ban/jails.local

echo "Writing postscreen filter..."
echo "# Fail2ban filter for selected Postfix/Postscreen SMTP rejections
[INCLUDES]
before = common.conf

[Definition]
_daemon = postfix(-/w+)?/\w+(?:/postscreen)?
_port = (?::\d+)?

prefregex = ^%(__prefix_line)s

failregex = (?:DNSBL rank \d for +)\[<HOST>\]
" > /etc/fail2ban/filter.d/postfix-postscreen.conf

echo "Writing policyd config..."
echo "# For a fully commented sample config file see policyd-spf.conf.commented

debugLevel = 2
# The policy server can operate in a test only mode.  This allows you to see the potential
# impact of SPF checking in your mail logs without rejecting mail.  Headers are prepended in
# messages, but message delivery is not affected.  This mode is not enabled by default.  To
# enable it, set TestOnly = 0.  I have enabled TestOnly mode via this script after reviewing
# your logs changing 0 to 1 will enable blocking.
TestOnly = 0

HELO_reject = Fail
Mail_From_reject = Fail

PermError_reject = False
TempError_Defer = False

skip_addresses = 127.0.0.0/8,::ffff:127.0.0.0/104,::1" > /etc/postfix-policyd-spf-python/policyd-spf.conf


# OpenDKIM

# A lot of the big name email services, like Google, will automatically
# reject mark as spam unfamiliar and unauthenticated email addresses. As in, the
# server will flatly reject the email, not even delivering it to someone's
# Spam folder.

# OpenDKIM is a way to authenticate your email so you can send to such services
# without a problem.

# Create an OpenDKIM key in the proper place with proper permissions.
echo "Generating openDKIM keys..."
mkdir -p /etc/postfix/dkim
opendkim-genkey -D /etc/postfix/dkim/ -d "$domain" -s default -v
chgrp opendkim /etc/postfix/dkim/*
chmod g+r /etc/postfix/dkim/*
chmod o+r /etc/postfix/dkim/default.txt

# Generate the OpenDKIM info:
echo "Configuring openDKIM..."
grep -q "$domain" /etc/postfix/dkim/keytable 2>/dev/null ||
echo "default._domainkey.$domain $domain:default:/etc/postfix/dkim/default.private" >> /etc/postfix/dkim/keytable

grep -q "$domain" /etc/postfix/dkim/signingtable 2>/dev/null ||
echo "*@$domain default._domainkey.$domain" >> /etc/postfix/dkim/signingtable

grep -q "127.0.0.1" /etc/postfix/dkim/trustedhosts 2>/dev/null || echo "localhost
127.0.0.1
mail.$domain
$domain
*.$domain" >> /etc/postfix/dkim/trustedhosts

# ...and source it from opendkim.conf
grep -q "^KeyTable" /etc/opendkim.conf 2>/dev/null || echo "KeyTable file:/etc/postfix/dkim/keytable
SigningTable refile:/etc/postfix/dkim/signingtable
InternalHosts refile:/etc/postfix/dkim/trustedhosts" >> /etc/opendkim.conf

sed -i '/^#Canonicalization/s/simple/relaxed\/simple/' /etc/opendkim.conf
sed -i '/^#Canonicalization/s/^#//' /etc/opendkim.conf

sed -e '/Socket/s/^#*/#/' -i /etc/opendkim.conf
sed -i '/\local:\/var\/run\/opendkim\/opendkim.sock/a \Socket\t\t\tinet:12301@localhost' /etc/opendkim.conf

# OpenDKIM daemon settings, removing previously activated socket.
sed -i "/^SOCKET/d" /etc/default/opendkim && echo "SOCKET=\"inet:12301@localhost\"" >> /etc/default/opendkim

# Here we add to postconf the needed settings for working with OpenDKIM
echo "Configuring Postfix with OpenDKIM settings..."
postconf -e "smtpd_sasl_security_options = noanonymous, noplaintext"
postconf -e "smtpd_sasl_tls_security_options = noanonymous"
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = inet:localhost:12301"
postconf -e "non_smtpd_milters = inet:localhost:12301"
postconf -e "mailbox_command = /usr/lib/dovecot/deliver"


for n in dovecot.service postfix.service opendkim.service spamassassin.service certbot.timer fail2ban.service; do
	printf "Enabling & Restarting %s..." "$n"
	systemctl enable "$n" && systemctl restart "$n" && printf " ...done\\n"
done

pval="$(tr -d "\n" </etc/postfix/dkim/default.txt | sed "s/k=rsa.* \"p=/k=rsa; p=/;s/\"\s*\"//;s/\"\s*).*//" | grep -o "p=.*")"
dkimentry="default._domainkey	TXT		v=DKIM1; k=rsa; $pval"
dmarcentry="_dmarc	TXT		v=DMARC1; p=quarantine; rua=mailto:dmarc@$domain; fo=1"
spfentry="@		TXT		v=spf1 mx a:$domain -all"

# Spamassassin
sed -i '/^OPTIONS/d;/^CRON/d' /etc/default/spamassassin
echo "SAHOME="/var/log/spamassassin/"
OPTIONS="--create-prefs --max-children 5 --helper-home-dir --username spamd -H ${SAHOME} -s ${SAHOME}spamd.log"
CRON=1" >> /etc/default/spamassassin

cp /etc/spamassassin/local.cf /etc/spamassassin/local.cf.bak
echo "rewrite_header Subject [***** SPAM _SCORE_ *****]
report_safe 2
required_score          5.0
use_bayes               1
bayes_auto_learn        1
" > /etc/spamassassin/local.cf

groupadd spamd
useradd -g spamd -s /usr/sbin/nologin -d /var/log/spamassassin spamd
mkdir /var/log/spamassassin
chown spamd:spamd /var/log/spamassassin

useradd -G mail dmarc

postfix check
postfix reload

echo "$dkimentry
$dmarcentry
$spfentry" > "$HOME/dns_txt_records"

echo "
*******************************************************************************
*******************************************************************************

    ATTENTION: Add these three records to your DNS TXT records on
    your registrar's site.

*******************************************************************************
*******************************************************************************

$dkimentry

$dmarcentry

$spfentry

Records also saved to ~/dns_txt_records for later reference."
