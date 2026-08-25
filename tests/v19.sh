#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
db_password=${TKL_TEST_DB_PASS:?TKL_TEST_DB_PASS is required}
base=https://localhost
webroot=/var/www/snipe-it
cookie=/tmp/tkl-snipe-it-cookie.$$
page=/tmp/tkl-snipe-it-page.$$
headers=/tmp/tkl-snipe-it-headers.$$
response=/tmp/tkl-snipe-it-response.$$
adminer_cookie=/tmp/tkl-snipe-it-adminer-cookie.$$
queue_probe=/tmp/tkl-snipe-it-queue.$$
schedule_output=/tmp/tkl-snipe-it-schedule.$$
policy=/tmp/tkl-snipe-it-policy.$$

report_error() {
    printf 'test_failure line=%s status=%s\n' "$1" "$2" >&2
    exit "$2"
}
trap 'report_error "$LINENO" "$?"' ERR

cleanup() {
    rm -f -- "$cookie" "$page" "$headers" "$response" \
        "$adminer_cookie" "$queue_probe" "$schedule_output" "$policy"
}
trap cleanup EXIT

csrf_token() {
    python3 - "$1" <<'PYTHON'
from html.parser import HTMLParser
import sys


class CsrfParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.token = None

    def handle_starttag(self, tag, attrs):
        if tag != "input":
            return
        item = dict(attrs)
        if item.get("name") == "_token":
            self.token = item.get("value")


parser = CsrfParser()
with open(sys.argv[1], encoding="utf-8") as stream:
    parser.feed(stream.read())
assert parser.token, "CSRF token missing"
print(parser.token)
PYTHON
}

payload_id() {
    python3 - "$1" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert data["status"] == "success", data
print(data["payload"]["id"])
PYTHON
}

require_active_unit() {
    local unit=$1
    local state=

    for _ in {1..10}; do
        state=$(systemctl is-active "$unit" 2>/dev/null || true)
        if [[ $state == active ]]; then
            return 0
        fi
        sleep 1
    done

    printf 'required_unit_inactive unit=%s state=%s\n' "$unit" "$state" >&2
    systemctl --no-pager --full status "$unit" >&2 || true
    return 1
}

for unit in apache2.service mariadb.service redis-server.service \
        supervisor.service postfix.service cron.service multi-user.target; do
    require_active_unit "$unit"
done
for unit in apache2.service mariadb.service redis-server.service \
        supervisor.service postfix.service cron.service; do
    systemctl --quiet is-enabled "$unit"
done
apache2ctl -t
apache2ctl -M 2>/dev/null | grep -q ' rewrite_module '
grep -Fxq 'VERSION_CODENAME=trixie' /etc/os-release
grep -Eq '^turnkey-snipe-it-19\.0' /etc/turnkey_version
grep -Fq '[40snipe-it] successfully completed' /var/log/inithooks.log

source_manifest=/usr/local/share/turnkey/snipe-it-source
grep -Fxq 'version=8.6.3' "$source_manifest"
grep -Fxq 'tag=v8.6.3' "$source_manifest"
grep -Fxq 'commit=cfd1ff8413e478a8daab700c15e96c96f93220e2' \
    "$source_manifest"
grep -Fxq 'tree=012c6af2f4b2428d4c057b9861a7ab71f2a87e14' \
    "$source_manifest"
grep -Fxq 'url=https://github.com/grokability/snipe-it.git' \
    "$source_manifest"

git_safe=(git -c safe.directory="$webroot" -C "$webroot")
test "$("${git_safe[@]}" rev-parse HEAD)" = \
    cfd1ff8413e478a8daab700c15e96c96f93220e2
test "$("${git_safe[@]}" rev-parse 'HEAD^{tree}')" = \
    012c6af2f4b2428d4c057b9861a7ab71f2a87e14
"${git_safe[@]}" fsck --no-dangling >/dev/null
"${git_safe[@]}" diff --quiet

installed_version=$(php -r \
    '$v=require $argv[1]; echo ltrim($v["app_version"], "v");' \
    "$webroot/config/version.php")
test "$installed_version" = 8.6.3
php_version=$(php -r 'echo PHP_VERSION;')
[[ $php_version == 8.4.* ]]
for module in bcmath curl exif fileinfo gd intl json ldap mbstring mysqli \
        openssl pdo_mysql redis sodium tokenizer xml zip; do
    php -m | grep -Fxiq "$module"
done

grep -Fxq 'APP_URL=https://localhost' "$webroot/.env"
grep -Fxq 'MAIL_MAILER=sendmail' "$webroot/.env"
grep -Fxq 'MAIL_FROM_ADDR=admin@example.invalid' "$webroot/.env"
grep -Fxq 'QUEUE_CONNECTION=redis' "$webroot/.env"
grep -Fxq 'REDIS_HOST=127.0.0.1' "$webroot/.env"

curl --insecure --fail --silent --show-error --cookie-jar "$cookie" \
    "$base/login" >"$page"
