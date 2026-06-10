#!/bin/bash

###############################################################################
##                                                                           ##
##  PURPOSE: GNSS data processing with PPPx                                  ##
##                                                                           ##
##  AUTHOR : Yuanxin Pan (yxpan.im@gmail.com)                                ##
##                                                                           ##
##  VERSION: 1.1.0                                                           ##
##                                                                           ##
##    Copyright (C) 2026 by Yuanxin Pan                                      ##
##                                                                           ##
##    This program is free software: you can redistribute it and/or modify   ##
##    it under the terms of the GNU General Public License (version 3) as    ##
##    published by the Free Software Foundation.                             ##
##                                                                           ##
##    This program is distributed in the hope that it will be useful,        ##
##    but WITHOUT ANY WARRANTY; without even the implied warranty of         ##
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          ##
##    GNU General Public License (version 3) for more details.               ##
##                                                                           ##
##    You should have received a copy of the GNU General Public License      ##
##    along with this program.  If not, see <https://www.gnu.org/licenses/>. ##
##                                                                           ##
###############################################################################


######################################################################
##                        Message Colors                            ##
######################################################################
NC='\033[0m'
RED='\033[0;31m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'

MSGERR="${RED}error:$NC"
MSGWAR="${YELLOW}warning:$NC"
MSGINF="${BLUE}::$NC"
MSGSTA="${BLUE}===>$NC"

readonly TABLE_DIR="PACKAGE_ROOT/table"
readonly PRODUCT_DIR="./products"

######################################################################
##                     Funciton definations                         ##
######################################################################
main()
{
    CheckCmdArgs "$@" || return 1  # set: config rnxobs rnxbas
    CheckExecutables || return 1

    # Download products
    local mjd=$(GetRinexMjd "$rnxobs")
    product_args=""
    PrepareProducts $mjd "$PRODUCT_DIR" "$config" || return 1  # set: product_args

    # Default paths for missing tables
    local table_args=$(GetTableArgs $mjd "$TABLE_DIR" "$config")

    # Process
    echo pppx "$@" $product_args $table_args
    pppx "$@" $product_args $table_args
}

CheckCmdArgs() { # purpose: chech whether command line arguments are right
                 # usage  : CheckCmdArgs "$@"
    # [ $# -ne 2 -a $# -ne 3 ] && PPPx_Help && return 1

    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -c | --cfg )
            config="$2"
            shift 2
            ;;
        -* )
            PPPx_Help
            return 1
            ;;
        * )
            positional+=("$1")
            shift
            ;;
        esac
    done
    rnxobs=${positional[0]}
    rnxbas=${positional[1]}
    [ -z "$config" -o -z "$rnxobs" ] && PPPx_Help && return 1

    if [ ! -f "$config" ]; then
        echo -e "$MSGERR no such config: $config"
        return 1
    elif [ ! -f ${rnxobs} ]; then
        echo -e "$MSGERR no such rnxobs: $rnxobs"
        return 1
    fi

    local sol_mode=$(GetConfigOption "sol_mode" "$config")
    [ -z $sol_mode ] && sol_mode="ppp"  # default mode
    if [ "$sol_mode" = "rtk" ]; then
       [ ! -f "$rnxbas" ] && echo -e "$MSGERR no such rnxbas: $rnxbas" && return 1
    fi
    return 0
}

CheckExecutables() { # purpose: check whether all needed executables are callable
                     # usage  : CheckExecutables
    # echo -e "$MSGSTA CheckExecutables..."

    which pppx > /dev/null 2>&1
    [ $? -ne 0 ] && echo -e "$MSGERR pppx not found" && return 1
    which wget > /dev/null 2>&1
    [ $? -ne 0 ] && echo -e "$MSGERR wget not found" && return 1
    which awk > /dev/null 2>&1
    [ $? -ne 0 ] && echo -e "$MSGERR awk not found" && return 1

    # echo -e "$MSGSTA CheckExecutables done"
    return 0
}

PPPx_Help() { # purpose: print usage for PPPx
              # usage  : PPPx_Help
    echo " ---------------------------------------------------------------"
    echo "  Purpose  :    GNSS data processing with PPPx"
    echo "  Usage    :    pppx.sh -c config rnxobs [rnxbas]"
    echo "                   -- config : configuration file"
    echo "                   -- rnxobs : RINEX-OBS file"
    echo "                   -- rnxbas : RINEX-OBS base station"
    echo "  Example  :    pppx.sh -c pppx.ini zim20010.24o"
    echo "                pppx.sh zim20010.24o zimm0010.24o -c pppx.ini"
    echo "  Copyright:    Yuanxin Pan, 2025"
    echo " ---------------------------------------------------------------"
}

