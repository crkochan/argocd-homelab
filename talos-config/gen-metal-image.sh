#!/bin/bash
set -euo pipefail

# Set version from https://github.com/nberlee/talos/releases (don't include the "v")
version=1.7.4

# Specify additional extension from https://github.com/siderolabs/extensions
system_extentions=(
  iscsi-tools
  nut-client
  util-linux-tools
)

# Everything should be automated below this line

function join_by { local IFS="$1"; shift; echo "$*"; }

imager=ghcr.io/nberlee/imager:v${version}
base_image=ghcr.io/nberlee/installer:v${version}-rk3588
overlay_image=ghcr.io/nberlee/sbc-turingrk1:v${version}

echo "Gathering extension digests..."
extensions=$(join_by \| "${system_extentions[@]}")
extension_digests=($(crane export ghcr.io/siderolabs/extensions:v${version} | tar x -O image-digests | grep -E "${extensions}"))

rk3588_extension_digest=$(crane export ghcr.io/nberlee/extensions:v${version} | tar x -O image-digests | grep rk3588)
extension_digests+=(${rk3588_extension_digest})

cmd="docker run --rm -t -v $(pwd):/out -v /dev:/dev --privileged ${imager} metal --arch arm64 --overlay-name turingrk1 --platform metal --overlay-image ${overlay_image} --base-installer-image ${base_image}"
for extension in "${extension_digests[@]}"; do
  cmd="${cmd} --system-extension-image ${extension}"
done

echo "Running imager..."
(${cmd})

echo "Unpacking raw image..."
xz -dv metal-arm64.raw.xz
