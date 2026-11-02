#!/bin/sh
# Print the c3c flags that link the static libcurl installed by vcpkg (Windows CI and release builds).
dir="$VCPKG_INSTALLATION_ROOT/installed/x64-windows-static/lib"
flags="-L $dir --wincrt=static -l ws2_32 -l iphlpapi -l crypt32 -l bcrypt -l advapi32 -l secur32 -l normaliz -l wldap32"
for f in "$dir"/*.lib; do
  [ -e "$f" ] || continue
  n=$(basename "$f" .lib)
  case $n in curl | libcurl) ;; *) flags="$flags -l $n" ;; esac   # curl.lib is linked by the vendored manifest
done
echo "$flags"