GetConfigOption() {
    local opt="$1"
    local ctrl_file="$2"
    local value=$(sed -n "/^${opt}/ {s/${opt}\s*=\s*//; s/\s*\;.*$//; p}" "$ctrl_file")
    echo "$value"
}

GetRinexMjd() { # purpose: get MJD of the first epoch
                # usage  : GetRinexDate rnxobs
    local rnxobs="$1"
    local ymd_start
    local time_str=$(grep -E "^(> [ 0-9]{4} [ 0-1][0-9] | [ 0-9][0-9] [ 0-1][0-9] )" "$rnxobs" | head -1)
    if [[ "$time_str" =~ ^\>  ]]; then
        ymd_start=$(echo $time_str | awk '{print $2,$3,$4}')
    else
        ymd_start=$(echo $time_str | awk '{print $1,$2,$3}')
    fi

    local mjd_start=$(ymd2mjd ${ymd_start[*]})
    echo $mjd_start
}

SelectAtx() { # purpose: determine the version of igs.atx
              # usage  : SelectAtx table_dir mjd
    local table_dir="$1"
    local mjd=$2

    local atx=null
    if [ $mjd -lt 55668 ]; then
        atx="igs05.atx"
    elif [ $mjd -lt 57782 ]; then
        atx="igs08.atx"
    elif [ $mjd -lt 59910 ]; then
        atx="igs14.atx"
    else
        atx="igs20.atx"
    fi

    echo "$table_dir/$atx"
}

GetTableArgs() {
    local mjd=$1
    local table_dir="$2"
    local ctrl_file="$3"

    local sol_mode=$(GetConfigOption "sol_mode" "$ctrl_file")

    local atx_args=""
    local atx=$(GetConfigOption "igsatx" "$ctrl_file")
    [ -z "$atx" ] && atx=$(SelectAtx "$TABLE_DIR" $mjd) && atx_args="--atx $atx"

    local chn_args=""
    local chn=$(GetConfigOption "channel" "$ctrl_file")
    [ -z "$chn" -a "$sol_mode" != "spp" ] && chn="$TABLE_DIR/glonass_chn" && chn_args="--chn $chn"

    local ocl_args=""
    local ocl=$(GetConfigOption "oceanload" "$ctrl_file")
    [ -z "$ocl" -a "$sol_mode" = "ppp" ] && ocl="$TABLE_DIR/oceanload" && ocl_args="--ocl $ocl"


    local trop_model=$(GetConfigOption "trop" "$ctrl_file")

    local gpt2w_args=""
    local gpt2w=$(GetConfigOption "gpt2w" "$ctrl_file")
    [ -z "$gpt2w" -a "$trop_model" = "GPT2w" ] && gpt2w="$TABLE_DIR/gpt2_1wA.grd" && gpt2w_args="--gpt2w $gpt2w"

    local oro_args=""
    local oro=$(GetConfigOption "orography" "$ctrl_file")
    [ -z "$oro" -a "$trop_model" = "VMF1" ] && oro="$TABLE_DIR/orography_ell" && oro_args="--oro $oro"

    local table_args="$atx_args $chn_args $ocl_args $gpt2w_args $oro_args"
    echo "$table_args"
    return 0
}

