#!/usr/bin/env bash

set -euo pipefail

readonly MOONBIT_VERSION='1.0.0-rc1+3c0520448'
readonly MOONBIT_VERSION_URL='1.0.0-rc1%2B3c0520448'
readonly MOONBIT_BASE_URL='https://cli.moonbitlang.com'
readonly TOOLCHAIN_SHA256='113527a9037fe12e463e6ac1e7698116bf703730243096328e4ac7e2774307c0'
readonly CORE_SHA256='a3f7d82f1195e28ad9aad7b9b8b4cbca490cbf8146b306a376ea3beba4173751'

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
