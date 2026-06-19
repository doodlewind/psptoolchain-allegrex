#!/bin/bash

# Install build dependencies
sudo dnf install $@ \
  clang llvm gcc gcc-c++ make git gettext texinfo bison flex gmp-devel mpfr-devel libmpc-devel \
  ncurses-devel diffutils gawk file
