# standalone_email.server

This script will setup an email server on a Debian/Ubuntu based server.  Unlike
similar scripts this installs a standalone email server, there is no need to install
an Nginx or Apache placeholder website and has been tested on Debian 10 Buster
and Ubuntu 18.04LTS.

**Read this readme and the script's comments before running it.**

When prompted by the dialog menu at the beginning of the postfix install, select
"Internet Site", then give your FQDN (Fully Qualified Domain Name) without any
subdomain, ie. `domain.com` **not** `mail@domain.com`.

## Certbot

Make sure your DNS records are updated before running _certbot_ you can use the
`whois` command to verify that any changes you've made have been propagated
otherwise you will receive and error from _certbot_.  Also before you run script
your SSL Certificate must be obtained.  This can be done but running this
command.

`sudo certbot certonly --standalone -d domain.com`

***IMPORTANT*** Certbot uses short term certificates that expire every 90 days.
The Certbot package installs a systemd timer and service that can used to
automate the renewal or a simple cron job can be used.  Certbot needs to answer
a cryptographic challenge issued by the Let\’s Encrypt API in order to prove
control of the domain. It uses ports 80 (HTTP) or 443 (HTTPS) to accomplish this,
ensure one of these ports is open in your firewall.

## This script installs.

- **Postfix** to send and receive mail.
- **Dovecot** to get mail to your email client (mutt, Thunderbird, etc).
- **Spamassassin** to prevent spam and allow you to make custom filters.
- **OpenDKIM** to validate you so you can send to Gmail and other big sites.
- **Policyd-spf-python** to help prevent spoofing and phishing attacks.
- **Fail2ban** to help secure the server and block brute force attacks.
- **DNSBLs** blacklists enforced by postfix-postscreen and Spamassassin.
- **Logrotate** configs where needed for the installed packages.

## Server security

  This script sets some **baselevel** security in the way of _Fail2ban_, _TLS_,
  _SPF_, _Spamassassin_, and _DNSBLs_ but you most have secure passwords and
  proper configs for this to make any difference.  The default configs for
  _Fail2ban_ and _Spamassassin_ in this script setup a reasonable baseline but
  if your going to run your own email server or web server you have to maintain
  your own security.  The idea that some no name website or single email server
  won't be worth attacking like I have see and heard others say is just
  **wrong** most of these attacks are preformed by bots with little to no human
  interaction.  Logins must **not** contain any combination of dictionary words
  and or names.  And **must** be at least 9 characters long and contain special
  characters.  Equal to or greater than 11 characters recommended.

  The _Spamassassin_ default config for versions >= 3.0 has **URIDNSBL** enabled by
  default so it is highly recommended to use one of the newer release versions.

  The _Fail2ban_ configs setup five jails _sshd_, _dovecot_, _postfix_,
  _postfix-postscreen_ (Not covered by postfix aggressive mode) and _recidive_
  these along with _SPF_ checking instituted via postfix provides a wide
  array of not only spam blocking but also general server security and also email
  server security.