token=$(csrf_token "$page")
curl --insecure --silent --show-error --cookie "$cookie" \
    --cookie-jar "$cookie" --data-urlencode "_token=$token" \
    --data-urlencode 'username=admin' \
    --data-urlencode "password=$app_password" \
    --dump-header "$headers" --output "$page" "$base/login"
grep -Eq '^HTTP/.* 30[12378]' "$headers"
curl --insecure --fail --silent --show-error --location \
    --cookie "$cookie" --cookie-jar "$cookie" "$base/" >"$page"
grep -Fq 'Dashboard' "$page"
! grep -Fq 'name="username"' "$page"

api_token=$(runuser -u www-data -- php "$webroot/artisan" \
    snipeit:make-api-key --user_id=1 --name="TurnKey-v19-$$" --key-only |
    tail -n1)
test -n "$api_token"
api=(curl --insecure --fail --silent --show-error \
    --header "Authorization: Bearer $api_token" \
    --header 'Accept: application/json')

category_name="TurnKey v19 assets $$"
"${api[@]}" --request POST \
    --data-urlencode "name=$category_name" \
    --data-urlencode 'category_type=asset' \
    --data-urlencode 'require_acceptance=0' \
    --data-urlencode 'use_default_eula=0' \
    "$base/api/v1/categories" >"$response"
category_id=$(payload_id "$response")

manufacturer_name="TurnKey v19 manufacturer $$"
"${api[@]}" --request POST \
    --data-urlencode "name=$manufacturer_name" \
    "$base/api/v1/manufacturers" >"$response"
manufacturer_id=$(payload_id "$response")

status_name="TurnKey v19 ready $$"
"${api[@]}" --request POST \
    --data-urlencode "name=$status_name" \
    --data-urlencode 'type=deployable' \
    "$base/api/v1/statuslabels" >"$response"
status_id=$(payload_id "$response")

model_name="TurnKey v19 model $$"
"${api[@]}" --request POST \
    --data-urlencode "name=$model_name" \
    --data-urlencode 'model_number=TKL-V19' \
    --data-urlencode "category_id=$category_id" \
    --data-urlencode "manufacturer_id=$manufacturer_id" \
    "$base/api/v1/models" >"$response"
model_id=$(payload_id "$response")

asset_tag="TKL-V19-$$-$RANDOM"
asset_name="TurnKey v19 acceptance asset $$"
asset_serial="TKL-SERIAL-$$-$RANDOM"
"${api[@]}" --request POST \
    --data-urlencode "asset_tag=$asset_tag" \
    --data-urlencode "name=$asset_name" \
    --data-urlencode "serial=$asset_serial" \
    --data-urlencode "model_id=$model_id" \
    --data-urlencode "status_id=$status_id" \
    "$base/api/v1/hardware" >"$response"
asset_id=$(payload_id "$response")

"${api[@]}" "$base/api/v1/hardware/$asset_id" >"$response"
python3 - "$response" "$asset_id" "$asset_tag" "$asset_name" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    asset = json.load(stream)
assert asset["id"] == int(sys.argv[2]), asset
assert asset["asset_tag"] == sys.argv[3], asset
assert asset["name"] == sys.argv[4], asset
PYTHON

db_asset=$(mariadb --batch --skip-column-names --user=root \
    --password="$db_password" snipeit --execute \
    "SELECT CONCAT(asset_tag, '|', name, '|', serial) FROM assets WHERE id=$asset_id")
test "$db_asset" = "$asset_tag|$asset_name|$asset_serial"
systemctl restart mariadb.service apache2.service
"${api[@]}" "$base/api/v1/hardware/$asset_id" >"$response"
grep -Fq "$asset_tag" "$response"

redis-cli ping | grep -Fxq PONG
supervisorctl status snipe-it-worker >"$page"
grep -Eq '^snipe-it-worker[[:space:]]+RUNNING' "$page"
queue_name="turnkey-v19-probe-$$"
queue_payload="turnkey-v19-queue-$$"
runuser -u www-data -- php -r '
    require $argv[1] . "/vendor/autoload.php";
    $app = require $argv[1] . "/bootstrap/app.php";
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    $queue = Illuminate\Support\Facades\Queue::connection("redis");
    $payload = json_encode([
        "id" => $argv[2],
        "attempts" => 0,
        "data" => ["marker" => $argv[2]],
    ], JSON_THROW_ON_ERROR);
    $queue->pushRaw($payload, $argv[3]);
    if ($queue->size($argv[3]) !== 1) {
        exit(3);
    }
' "$webroot" "$queue_payload" "$queue_name"
runuser -u www-data -- php -r '
    require $argv[1] . "/vendor/autoload.php";
    $app = require $argv[1] . "/bootstrap/app.php";
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    $job = Illuminate\Support\Facades\Queue::connection("redis")->pop($argv[2]);
    if (!$job) {
        exit(2);
    }
    $payload = json_decode($job->getRawBody(), true, flags: JSON_THROW_ON_ERROR);
    file_put_contents($argv[3], $payload["data"]["marker"]);
    $job->delete();
' "$webroot" "$queue_name" "$queue_probe"
grep -Fxq "$queue_payload" "$queue_probe"