PrepareProducts() { # purpose: prepare products in working directory
                    # usage  : PrepareProducts mjd products_dir config
    # echo -e "$MSGSTA PrepareProducts..."

    local mjd_mid=$1
    local products_dir="$2"
    local ctrl_file="$3"

    [ -d $products_dir ] || mkdir -p "$products_dir"

    grep "^ppp_ar\s*=\s*yes" "$ctrl_file" > /dev/null 2>&1
    local AR=$?
    local product_src=$(sed -n "/^src/ {s/src\s*=\s*//; s/\s*\;.*$//; p}" "$ctrl_file")
    # [ -z "$product_src" ] && echo -e "$MSGERR $ctrl_file: [product] src: not set " && return 1
    [ -z "$product_src" ] && product_src="precise"  # default source
    local ydoy=($(mjd2ydoy $mjd_mid))
    local wkdow=($(mjd2wkdow $mjd_mid))
    local year=${ydoy[0]}
    local doy=${ydoy[1]}
    local week=${wkdow[0]}
    local dow=${wkdow[1]}

    local ac="COD"
    local HOST="ftp://ftp.aiub.unibe.ch/CODE/$year"
    local rapid="no"
    local sp3 clk erp obx bia ion
    eval $(GetProductNames $mjd_mid $ac FIN)

    # VMF1 grids
    local vmf_args=""
    grep '^trop\s*=\s*VMF1' ${ctrl_file} 2>&1 > /dev/null
    if [ $? -eq 0 ]; then
        local vmf_spliced=${products_dir}/VMFG_${ydoy[0]}${ydoy[1]}
        DownloadVmf1Grids $mjd_mid ${products_dir} ${vmf_spliced} || return 1
        vmf_args="--vmf ${vmf_spliced}"
    fi

    # GIM
    local ion_args=""
    local ion_opt=$(GetConfigOption "iono" "$ctrl_file")
    if [ "$ion_opt" = "IONEX" ]; then
        local ion_no_suffix=$(StripCompressSuffix $ion)
        if ! DownloadProduct ${products_dir}/${ion_no_suffix} $HOST/$ion; then
            UseRapidProducts $mjd_mid $ac || return 1
            ion_no_suffix=$(StripCompressSuffix $ion)
            DownloadProduct ${products_dir}/${ion_no_suffix} $HOST/$ion || return 1
        fi
        ion_args="--ion ${products_dir}/${ion_no_suffix}"
    fi

    # BRDC
    local BRDC_HOST="ftp://gssc.esa.int/gnss/data/daily/${year}/brdc"
    local brdc=$(GetBrdcName $mjd_mid)
    if [ "$product_src" = "brdc" -o "$ion_opt" = "brdc" ]; then
        local brdc_no_suffix=$(StripCompressSuffix $brdc)
        local nav_args="--nav ${products_dir}/${brdc_no_suffix}"
        DownloadProduct ${products_dir}/${brdc_no_suffix} $BRDC_HOST/$brdc || return 1
        [ "$ion_opt" = "brdc" ] && product_args="$nav_args "
        [ "$product_src" = "brdc" ] && product_args="$nav_args $vmf_args $ion_args" && return 0
    elif [ "$product_src" != "precise" ]; then
        echo -e "$MSGERR $ctrl_file: [product] src: not set correctly"
        return 1
    fi

    # Fallback to rapid products if final ones are not available yet
    if [ "$rapid" = "no" ]; then
        DownloadProduct ${products_dir}/$(StripCompressSuffix $sp3) $HOST/$sp3 \
            || UseRapidProducts $mjd_mid $ac || return 1
    fi

    # Download
    local product_lists="$sp3 $clk $erp $obx"
    [ $AR -eq 0 ] && product_lists+=" $bia"
    for f in $product_lists
    do
        f_no_suffix=$(StripCompressSuffix $f)
        DownloadProduct ${products_dir}/${f_no_suffix} $HOST/$f
    done
    local sp3_base=$(StripCompressSuffix $sp3)
    local clk_base=$(StripCompressSuffix $clk)
    local erp_base=$(StripCompressSuffix $erp)
    local obx_base=$(StripCompressSuffix $obx)
    local bia_base=$(StripCompressSuffix $bia)
    [ ! -f $products_dir/$sp3_base ] && echo -e "${MSGERR} Download $sp3 failed" && return 1
    [ $AR -eq 0 -a ! -f $products_dir/$bia_base ] && echo -e "${MSGERR} Download $bia failed" && return 1

    local sp3_args clk_args erp_args obx_args bia_args
    [ -f $products_dir/$sp3_base ] && sp3_args="--sp3 $products_dir/$sp3_base"
    [ -f $products_dir/$clk_base ] && clk_args="--clk $products_dir/$clk_base"
    [ -f $products_dir/$erp_base ] && erp_args="--erp $products_dir/$erp_base"
    [ -f $products_dir/$obx_base ] && obx_args="--obx $products_dir/$obx_base"
    [ $AR -eq 0 -a -f $products_dir/$bia_base ] && bia_args="--bia $products_dir/$bia_base"

    # echo -e "$MSGSTA PrepareProducts done"
    product_args+="$sp3_args $clk_args $erp_args $obx_args $bia_args $vmf_args $ion_args"
    return 0
}

GetBrdcName() { # purpose: Get the name of broadcast ephemeris
                # usage  : GetBrdcNames mjd
    local mjd=$1

    local ydoy=($(mjd2ydoy $mjd))
    local year=${ydoy[0]}
    local doy=${ydoy[1]}

    local brdc="BRDC00IGS_R_${year}${doy}0000_01D_MN.rnx.gz"

    [ $mjd -lt 57288 ] && brdc="brdc${doy}0.${year:2:2}n.Z"

    echo "$brdc"
    return 0
}

