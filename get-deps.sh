#!/bin/sh

NOTFOUND=0

have_command() {
  command -v $1 >/dev/null
}

if test -z "$SUDO"; then
  if have_command 'sudo'; then
    SUDO="sudo"
  elif have_command 'doas'; then
    SUDO="doas"
  fi
fi

alpine_deps() {
  APK="$SUDO apk"
  $APK add \
    'alpine-sdk' \
    'bash' \
    'build-base' \
    'coreutils' \
    'openssl-dev' \
    'pkgconf' \
    'python3' \
    'zlib-dev' \
    'zstd-dev'

  if ! have_command 'cargo'; then
    $APK add 'cargo'
  fi
}

fedora_deps() {
  if have_command 'dnf'; then
    YUM="$SUDO dnf"
  elif have_command 'yum'; then
    YUM="$SUDO yum"
  else
    echo "No idea what package manager to use, sorry! (perhaps 'dnf' or 'yum' is not in \$PATH?)"
    return 1
  fi
  $YUM group install -y "Development Tools"
  $YUM install -y \
    'make' \
    'gcc' \
    'gcc-c++' \
    'openssl-devel' \
    'python3' \
    'python3-pip' \
    'rpm-build' \
    'clang' \
    'telnet' \
    'git'
}

suse_deps() {
  ZYPPER="$SUDO zypper"
  $ZYPPER install -yl \
    'cmake' \
    'make' \
    'gcc' \
    'gcc-c++' \
    'clang' \
    'llvm' \
    'telnet' \
    'git' \
    'libopenssl-devel' \
    'python3' \
    'rpm-build'
}

debian_deps() {
  APT="$SUDO apt-get"
  $APT install -y \
    'bsdutils' \
    'cmake' \
    'dpkg-dev' \
    'fakeroot' \
    'gcc' \
    'g++' \
    'libssl-dev' \
    'lsb-release' \
    'python3'
}

arch_deps() {
  PACMAN="$SUDO pacman"
  $PACMAN -S --noconfirm --needed \
    'base-devel' \
    'cargo' \
    'cmake' \
    'git' \
    'pkgconf' \
    'python3' \
    'rust'
}

bsd_deps() {
  PKG="$SUDO pkg"
  $PKG install -y \
    'cmake' \
    'curl' \
    'expat' \
    'fontconfig' \
    'gcc' \
    'gettext' \
    'git' \
    'gmake' \
    'openssl' \
    'pkgconf' \
    'python3' \
    'rust' \
    'z' \
    'zip'
}

gentoo_deps() {
  portageq envvar USE | xargs -n 1 | grep '^X$' \
  || (echo 'X is not found in USE flags' && exit 1)
  EMERGE="$SUDO emerge"
  for pkg in \
    'cmake' \
    'fontconfig' \
    'openssl' \
    'dev-vcs/git' \
    'pkgconf' \
    'python'
  do
	  equery l "$pkg" > /dev/null || $EMERGE --select $pkg
  done
}

void_deps() {
  XBPS="$SUDO xbps-install"
  $XBPS -S \
    'gcc' \
    'pkgconf' \
    'fontconfig-devel' \
    'openssl-devel'

  if ! have_command 'cargo'; then
    $XBPS -S 'cargo'
  fi
}

solus_deps() {
  EOPKG="$SUDO eopkg"
  $EOPKG install -y -c system.devel
}

fallback_method() {
  if test -e /etc/alpine-release; then
    alpine_deps
  elif test -e /etc/centos-release || test -e /etc/fedora-release || test -e /etc/redhat-release; then
    fedora_deps
  elif test -e /etc/debian_version; then
    debian_deps
  elif test -e /etc/arch-release; then
    arch_deps
  elif test -e /etc/gentoo-release; then
    gentoo_deps
  elif test -e /etc/solus-release; then
    solus_deps
  elif have_command 'lsb_release' && test "$(lsb_release -si)" = "openSUSE"; then
    suse_deps
  fi

  # OSTYPE is set by bash
  case $OSTYPE in
    darwin*|msys)
      echo "skipping darwin*/msys"
    ;;
    freebsd*)
      bsd_deps
    ;;
    ''|linux-gnu)
      # catch and known OSTYPE
      echo "\$OSTYPE is '$OSTYPE'"
    ;;
    *)
      NOTFOUND=1
      return 1
    ;;
  esac
  return 0
}

if test -e /etc/os-release; then
  . /etc/os-release
fi

case $ID in
  centos|fedora|rhel)
    fedora_deps
  ;;
  alpine)
    alpine_deps
  ;;
  *suse*)
    suse_deps
  ;;
  debian|ubuntu)
    debian_deps
  ;;
  freebsd) # available since 13.0
    bsd_deps
  ;;
  arch|artix)
    arch_deps
  ;;
  gentoo)
    gentoo_deps
  ;;
  void)
    void_deps
  ;;
  solus)
    solus_deps
  ;;
  *)
    echo "Couldn't find OS by ID, found ID: $ID"
    echo "Fallback to detecting '/etc/<name>-release'"
    fallback_method
    if ! test $? -eq 0; then
      if ! test $NOTFOUND -eq 0; then
        echo "Couldn't identify OS through '/etc/<name>-release'"
      fi
      exit 1
    fi
  ;;
esac

if ! test $NOTFOUND -eq 0; then
  echo "Please contribute the commands to install the deps for:"
  if have_command 'lsb_release'; then
    lsb_release -ds
  elif test -e /etc/os-release; then
    cat /etc/os-release
  else
    echo "Couldn't recognise system"
  fi
  exit 1
fi

if ! have_command 'rustc'; then
  echo "Rust is not installed!"
  echo "Please see https://docs.kumomta.com/tutorial/install_from_source/ for installation instructions"
  exit 1
fi