grep -Fxq '* * * * * www-data /usr/bin/php /var/www/snipe-it/artisan schedule:run > /dev/null 2>&1' \
    /etc/cron.d/snipe-it
runuser -u www-data -- php "$webroot/artisan" schedule:list \
    >"$schedule_output"
grep -Fq 'snipeit:backup' "$schedule_output"
grep -Fq 'auth:clear-resets' "$schedule_output"
runuser -u www-data -- php "$webroot/artisan" schedule:run \
    --no-interaction >/dev/null

mail_marker="TurnKey v19 Snipe-IT mail $$"
runuser -u www-data -- php -r '
    require $argv[1] . "/vendor/autoload.php";
    $app = require $argv[1] . "/bootstrap/app.php";
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    $marker = $argv[2];
    Illuminate\Support\Facades\Mail::raw($marker, function ($message) use ($marker) {
        $message->to("root@localhost")->subject($marker);
    });
' "$webroot" "$mail_marker"
for _ in $(seq 1 20); do
    grep -Fq "$mail_marker" /var/mail/root 2>/dev/null && break
    sleep 1
done
grep -Fq "$mail_marker" /var/mail/root
test "$(postconf -h inet_interfaces)" = localhost
ss -ltn | grep -Eq '127\.0\.0\.1:25[[:space:]]'

dpkg-query -W adminer webmin-apache webmin-mysql webmin-phpini \
    webmin-postfix postfix mariadb-server redis-server supervisor >/dev/null
curl --insecure --fail --silent --show-error \
    https://127.0.0.1:12322/ >"$page"
grep -qi Adminer "$page"
curl --insecure --silent --show-error --location \
    --cookie-jar "$adminer_cookie" --cookie "$adminer_cookie" \
    --data-urlencode 'auth[driver]=server' \
    --data-urlencode 'auth[server]=localhost' \
    --data-urlencode 'auth[username]=adminer' \
    --data-urlencode "auth[password]=$db_password" \
    --data-urlencode 'auth[db]=snipeit' \
    https://127.0.0.1:12322/ >"$page"
grep -qi snipeit "$page"
grep -qi Logout "$page"
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12321/ >/dev/null

update_result=$(turnkey-snipe-it-update --check)
grep -Fq "installed=$installed_version" <<<"$update_result"
grep -Fq 'channel=official-stable' <<<"$update_result"
latest_tag=$(grep -oE 'latest=v[0-9]+\.[0-9]+\.[0-9]+' <<<"$update_result" |
    cut -d= -f2)
latest_commit=$(grep -oE 'candidate=[0-9a-f]{40}' <<<"$update_result" |
    cut -d= -f2)
test -n "$latest_tag"
test -n "$latest_commit"

apache_version=$(dpkg-query -W -f='${Version}' apache2)
mariadb_version=$(dpkg-query -W -f='${Version}' mariadb-server)
redis_version=$(dpkg-query -W -f='${Version}' redis-server)
before="$apache_version|$mariadb_version|$redis_version"
apt-get update >/dev/null
for package in php apache2 mariadb-server redis-server composer; do
    apt-cache policy "$package" >"$policy"
    candidate=$(awk '/Candidate:/ {print $2}' "$policy")
    test -n "$candidate"
    test "$candidate" != '(none)'
    grep -Eq 'trixie|deb13' "$policy"
done
after="$(dpkg-query -W -f='${Version}' apache2)|$(dpkg-query -W -f='${Version}' mariadb-server)|$(dpkg-query -W -f='${Version}' redis-server)"
test "$after" = "$before"
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
if grep -Rqi bookworm /etc/apt/sources.list.d; then
    exit 1
fi

cat >"$result" <<EOF
package_source=Official Snipe-IT v8.6.3 Git release at commit cfd1ff8413e478a8daab700c15e96c96f93220e2; PHP, Apache, MariaDB, Redis, Composer, Postfix and supporting extensions from Debian Trixie
installed_version=Snipe-IT $installed_version; PHP $php_version; apache2 $apache_version; mariadb-server $mariadb_version; redis-server $redis_version
runtime_checks=normal init; Apache TLS; firstboot administrator HTTPS login; Snipe-IT API asset create and read with direct MariaDB readback after service restart; Redis queue round trip and supervised worker; Laravel scheduler; application mail through local Postfix; authenticated Adminer and Webmin endpoints
updater_command=turnkey-snipe-it-update --check; apt-get update and apt-cache policy
updater_result=installed Snipe-IT v8.6.3 source remained unchanged; current official stable release $latest_tag and candidate commit $latest_commit were identified; signed Trixie metadata refreshed with installed packages unchanged
updater_channel=official Snipe-IT stable releases and master through https://github.com/grokability/snipe-it; signed Debian and TurnKey Trixie repositories
integrity_evidence=installed official Git commit cfd1ff8413e478a8daab700c15e96c96f93220e2 and tree 012c6af2f4b2428d4c057b9861a7ab71f2a87e14 passed git fsck and matched the release marker; APT accepted signed Trixie metadata; no Bookworm source remained
EOF
