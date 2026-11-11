#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
mkdir -p "$work/tools" "$work/gradle-home" "$work/java-home"
archive="$work/tools/$JDK_ARCHIVE"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "$JDK_URL" -o "$archive.partial"
  echo "$JDK_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$JDK_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  mkdir -p "$work/jdk"
  tar -xf "$archive" -C "$work/jdk" --strip-components=1
fi
java -version
cat > "$GRADLE_USER_HOME/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx8g -Dfile.encoding=UTF-8 -XX:ActiveProcessorCount=2 -XX:+UseParallelGC -XX:MaxMetaspaceSize=1g
org.gradle.workers.max=1
kotlin.daemon.jvmargs=-Xmx2g
EOF
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
if [[ -e "$resolved" ]]; then
  cmp "$app_dir/Package.resolved" "$resolved"
else
  mkdir -p "$(dirname "$resolved")"
  cp "$app_dir/Package.resolved" "$resolved"
fi
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