GetProductNames() { # purpose: Get products name of a specific AC
                    # usage  : GetProductNames mjd ac [FIN|RAP]
    local mjd=$1
    local ac=$2
    local typ=${3:-FIN}

    local ydoy=($(mjd2ydoy $mjd))
    local wkdow=($(mjd2wkdow $mjd))
    local year=${ydoy[0]}
    local doy=${ydoy[1]}
    local week=${wkdow[0]}
    local dow=${wkdow[1]}

    local gz=".gz"
    [ "$typ" = "RAP" ] && gz=""  # rapid products are uncompressed (except GIM)

    local sp3="${ac^^}0OPS${typ}_${year}${doy}0000_01D_05M_ORB.SP3${gz}"
    local clk="${ac^^}0OPS${typ}_${year}${doy}0000_01D_30S_CLK.CLK${gz}"
    local erp="${ac^^}0OPS${typ}_${year}${doy}0000_01D_01D_ERP.ERP${gz}"
    local obx="${ac^^}0OPS${typ}_${year}${doy}0000_01D_30S_ATT.OBX${gz}"
    local bia="${ac^^}0OPS${typ}_${year}${doy}0000_01D_01D_OSB.BIA${gz}"
    local ion="${ac^^}0OPS${typ}_${year}${doy}0000_01D_01H_GIM.INX.gz"

    if [ $mjd -lt 59910 ]; then
        sp3="${ac^^}${week}${dow}.EPH.Z"
        clk="${ac^^}${week}${dow}.CLK.Z"
        erp="${ac^^}${week}${dow}.ERP.Z"
        obx="${ac^^}${week}${dow}.OBX.Z"
        bia="${ac^^}${week}${dow}.BIA.Z"
        ion="${ac^^}G${doy}0.${year:2:2}I.Z"
    fi

    echo "sp3=$sp3; clk=$clk; erp=$erp; obx=$obx; bia=$bia; ion=$ion"
    return 0
}

UseRapidProducts() { # purpose: switch product set to CODE rapid (caller vars: HOST sp3 clk erp obx bia ion rapid)
                     # usage  : UseRapidProducts mjd ac
    local mjd=$1
    local ac=$2

    [ $mjd -lt 59910 ] && return 1  # only short-name rapid products before GPS week 2238

    echo -e "$MSGWAR final products not available, falling back to CODE rapid products"
    HOST="ftp://ftp.aiub.unibe.ch/CODE"  # rapid products reside at the top level
    eval $(GetProductNames $mjd $ac RAP)
    rapid="yes"
    return 0
}

StripCompressSuffix() { # purpose: strip trailing .gz/.Z from a filename
                        # usage  : StripCompressSuffix file
    local name="$1"
    name="${name%.gz}"
    echo "${name%.Z}"
}

DownloadVmf1Grids() { # purpose: Download and splice VMF1 grids
                      # usage  : DownloadVmf1Grids mjd products_dir vmf_spliced
    # echo -e "$MSGSTA Downloading VMF1 GRID..."

    local mjd_mid=$1
    local products_dir="$2"
    local vmf_spliced="$3"

    local ydoy=($(mjd2ydoy $mjd_mid))
    local ymd=($(ydoy2ymd ${ydoy[*]}))

    local VMF_HOST="http://vmf.geo.tuwien.ac.at/trop_products/GRID/2.5x2/VMF1/VMF1_OP"
    local vmf vmf_url hour tmpy
    local vmf_url_lists=""

    # Previous Day (for interpolation)
    tmpy=($(mjd2ydoy $((mjd_mid-1))))
    tmpy=($(ydoy2ymd ${tmpy[*]}))
    vmf="VMFG_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H18"
    vmf_url_lists+=" $VMF_HOST/${tmpy[0]}/${vmf}"

    # Current Day (for interpolation)
    for hour in `seq 0 6 18 | awk '{printf("%02d\n",$1)}'`
    do
        vmf="VMFG_${ymd[0]}${ymd[1]}${ymd[2]}.H${hour}"
        vmf_url_lists+=" $VMF_HOST/${ydoy[0]}/${vmf}"
    done

    # Next Day (for interpolation)
    tmpy=($(mjd2ydoy $((mjd_mid+1))))
    tmpy=($(ydoy2ymd ${tmpy[*]}))
    vmf="VMFG_${tmpy[0]}${tmpy[1]}${tmpy[2]}.H00"
    vmf_url_lists+=" $VMF_HOST/${tmpy[0]}/${vmf}"

    # Download
    rm -f ${vmf_spliced}
    for vmf_url in $vmf_url_lists
    do
        vmf=$products_dir/$(basename "$vmf_url")
        DownloadProduct "$vmf" "$vmf_url" || return 1
        cat $vmf >> ${vmf_spliced}
    done

    # echo -e "$MSGSTA Downloading VMF1 GRID done"
    return 0
}

