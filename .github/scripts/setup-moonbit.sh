#!/usr/bin/env bash

set -euo pipefail

readonly MOONBIT_VERSION='0.10.5+5e7afb0c0'
readonly MOONBIT_VERSION_URL='0.10.5%2B5e7afb0c0'
readonly MOONBIT_BASE_URL='https://cli.moonbitlang.com'
readonly TOOLCHAIN_SHA256='07da4e4b21d3ea203b00183906e9e6a3104d77b9756a95c4d9e648471cf2e2d8'
readonly CORE_SHA256='d92991190e30d10a1ab6fcd7d0282b8ddd0004d0309bc40fbc056310cf20bfc5'

: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"
: "${GITHUB_ENV:?GITHUB_ENV must be set}"
: "${GITHUB_PATH:?GITHUB_PATH must be set}"

moonbit_setup_root=$(mktemp -d "${RUNNER_TEMP}/moonbit-toolchain.XXXXXX")
readonly moonbit_setup_root
readonly moon_home="${moonbit_setup_root}/home"
readonly download_dir="${moonbit_setup_root}/downloads"
readonly toolchain_archive="${download_dir}/moonbit-linux-x86_64.tar.gz"
readonly core_archive="${download_dir}/core.tar.gz"

cleanup_downloads() {
  if [[ "${download_dir}" == "${RUNNER_TEMP}"/moonbit-toolchain.*/downloads ]]; then
    rm -rf -- "${download_dir}"
  fi
}
trap cleanup_downloads EXIT

mkdir -p "${download_dir}" "${moon_home}/lib"

download() {
  local source_url=$1
  local destination=$2
  curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --location \
    --show-error \
    --silent \
    --output "${destination}" \
    "${source_url}"
}

verify_archive() {
  local expected_sha256=$1
  local archive=$2
  printf '%s  %s\n' "${expected_sha256}" "${archive}" | sha256sum --check --strict
}

download \
  "${MOONBIT_BASE_URL}/binaries/${MOONBIT_VERSION_URL}/moonbit-linux-x86_64.tar.gz" \
  "${toolchain_archive}"
download \
  "${MOONBIT_BASE_URL}/cores/core-${MOONBIT_VERSION_URL}.tar.gz" \
  "${core_archive}"

verify_archive "${TOOLCHAIN_SHA256}" "${toolchain_archive}"
verify_archive "${CORE_SHA256}" "${core_archive}"

tar -xzf "${toolchain_archive}" -C "${moon_home}"
tar -xzf "${core_archive}" -C "${moon_home}/lib"
ln -s moon "${moon_home}/bin/moonx"
chmod +x "${moon_home}"/bin/*
chmod +x "${moon_home}/bin/internal/tcc"

PATH="${moon_home}/bin:${PATH}" \
  "${moon_home}/bin/moon" -C "${moon_home}/lib/core" bundle --warn-list -a --all
PATH="${moon_home}/bin:${PATH}" \
  "${moon_home}/bin/moon" -C "${moon_home}/lib/core" bundle --warn-list -a --target wasm-gc --quiet

printf 'MOON_HOME=%s\n' "${moon_home}" >> "${GITHUB_ENV}"
printf '%s\n' "${moon_home}/bin" >> "${GITHUB_PATH}"
printf 'Installed MoonBit %s in %s\n' "${MOONBIT_VERSION}" "${moon_home}"
