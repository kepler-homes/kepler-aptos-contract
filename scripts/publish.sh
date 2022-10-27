base=$(cd "$(dirname "$0")" || exit; pwd)
cd "$base" || exit
cd ..

aptos move publish --assume-yes --package-dir ./contracts/$1 --named-addresses kepler=default