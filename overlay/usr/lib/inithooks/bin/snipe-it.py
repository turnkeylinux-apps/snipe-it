#!/usr/bin/python3
"""Set Snipe-IT admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
"""

import sys
import getopt
import bcrypt
from mysqlconf import MySQL
import subprocess

from libinithooks.dialog_wrapper import Dialog
from libinithooks import inithooks_cache


def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)

DEFAULT_DOMAIN="www.example.com"

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
    except getopt.GetoptError as e:
        usage(e)

    email = ""
    domain = ""
    password = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val
        elif opt == '--domain':
            domain = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "Snipe-IT Password",
            "Enter new password for the Snipe-IT 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "Snipe-IT Email",
            "Enter email address for the Snipe-IT 'admin' account.",
            "admin@example.com")

    inithooks_cache.write('APP_EMAIL', email)

    if not domain:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        domain = d.get_input(
            "Snipe-IT Domain",
            "Enter the domain to serve Snipe-IT.",
            DEFAULT_DOMAIN)

    if domain == "DEFAULT":
        domain = DEFAULT_DOMAIN

    if domain.startswith('https://') or domain.startswith('http://'):
        domain = domain.split('://', 1)[1]
    if domain.endswith('/'):
        domain = domain.rstrip('/')

    inithooks_cache.write('APP_DOMAIN', domain)

    CONF = '/var/www/snipe-it/.env'
    # read .env lines
    with open(CONF, 'r') as fob:
        conf_lines = fob.readlines()

    # find APP_URL and set it to domain
    for i in range(len(conf_lines)):
        line = conf_lines[i].strip()
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        if key == 'APP_URL':
            line = f'APP_URL=https://{domain}'
        conf_lines[i] = line + '\n'

    # write .env lines
    with open(CONF, 'w') as fob:
        fob.writelines(conf_lines)

    subprocess.run(['/usr/local/bin/turnkey-artisan', 'config:clear'])

    salt = bcrypt.gensalt()
    hashpass = bcrypt.hashpw(password.encode('utf8'), salt).decode('utf8')
    
    m = MySQL()
    m.execute('UPDATE snipeit.users SET password=%s WHERE id=1;', (hashpass,))
    m.execute('UPDATE snipeit.users SET email=%s WHERE id=1;', (email,))


if __name__ == "__main__":
    main()