DownloadProduct() { # purpose: download and uncompress a product
                    # usage  : DownloadProduct file_no_suffix url
    local file="$1"
    local url="$2"
    local base_no_suffix=$(basename -- "$url" ".${url##*.}")
    local suffix=".${url##*.}"
    if [ -f "$file" ]; then
        return 0
    else
        WgetDownload "$url" || return 1
        if [ $suffix = '.Z' -o $suffix = '.gz' ]; then
            gunzip -f $(basename "$url") || return 1
        else
            base_no_suffix=$(basename "$url")
        fi
        [ ! "$base_no_suffix" = "$file" ] && mv "$base_no_suffix" "$file"
        return 0
    fi
}

WgetDownload() { # purpose: download a file with wget
                 # usage  : WgetDownload url
    local url="$1"
    local args="-nv -nc -c -t 3 --connect-timeout=10 --read-timeout=60"

    wget ${args} ${url}
    [ -e $(basename "${url}") ] && return 0 || return 1
}

LastYearMonth() { # purpose: get last year-month
                  # usage  : LastYearMonth year month
    local year=$1
    local mon=$((10#$2))
    [ $((mon-1)) -lt 1  ] && mon=12 && year=$((year-1)) || mon=$((mon-1))
    printf "%4d %02d\n" $year $mon
}

UncompressFile() { # purpose: uncompress a file automatically
                   # usage  : UncompressFile file del(Y/N)
    local file="$1"
    local del=$2
    # file $file
}

######################################################################
##                      Time Convert Funcitons                      ##
######################################################################
ymd2mjd()
{
    local year=$1
    local mon=$((10#$2))
    local day=$((10#$3))
    [ $year -lt 100 ] && year=$((year+2000))
    if [ $mon -le 2 ];then
        mon=$(($mon+12))
        year=$(($year-1))
    fi
    local mjd=`echo $year | awk '{print $1*365.25-$1*365.25%1-679006}'`
    mjd=`echo $mjd $year $mon $day | awk '{print $1+int(30.6001*($3+1))+2-int($2/100)+int($2/400)+$4}'`
    #local mjd=$(bc <<< "$year*365.25 - $year*365.25 % 1 - 679006")
    #mjd=$(bc <<< "($mjd + (30.6001*($mon+1))/1 + 2 - $year/100 + $year/400 + $day)/1")
    echo $mjd
}

mjd2ydoy()
{
    local mjd=$1
    local year=$((($mjd + 678940)/365))
    local mjd0=$(ymd2mjd $year 1 1)
    local doy=$(($mjd-$mjd0))
    while [ $doy -le 0 ];do
        year=$(($year-1))
        mjd0=$(ymd2mjd $year 1 1)
        doy=$(($mjd-$mjd0+1))
    done
    printf "%d %03d\n" $year $doy
}

ymd2wkdow()
{
    local year=$1
    local mon=$2
    local day=$3
    local mjd0=44243
    local mjd=$(ymd2mjd $year $mon $day)
    local difmjd=$(($mjd-$mjd0-1))
    local week=$(($difmjd/7))
    local dow=$(($difmjd%7))
    echo $week $dow
}

mjd2wkdow()
{
    local mjd=$1
    local mjd0=44243
    local difmjd=$(($mjd-$mjd0-1))
    local week=$(($difmjd/7))
    local dow=$(($difmjd%7))
    echo $week $dow
}

ydoy2ymd()
{
    local iyear=$1
    local idoy=$((10#$2))
    local days_in_month=(31 28 31 30 31 30 31 31 30 31 30 31)
    local iday=0
    [ $iyear -lt 100 ] && iyear=$((iyear+2000))
    local tmp1=$(($iyear%4))
    local tmp2=$(($iyear%100))
    local tmp3=$(($iyear%400))
    if [ $tmp1 -eq 0 -a $tmp2 -ne 0 ] || [ $tmp3 -eq 0 ]; then
       days_in_month[1]=29
    fi
    local id=$idoy
    local imon=0
    local days
    for days in ${days_in_month[*]}
    do
        id=$(($id-$days))
        imon=$(($imon+1))
        if [ $id -gt 0 ]; then
            continue
        fi
        iday=$(($id + $days))
        break
    done
    printf "%d %02d %02d\n" $iyear $imon $iday
}


######################################################################
##                               Entry                              ##
######################################################################
main "$@"

