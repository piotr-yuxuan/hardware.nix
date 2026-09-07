# shellcheck shell=bash

if [[ $# -ne 1 ]]; then
	printf 'usage: xdg-open URL\n' >&2
	exit 2
fi

url=$1
case $url in
	http://* | https://*) ;;
	*)
		printf 'xdg-open: refusing non-HTTP URI: %s\n' "$url" >&2
		exit 3
		;;
esac

gdbus_bin=${GDBUS_BIN:-gdbus}
"$gdbus_bin" call \
	--session \
	--dest org.freedesktop.portal.Desktop \
	--object-path /org/freedesktop/portal/desktop \
	--method org.freedesktop.portal.OpenURI.OpenURI \
	'' "$url" '{}' >/dev/null
