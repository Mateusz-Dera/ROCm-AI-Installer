#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2025 Mateusz Dera

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

# KoboldCPP
install_koboldcpp() {
    echo XD
    # podman exec -it rocm
    # uv_base "https://github.com/YellowRoseCx/koboldcpp-rocm" "ee3f39fc7ce391d02eda407f828098f70488a6b7" "uv run koboldcpp.py" "3.13" "rocm6.4" "0"
    # make LLAMA_HIPBLAS=1 -j$(($(nproc) - 1))
}