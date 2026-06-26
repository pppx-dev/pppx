![GitHub Release](https://img.shields.io/github/v/release/pppx-dev/pppx)
![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/pppx-dev/pppx/total)
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux-blue)](#)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.12759169.svg)](https://doi.org/10.5281/zenodo.12759169)


# PPPx

PPPx is a versatile multi-GNSS data processing software package whose capabilities
extend beyond Precise Point Positioning (PPP).

The main program, `pppx`, focuses on positioning and supports the following features:
- Solution modes:
    - SPP: Single Point Positioning
    - PPP: Precise Point Positioning
    - RTK: Short-baseline processing
    - TDP: Time-Differenced Positioning
- GNSS systems: GPS, GLONASS, Galileo, Beidou-2/3, QZSS
- Solvers: LSQ, EKF, and FGO
- PPP-AR with OSB products (.BIA)
- Flexible frequency selection: L1/L2/L5/E1/E5a/...
- High precision and efficiency: Processes 2880 epochs within 1 second
- Unified input/output format
- Cross-platform: Runs on Linux, Windows, and macOS

Other programs in the PPPx software package include:
- [clkcomb](https://github.com/YuanxinPan/clkcomb): A program for combining PPP-AR products


## Table of Contents
- [Documentation](#documentation)
- [Installation](#installation)
    - [Linux](#linux)
    - [Windows](#windows)
    - [macOS](#macos)
- [Usage](#usage)
- [Example](#example)
- [Contributing](#contributing)


## Documentation

The user manual is available as a PDF, attached to every release:
[**PPPx User Manual**](https://github.com/pppx-dev/pppx/releases/latest/download/pppx-manual.pdf).


## Installation

### Linux

This application is distributed as an [AppImage](https://appimage.org/), making it portable
across most modern Linux distributions. Specifically, `pppx` is built on Ubuntu 20.04 and
requires the host system to have **GNU C Library (`glibc`) version 2.31 or newer**.

It is compatible with the following distributions (and any of their derivatives):

| Distribution Family | Supported Versions
| :--- | :--- |
| **Ubuntu** | 20.04 LTS, 22.04 LTS, 24.04 LTS (and newer) |
| **Linux Mint** | 20, 21, 22 (and newer) |
| **Debian** | 11 "Bullseye", 12 "Bookworm" (and newer) |
| **Fedora** | 32 (and newer) |
| **RHEL / Rocky / Alma** | 9.x (and newer) *Note: RHEL 8 is not supported* |
| **openSUSE** | Leap 15.3+, Tumbleweed |
| **Arch Linux / Manjaro** | Rolling releases (always up to date) |

❓ **Not sure if your system is supported?**

> You can easily check your system's `glibc` version by running `ldd --version` in your terminal.


Clone the repository and run the installer from its root folder:

```shell
git clone --depth 1 https://github.com/pppx-dev/pppx.git
cd pppx
./install.sh
```

The installer downloads the latest `pppx` executable, installs both `pppx` and the
wrapper script `pppx.sh` to `~/.local/bin`, and configures `pppx.sh` to use the
`table` files in the cloned repository. Keeping the repository is recommended, as it
provides the `table` files and examples used by `pppx`.


### Windows

The easiest way to run `pppx` on Windows is via the Windows Subsystem for Linux (WSL).
However, `pppx` can also run natively on Windows using PowerShell, Command Prompt (cmd.exe)
or Git Bash.


Clone the repository, then run the installer from its root folder in PowerShell. It will
download the executable, fetch the required DLLs, and add the installation folder
(`C:\Users\<YOUR_USER_NAME>\AppData\Local\Programs\PPPx`) to your user `PATH`:

```PowerShell
git clone --depth 1 https://github.com/pppx-dev/pppx.git
cd pppx
.\install.ps1
```
The installer also installs and configures the wrapper script `pppx.sh` (pointing it at
the `table` folder in the cloned repository). While `pppx.sh` cannot run in PowerShell or
cmd.exe, you can run it from **Git Bash**, which is bundled with [Git for Windows](https://git-scm.com/download/win)
(the same tool used for `git clone`). Product downloads rely on `curl`, which Git Bash
provides:

```shell
# In Git Bash
pppx.sh -c pppx.ini rinex/ZIM200CHE_R_20221000000_01D_30S_MO.rnx
```

> Note: You must restart PowerShell, cmd.exe, or Git Bash after installation.


### macOS

`pppx` supports only Apple silicon Macs running a macOS version newer than Monterey.

⚠️ **Prerequisite**

If you do not have [Homebrew](https://brew.sh/) on your Mac, please install it first:

```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

`pppx` is linked against the latest `ceres-solver` library, so make sure the
latest version is installed on your Mac as well. Run the following command in
the Terminal application:

```shell
brew install ceres-solver
```


Clone the repository and run the installer from its root folder in the Terminal:

```shell
git clone --depth 1 https://github.com/pppx-dev/pppx.git
cd pppx
./install.sh
```

The installer downloads the latest `pppx` executable, bypasses Apple's quarantine
security check, installs both `pppx` and the wrapper script `pppx.sh` to `~/.local/bin`,
and configures `pppx.sh` to use the `table` files in the cloned repository. Keeping the
repository is recommended, as it provides the `table` files and examples used by `pppx`.


## Usage

The general steps to process GNSS data with `pppx` are:
1. Prepare RINEX observation files and the necessary products (either broadcast ephemerides or precise products)
2. Modify an existing configuration file `pppx.ini`, or create one from a template:

```shell
pppx -x ppp > pppx.ini  # ppp can be replaced with spp/rtk/tdp
```

3. Run `pppx` with the appropriate command-line arguments:

```shell
pppx -c pppx.ini path-to-rnxo [rnxo-of-base]

# Example usage:

# For SPP/PPP/TDP  (Note: TDP is suitable for high-frequency data, e.g., 1 Hz)
pppx -c pppx.ini rinex/ZIM200CHE_R_20221000000_01D_30S_MO.rnx

# For RTK (ZIMM is the base station in this example)
pppx -c pppx.ini rinex/ZIM200CHE_R_20221000000_01D_30S_MO.rnx rinex/ZIMM00CHE_R_20221000000_01D_30S_MO.rnx
```

To simplify GNSS data processing, the script `scripts/pppx.sh` is provided. It
automatically downloads the necessary products (e.g., SP3, CLK, OBX, BIA, ERP, BRDC, GIM, VMF1)
according to the configuration and then invokes `pppx`. Currently, it supports
only the operational products from [CODE](http://ftp.aiub.unibe.ch/CODE/).
The recommended way to use this wrapper script is:

```shell
# Generate a default config file
pppx -x ppp > pppx.ini   # options: spp/ppp/rtk/tdp

# Edit pppx.ini if necessary, but leave [product] (except "src") and [table] blank
pppx.sh -c pppx.ini rinex/ZIM200CHE_R_20221000000_01D_30S_MO.rnx
```

> **NOTE**: `pppx.sh` is installed and configured automatically by the installer
(`install.sh` on Linux/macOS, `install.ps1` on Windows), pointing it at the `table`
folder in your cloned repository, so `pppx.sh -c ...` works out of the box. It runs
natively on Linux and macOS, and on Windows via Git Bash. It requires only `curl` and
standard Unix tools, which are available by default on these platforms.


### Input

1. Configuration file: [pppx.ini](pppx.ini)
2. GNSS observations: RINEX files
3. Satellite products: Broadcast ephemeris or precise products, specified in `pppx.ini`
4. Table files: Provided in the [table](table/) directory, specified in `pppx.ini`


### Output

1. `pos file`: Receiver position, clock, and ZTD estimates for each epoch
2. `log file`: Debugging information
3. `stat file`: Postfit residuals and various estimates in the RTKLIB stat format, suitable for visualization with [RTKLIB](https://github.com/tomojitakasu/RTKLIB_bin/tree/rtklib_2.4.3)


### Visualization

#### With the PPPx Web Viewer

The [PPPx Web Viewer](https://app.pppx.dev/) is a browser-based app for interactive
viewing of PPPx results. Simply open the page and load a `.pos` or `.stat` file to
explore the position time series and a map view of the solution. No installation is
required, and it runs on any platform.

#### With Python

```shell
# To plot position estimates only
python scripts/plot_ppppos.py pos_file

# To plot position, receiver clock, and ZTD estimates
python scripts/plot_ppppos.py pos_file -a

# -a  Plot receiver position, clock, and ZTD estimates
# -i  Interactive mode
# -s  Fixed scale for the y-axis; otherwise, the scale is set automatically
```

#### With RTKLIB

For enhanced interactive viewing and visualization of postfit residuals:

1. Open the `rtkplot.exe` application
2. Navigate to "File" > "Open Solution-1" and select the generated stat file
3. Explore the various plots interactively


## Example

To help you get started, several examples are provided in the
[example/pppx](example/pppx) folder. In addition, an example demonstrating how
`pppx` processes GNSS data collected by Android smartphones is available in
the [example/smartphone](example/smartphone) folder. Run the corresponding
`run.sh` script to see how `pppx` works:

```shell
cd example/pppx/
./run.sh   # processing & plotting
```

For instance, the figure below shows a kinematic PPP solution for the ZIM2
station, computed with FGO using GPS+Galileo observations:

<img src="example/pppx/03_ppp_fgo/ZIM200CHE_R_20221000000_01D_30S_MO.png" width="500">


## Contributing

If you have suggestions or encounter problems while using the PPPx software,
please open an [issue](https://github.com/pppx-dev/pppx/issues/new).


## Author

- **Yuanxin Pan** - [YuanxinPan](https://github.com/YuanxinPan)


## License

PPPx is distributed as a **closed-source binary** and is **free for academic,
research, and educational use only**. Commercial use and redistribution of the
binary are **not permitted**. See the [LICENSE](LICENSE) file for the full terms.

For commercial licensing or redistribution permissions, please contact the author.


## Citation

If you use PPPx in your work, please cite it via its Zenodo DOI:

> Yuanxin Pan. *YuanxinPan/PPPx_bin*. Zenodo. https://doi.org/10.5281/zenodo.12759169
