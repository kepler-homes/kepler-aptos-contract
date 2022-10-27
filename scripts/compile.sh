base=$(cd "$(dirname "$0")" || exit; pwd)
cd "$base" || exit
cd ..

aptos move compile --package-dir ./contracts/$1 --save-metadata --named-addresses kepler=default