##  Requirements

 1. A **Debian or Ubuntu server**. I've tested this on a
    [Vultr](https://www.vultr.com/?ref=8637959) Debian 10 servers and servers running
    Ubuntu 18.04LTS.
 2. **A Let's Encrypt SSL certificate for your domain.** This is where the
	  script departs from others.  You will **NOT** need to create an Nginx or
    Apache server and setup a placeholder website.  We will be using a standalone SSL
    certificate from Let's Encrypt [Certbot](https://certbot.eff.org/).
 3. You need to set up some minimal DNS records for **A RECORD**, **MX**, and
    **AAAA** if your planning on using IPV6.
 4. **A Reverse DNS entry for your site.** Go to your VPS settings and add an
    entry for your IPV4 Reverse DNS that goes from your IP address to
    `mail.<yourdomain.com>`. If your using IPV6, you can do the same for
    that. This has been tested on Vultr, and all decent VPS hosts will have
    a section on their instance settings page to add a reverse rDNS entry.
    You can use the 'Test Email Server' or 'smtp' tool on
    [mxtoolbox](https://mxtoolbox.com/SuperTool.aspx) to test if you set up
    a reverse DNS correctly. Most large email services like gmail and Outlook
    will stop emails coming from mail servers without a invalid rDNS lookup.
    This means your email will fail to even make it to the recipients spam folder.
 5. `apt purge` all your previous (failed) attempts to install and configure a
    mailserver. Get rid of _all_ your system settings for Postfix, Dovecot,
    OpenDKIM and everything else. This script builds off of a fresh install.
    Most VPS providers block port 25 by default to prevent spammers from using
    there services to send out bulk emails. You will probably have to open a
    support ticket with your VPS and verify your use case to have them open the
    port for you.     request that this port be opened to send mail successfully. Although I have
    never had to do this on a Vultr VPS, others have had this issue so if you
    cannot send, contact your VPS provider.
 6. **Set System Timezone** most if not all VPS providers by default have the
    timezone set for Universal Time UTC but for logging reasons and to have easily
    readable timestamps I recommend changing you your timezone to suite your
    locale.  This can be done easily with the `timedatectl` command and will
    make your life much easier when it comes to reading logs and should the need
    arise debugging any issues.

## Post-install requirement!

- After the script runs, you'll have to add additional DNS TXT records which
  are displayed at the end when the script is complete. They will help ensure
  your mail is validated and secure.

- Certbot renewal is automatically enabled on systems using the systemd init
  system.  Otherwise a simple crontab will work but you also need to make sure
  you restart your server after renewal the new certificate is not applied until
  either reboot or system services restart.

## Making new users/mail accounts.

`useradd -m -G mail example`

`passwd example`

This will create a new user *"example"* with the email address *"exmaple@domain.com"*.

## Setting aliases.

- SMTP/RFC mandate that any publicly accessible mail server that accepts any mail
  at all must also except mail at the *"postmaster"* account and some might also
  expect *"hostmaster", "abuse", "webmaster"* and others.  You can either
  redirect those address to root or a specific user.  I have supplied a list of
  common aliases that are usually expected on most mail servers in the basic
  config.  I suggest redirecting them all to *"root"* and then redirecting
  *"root"* to your main account **(this is how I have set up the aliases file)**.

- Additional aliases maybe added to the `/etc/aliases` file to redirect mail to
  any account.  If you decide to add additional aliases make sure to run the
  `newaliases` command with sudo privileges afterwords.

## Logging in from an MUA (ie. mutt, neomutt, ect.) remotely.

Let's say you want to access your mail with Thunderbird or mutt or another
email program. For my domain, the server information will be as follows:

- SMTP server: `mail.domain.com`
- SMTP port: 587
- SMTP STARTTLS
- IMAP server: `mail.domain.com`
- IMAP port: 993
- IMAP TLS/SSL
- Username `user` (ie. *not* `user@domain.com`)

## Troubleshooting -- Can't send mail?

- Check logs ie. `mail.log` and `mail.err` to see the specific problem.
- Go to [this site](https://appmaildev.com/en/dkim) to test your TXT records.
  If your DKIM, SPF or DMARC tests fail you probably copied in the TXT records
  incorrectly.
- If everything looks good and you *can* send mail, but it still goes to Gmail
  or another big provider's spam directory, your domain (especially if it's a
  new one) might be on a public spam list.  Check
  [this site](https://mxtoolbox.com/blacklists.aspx) to see if it is. Don't
  worry if you are: sometimes especially new domains are automatically assumed
  to be spam temporally. If you are blacklisted by one of these, look into it
  and it will explain why and how to remove yourself.
- Two useful tools will be `postconf -d` and `postconf -n` they will list the
  default and currently set *Postfix* settings.  *Remember any changes to either
  Postfix Dovecot or Fail2ban will not take effect until that service is
  restarted*.

**NOTE**: When logging into a remote server via ssh it will read some of your
environment variables and set them on the server.  If your using one of the more
common terminal emulators *(ie. rxvt or xterm)* this won't be an issue but if
you are using something less common I recommend setting your TERM variable
either manually or via ssh environment ~/.ssh/environment to rxvt or xterm
before running this script.

`export TERM=rxvt`

If you get errors when trying to install postfix and the postfix tui will not
start check this first.

## Mailbox location and format.

 Mail will be stored in Maildir form in the home directory in \$home/Mail.  This
 makes it easier for use with offline sync ie. offlineimap or isync(mbsync).

 The mailbox names are: Inbox, Sent, Drafts, Archive, Junk(Spam), Trash these are
 fairly standard names but can be changed to your liking, but if your planning
 on having more then one account or sync with other imap servers I recommend
 staying with this naming convention.

 Use the typical unix login system for mail users. Users will log into their
 email with their passnames on the server. No usage of a redundant mySQL
 database to do this.
