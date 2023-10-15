# Building a Talos image for Turing Pi 2 node 3

When compiling on macOS, use Homebrew to install GNU make. For any `make` command in the following instructions, substitute the aliased command `gmake` instead. When compiling u-boot, some additional cross compiling tools are needed.

```
brew tap messense/macos-cross-toolchains
brew install aarch64-unknown-linux-gnu make sed
```

If building using Ubuntu, install libraries and tools that will be needed.

`apt install gcc-aarch64-linux-gnu bison flex libssl-dev make`

### Setup Docker
If building using Ubuntu, make sure you're using an up to date version of Docker. Find installation instruction [here](https://docs.docker.com/engine/install/ubuntu/#installation-methods).

On macOS, use Homebrew to install Docker.

`brew install --cask docker`

### Create a local registry and BuildKit container

`docker run -d -p 5005:5000 --restart always --name local registry:2`

`docker buildx create --driver docker-container  --driver-opt network=host --name local1 --buildkitd-flags '--allow-insecure-entitlement security.insecure' --use`

### Custom kernel patching and compile
Clone: [https://github.com/siderolabs/pkgs](https://github.com/siderolabs/pkgs), checkout latest release (v1.5.0).

`mkdir kernel/prepare/patches`

Add [2-5.patch](kernel/2-5.patch) to the above dir

Edit kernel/prepare/pkg.yaml, add patch line just above `make mrproper`
`patch -p1 < /pkg/patches/2-5.patch`

Compile the kernel, adjusting the `TAG` if needed, based on the value of the `PKGS` value in the Makefile of the talos repo.

`make -j$(nproc) kernel PLATFORM=linux/arm64 TAG=v1.5.0-9-g7f9d6eb REGISTRY=127.0.0.1:5005 USERNAME=siderolabs PUSH=true`

### Compile u-boot from source

Clone: [https://github.com/u-boot/u-boot](https://github.com/u-boot/u-boot), checkout `next` branch. At the moment, the `next` branch has the necessary patches to allow u-boot to function on node 3.

Create [a Dockerfile](u-boot/Dockerfile) that will be used to package the compiled u-boot.

```
FROM scratch

COPY u-boot.bin /rpi_generic/u-boot.bin
```

If a container image has already been produced, delete it.

`docker rmi 127.0.0.1:5005/ubootbash:latest || true`

Run the following to generate and edit a config, and compile u-boot. Note: If on macOS, use the GNU sed alias `gsed` instead.

```
make -j $(nproc) clean rpi_arm64_defconfig
sed -i "s/CONFIG_TOOLS_LIBCRYPTO=y/# CONFIG_TOOLS_LIBCRYPTO is not set/" .config
CROSS_COMPILE=aarch64-linux-gnu- make -j $(nproc) HOSTLDLIBS_mkimage="-lssl -lcrypto"
```

If compiling on macOS running on Apple Silicon with native ARM Homebrew, additional parameters may be required so that the build process can find the required OpenSSL libraries. If the previous `make` command resulted in an error, try the following.

```
HOSTLDFLAGS="-L$(brew --prefix openssl)/lib" HOSTCFLAGS="-I$(brew --prefix openssl)/include" CROSS_COMPILE=aarch64-linux-gnu- gmake -j $(nproc) HOSTLDLIBS_mkimage="-lssl -lcrypto"
```

Package the compiled u-boot binary in to a container image that will be used by the Talos build process.

`docker build -t 127.0.0.1:5005/ubootbash:latest . && docker push 127.0.0.1:5005/ubootbash:latest`

### Make a custom Talos installer, imager, and a rPi image file

Clone [https://github.com/siderolabs/talos](https://github.com/siderolabs/talos), checkout latest release (v1.5.2).

The Dockerfile in the repo needs to be modified to pull from the local container registry for the custom kernel and u-boot containers.

On or about line 82, find and comment out the following...

`FROM --platform=arm64 ghcr.io/siderolabs/kernel:${PKGS} AS pkg-kernel-arm64`

Replace it with...

`FROM --platform=arm64 127.0.0.1:5005/siderolabs/kernel:${PKGS} AS pkg-kernel-arm64`

On or about line 84, find and comment out the following...

`FROM --platform=arm64 ghcr.io/siderolabs/u-boot:${PKGS} AS pkg-u-boot-arm64`

Replace it with...

`FROM --platform=arm64 127.0.0.1:5005/ubootbash:latest AS pkg-u-boot-arm64`

Additionally, if you don't want your images to have a `dirty` tag appended to their version string, edit the `Makefile` to remove the `--dirty` flag from the `SHA` and `TAG` values.

First, produce the custom installer. If the operation that is being performed is an in-place upgrade on an existing cluster, this is the only step required, although the image will need to be pushed to a registry accessible from your existing cluster.

`make -j$(nproc) installer IMAGE_REGISTRY=127.0.0.1:5005 PLATFORM=linux/amd64,linux/arm64 PUSH=true`

If there is a need to produce ISO files and raw images suitable for systems such a Raspberry Pi, then produce the custom imager next.

`make -j$(nproc) imager IMAGE_REGISTRY=127.0.0.1:5005 PLATFORM=linux/amd64,linux/arm64 PUSH=true`

Lastly, use the custom imager to produce any required image files.

For an ISO file...

`make -j$(nproc) iso IMAGE_REGISTRY=127.0.0.1:5005 PLATFORM=linux/arm64`

For a Raspberry Pi image...

`make -j$(nproc) sbc-rpi_generic IMAGE_REGISTRY=127.0.0.1:5005 PLATFORM=linux/arm64`

For a Raspberry Pi image with some pre-installed [system extensions](https://github.com/siderolabs/extensions)...

`make -j$(nproc) sbc-rpi_generic IMAGE_REGISTRY=127.0.0.1:5005 PLATFORM=linux/arm64 IMAGER_ARGS="--system-extension-image ghcr.io/siderolabs/iscsi-tools:v0.1.4 --system-extension-image ghcr.io/siderolabs/nvidia-container-toolkit:535.54.03-v1.14.0"`

