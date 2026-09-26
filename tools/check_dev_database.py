"""Read-only development DB probe using MariaDB client; never run addon code.
Run on the machine holding the private option file, outside a live GMod process.
Requires Python 3.9+ and the MariaDB CLI. No production migration is performed.
"""
import argparse
import configparser
import json
import os
import pathlib
import re
import shutil
import subprocess

NAME = re.compile(r'^(?:[A-Za-z0-9]+_)*us1_dev$')
ALLOWED = {'host', 'port', 'user', 'password', 'ssl-ca'}
SQL = ("SELECT DATABASE(), 1; "
       "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE(); "
       "SHOW SESSION STATUS LIKE 'Ssl_cipher';")


def validate_config(path: pathlib.Path, database: str) -> pathlib.Path:
    if not NAME.fullmatch(database):
        raise ValueError('Only us1_dev or a panel-prefixed *_us1_dev database is accepted.')
    path = path.expanduser().resolve(strict=True)
    if not path.is_file() or path.stat().st_size > 16384:
        raise ValueError('Expected a small private client option file.')
    if any((parent / '.git').exists() for parent in path.parents):
        raise ValueError('Credentials must be stored outside every Git working tree.')
    if os.name == 'posix' and path.stat().st_mode & 0o077:
        raise ValueError('Private option file must have owner-only permissions (chmod 600).')
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read_string(path.read_text(encoding='utf-8'))
    except (configparser.Error, UnicodeError):
        raise ValueError('Invalid client option file; values are intentionally not displayed.') from None
    if parser.defaults() or parser.sections() != ['client']:
        raise ValueError('Only one [client] section is accepted; no includes or defaults.')
    options = dict(parser['client'])
    if set(options) - ALLOWED or not {'host', 'port', 'user', 'password'} <= set(options):
        raise ValueError('Expected host, port, user, password, and optional ssl-ca only.')
    if any(not v.strip() or '\n' in v or 'REPLACE_' in v for v in options.values()):
        raise ValueError('Fill all placeholders locally; multiline values are not supported.')
    if not options['port'].isdigit() or not 1 <= int(options['port']) <= 65535:
        raise ValueError('Port must be the numeric port reported by the panel.')
    return path


def build_command(client: str, path: pathlib.Path, database: str) -> list:
    return [client, '--defaults-file=' + str(path), '--protocol=TCP',
            '--ssl', '--ssl-verify-server-cert', '--local-infile=0',
            '--batch', '--skip-column-names', '--connect-timeout=5',
            '--skip-reconnect', '--database=' + database, '--execute=' + SQL]


def parse_result(text: str, expected: str) -> dict:
    rows = [line.split('\t') for line in text.splitlines()]
    if len(rows) != 3 or rows[0] != [expected, '1']:
        raise ValueError('Unexpected probe response or incorrect database selected.')
    if len(rows[1]) != 1 or not rows[1][0].isdigit():
        raise ValueError('Invalid table-count response.')
    if len(rows[2]) != 2 or rows[2][0].lower() != 'ssl_cipher' or not rows[2][1]:
        raise ValueError('Encrypted connection was not confirmed; do not disable TLS.')
    return {'database':expected, 'select_1':'ok', 'table_count':int(rows[1][0]),
            'tls_active':True, 'writes_performed':False, 'player_rows_read':False}


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--config', type=pathlib.Path, required=True)
    args.add_argument('--database', required=True)
    args.add_argument('--client', default='mariadb')
    values = args.parse_args()
    try:
        config = validate_config(values.config, values.database)
        client = shutil.which(values.client)
        if not client: raise ValueError('MariaDB client is not installed on this machine.')
        env = {k:v for k,v in os.environ.items() if k not in ('MYSQL_PWD','MYSQL_TEST_LOGIN_FILE')}
        result = subprocess.run(build_command(client, config, values.database),
                                capture_output=True, text=True, timeout=15, env=env)
        if result.returncode:
            match = re.search(r'\bERROR\s+(\d+)', result.stderr)
            raise ValueError('Connection failed; database error code: '+(match.group(1) if match else 'unknown'))
        print(json.dumps(parse_result(result.stdout, values.database), indent=2))
        return 0
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'ok':False, 'error':str(error) if isinstance(error,ValueError) else type(error).__name__}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
