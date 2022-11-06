base=$(cd "$(dirname "$0")" || exit; pwd)
cd "$base" || exit
cd ..

profile=$1
package=$2

echo publish $2 to $1

aptos move publish --profile $1 --assume-yes --package-dir ./contracts/$2 --named-addresses kepler=$1