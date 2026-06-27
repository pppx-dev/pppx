#!/usr/bin/env python3

import sys
import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator, StrMethodFormatter, FuncFormatter

def xyz2blh(xyz):
    """
    Purpose: ECEF to Geodetic position
    Inputs:  xyz: nx3 ecef vector [m]
    Outputs: blh: nx3 blh vector  [deg, deg, m]
    """
    R2D = 180.0/np.pi
    a = 6378137.0000    # earth radius in meters    (WGS84)
    b = 6356752.3142    # earth semiminor in meters (WGS84)

    x2 = xyz[:,0]**2
    y2 = xyz[:,1]**2
    z2 = xyz[:,2]**2

    e   = np.sqrt(1 - (b/a)**2)
    b2  = b*b
    e2  = e**2
    ep  = e*(a/b)
    r   = np.sqrt(x2 + y2)
    r2  = r*r
    E2  = a**2 - b**2
    F   = 54*b2*z2
    G   = r2 + (1 - e2)*z2 - e2*E2
    c   = ((e2*e2)*F*r2)/(G**3)
    s   = (1 + c + np.sqrt(c*c + 2*c))**(1/3)
    P   = F/(3*(s + 1/s + 1)**2*G*G)
    Q   = np.sqrt(1 + 2*e2*e2*P)
    ro  = -(P*e2*r)/(1 + Q) + np.sqrt((a*a/2)*(1 + 1/Q) - (P*(1 - e2)*z2)/(Q*(1 + Q)) - P*r2/2)
    tmp = (r - e2*ro)**2
    U   = np.sqrt(tmp + z2)
    V   = np.sqrt(tmp + (1 - e2)*z2)
    zo  = (b2*xyz[:, 2])/(a*V)

    h   = U*(1 - b2/(a*V))                              # ellipsoidal height
    lat = np.arctan((xyz[:, 2] + ep*ep*zo)/r)*R2D       # latitude [degree]

    # longitude [degree]
    lon      = np.arctan(xyz[:, 1]/xyz[:, 0])*R2D
    ind      = np.logical_and(xyz[:, 0]<0, xyz[:, 1]>=0)
    lon[ind] = lon[ind] + 180
    ind      = np.logical_and(xyz[:, 0]<0, xyz[:, 1]<0)
    lon[ind] = lon[ind] - 180

    h   = h.reshape((1, -1))
    lat = lat.reshape((1, -1))
    lon = lon.reshape((1, -1))
    llh = np.hstack((lat.T, lon.T, h.T))
    return llh

def xyz2enu(xyz, orgxyz):
    """
    Purpose: ECEF to ENU position
    Inputs:  xyz   : nx3 ecef vector [m]
             orgxyz: 1x3 ecef vector [m]
    Outputs: enu   : nx3 enu  vector [m]
    """
    D2R = np.pi/180.0
    n = xyz.shape[0]
    difxyz = xyz - np.tile(orgxyz, (n, 1))
    orgllh = xyz2blh(orgxyz)
    phi = orgllh[0, 0]*D2R
    lam = orgllh[0, 1]*D2R
    sinphi = np.sin(phi)
    cosphi = np.cos(phi)
    sinlam = np.sin(lam)
    coslam = np.cos(lam)
    R = [[       -sinlam,         coslam,      0],
         [-sinphi*coslam, -sinphi*sinlam, cosphi],
         [ cosphi*coslam, cosphi*sinlam , sinphi]]
    enu = np.dot(R, difxyz.T).T
    return enu

def create_time_formatter(span_hours):
    """Create a formatter function appropriate for the time span in hours"""
    if span_hours < 1/60:  # < 1 minute, show seconds
        def formatter(x, pos):
            sec = round(x * 3600, 1)
            return f"{sec:.1f}"
        return formatter
    elif span_hours < 1:  # < 1 hour, show MM:SS
        def formatter(x, pos):
            total_sec = round(x * 3600)  # Round to nearest second
            minutes = total_sec // 60
            seconds = total_sec % 60
            return f"{int(minutes)}:{int(seconds):02d}"
        return formatter
    elif span_hours < 24:  # 1-24 hours, show HH:MM
        def formatter(x, pos):
            total_min = round(x * 60)  # Round to nearest minute
            hours_int = total_min // 60
            minutes = total_min % 60
            return f"{int(hours_int)}:{int(minutes):02d}"
        return formatter
    else:  # >= 24 hours, show HH
        return lambda x, pos: f"{int(round(x)):02d}"

def get_time_unit_label(span_hours):
    """Return appropriate axis label based on time span"""
    if span_hours < 1/60:  # < 1 minute
        return "Time (seconds)"
    elif span_hours < 1:  # < 1 hour
        return "Time (minutes)"
    elif span_hours < 24:  # 1-24 hours
        return "Time (hours)"
    else:  # >= 24 hours
        return "Time (hours)"

def choose_time_axis(hours):
    hours = np.asarray(hours, dtype=float)
    hours = hours[np.isfinite(hours)]
    if hours.size == 0:
        return 0.0, 1.0, 1.0, 0.2

    hour_min = float(np.min(hours))
    hour_max = float(np.max(hours))
    span = max(hour_max - hour_min, 1e-6)

    candidate_steps = np.array([
        10/3600, 15/3600, 30/3600,              # 10s, 15s, 30s
        1/60, 2/60, 5/60, 10/60, 15/60, 30/60,  # 1m, 2m, 5m, 10m, 15m, 30m
        0.5, 1, 2, 3, 4, 6, 8, 12, 24           # 0.5h, 1h, ..., 24h
    ], dtype=float)

    major_tick = float(candidate_steps[np.argmin(np.abs(span / candidate_steps - 6.0))])
    minor_tick = major_tick / 4

    padding = span / 48.0
    x_min = hour_min - padding
    x_max = hour_max + padding

    return x_min, x_max, major_tick, minor_tick

def read_data(path):
    if path.endswith('.pos'):
        # column_names = [ 'sod', 'nsat', 'x', 'y', 'z', 'rck', 'zhd', 'zwd', 'dzwd' ]
        # df = pd.read_csv(path, usecols=(1,2,3,4,5,9,10,11,12), delimiter='\s+', names=column_names, header=None, skiprows=1)
        df = pd.read_csv(path, usecols=(1,2,3,4,5,9,10,11,12), delimiter='\\s+')
        df['hour'] = df['sod']/3600
        df['ztd'] = df['zhd'] + df['zwd'] + df['dzwd']

        mean = np.expand_dims(np.mean(df.iloc[:,2:5], axis=0), axis=0)
        enu = xyz2enu(df[['x', 'y', 'z']], mean)
        df['e'] = enu[:,0]
        df['n'] = enu[:,1]
        df['u'] = enu[:,2]
        return df
    # elif path.endwith('.stat'):
    #     column_names = [ 'sod', 'x', 'y', 'z', 'nsat' ]
    #     exclude = [i for i, line in enumerate(open(path)) if not line.startswith('$POS')]
    #     df = pd.read_csv(path, usecols=(2,4,5,6,10), names=column_names, skiprows=exclude, header=None)
    else:
        print(f"error: not a valid input: {path}")
        return None

def format_axis(a, x_major_tick=None, x_minor_tick=None, y_major_tick=None, y_minor_tick=None, span_hours=None):
    # Frame Width
    fwidth = 1.5
    a.spines['bottom'].set_linewidth(fwidth)
    a.spines['left'].set_linewidth(fwidth)
    a.spines['top'].set_linewidth(fwidth)
    a.spines['right'].set_linewidth(fwidth)
    # Tick
    a.tick_params(axis='both', which='both', direction='in', right=True, top=True)
    a.tick_params(axis='both', which='major', length=4)
    a.tick_params(axis='both', which='minor', length=2)
    # Notation (tick label)
    a.tick_params(axis='both', labelsize=12)
    # a.tick_params(axis='x', labelrotation=0.0)
    if x_major_tick is not None:
        a.xaxis.set_major_locator(MultipleLocator(x_major_tick))
    if x_minor_tick is not None:
        a.xaxis.set_minor_locator(MultipleLocator(x_minor_tick))
    if span_hours is not None:
        a.xaxis.set_major_formatter(FuncFormatter(create_time_formatter(span_hours)))
    else:
        a.xaxis.set_major_formatter(StrMethodFormatter('{x:g}'))
    if y_major_tick is not None:
        a.yaxis.set_major_locator(MultipleLocator(y_major_tick))
    if y_minor_tick is not None:
        a.yaxis.set_minor_locator(MultipleLocator(y_minor_tick))
    # a.yaxis.set_major_formatter(FormatStrFormatter('%d'))
    # Label
    a.xaxis.label.set_size(14)
    a.yaxis.label.set_size(14)

def plot_pppx(df, is_plot_all=False, is_scaled=False):
    if sys.platform in [ 'linux', 'linux2' ]:
        plt.rc('font', family='Liberation Sans')
    elif sys.platform in [ 'win32', 'darwin' ]:
        plt.rc('font', family='Arial')

    fig, axes = plt.subplots(4, 1, sharex=True, dpi=200, figsize=(6.4, 6.4))

    x_min, x_max, x_major_tick, x_minor_tick = choose_time_axis(df['hour'])
    span_hours = x_max - x_min

    std = np.std(df[['e', 'n', 'u']]*100, axis=0).to_numpy()
    if is_plot_all:
        axes[0].plot(df['hour'], 100*df['e'], linewidth=1, color='tab:red', label='East')  # m -> cm
        axes[0].plot(df['hour'], 100*df['n'], linewidth=1, color='tab:green', label='North')
        axes[0].plot(df['hour'], 100*df['u'], linewidth=1, color='tab:blue', label='Up')
        axes[0].legend(ncol=3, loc='upper left')
        axes[0].text(0.96, 0.80, f"{std[0]:5.2f} {std[1]:5.2f} {std[2]:5.2f} cm", fontsize=12,
                horizontalalignment='right', verticalalignment='center', transform=axes[0].transAxes)
        axes[1].plot(df['hour'], df['rck(m)']/3E2)  # m -> us
        axes[2].plot(df['hour'], 1000*df['ztd'])    # m -> mm
    else:
        axes[0].plot(df['hour'], 100*df['e'], '.', markersize=1, color='tab:red', label='East')
        axes[1].plot(df['hour'], 100*df['n'], '.', markersize=1, color='tab:green', label='North')
        axes[2].plot(df['hour'], 100*df['u'], '.', markersize=1, color='tab:blue', label='Up')
        for i in range(3):
            axes[i].text(0.96, 0.80, f"{std[i]:5.2f} cm", fontsize=12,
                    horizontalalignment='right', verticalalignment='center', transform=axes[i].transAxes)

    axes[3].plot(df['hour'], df['nsat'], '--', linewidth=0.5, color='lightgrey')
    axes[3].plot(df['hour'], df['nsat'], '.', markersize=1)
    axes[3].set_xlabel(get_time_unit_label(span_hours))
    axes[3].set_xlim([x_min, x_max])

    ylabels = [ 'Position (cm)', 'Clock (us)', 'ZTD (mm)', 'nsat' ] if is_plot_all else [ "East (cm)", "North (cm)", "Up (cm)", "nsat"  ]
    ylims = [ [-10, 10], [-1000, 1000], [ 1900, 2400 ], [0, 40] ] if is_plot_all else [ [-10, 10], [-10, 10], [-10, 10], [0, 40] ]
    # ylims = [ [-10, 10], [-1000, 1000], [ 1900, 2400 ], [0, 40] ] if is_plot_all else [ [-5, 5], [-5, 5], [-5, 5], [0, 40] ]
    major_tick = 5 if is_scaled and not is_plot_all else None
    minor_tick = 1 if is_scaled and not is_plot_all else None
    for i in range(4):
        if is_scaled:
            axes[i].set_ylim(ylims[i])
        axes[i].set_ylabel(ylabels[i])
        format_axis(axes[i], x_major_tick, x_minor_tick, major_tick, minor_tick, span_hours)

    # Global Configuration
    mpl.rcParams['lines.linewidth'] = 0.5
    mpl.rcParams['lines.markersize'] = 0.1
    fig.subplots_adjust(hspace=0.10)
    fig.align_labels()
    return fig, axes



if __name__ == "__main__":
    if not len(sys.argv) in (2, 3, 4, 5):
        print("usage: %s pos [-a] [-s] [-i]"%(sys.argv[0]))
        sys.exit(1)

    is_plot_all    = True if '-a' in sys.argv else False  #
    is_scaled      = True if '-s' in sys.argv else False  # scaled y-axis
    is_interactive = True if '-i' in sys.argv else False  # interactive plot

    df = read_data(sys.argv[1])
    if df is None:
        sys.exit(1)

    std = np.std(df[['e', 'n', 'u']]*100, axis=0).to_numpy()
    print(f"{std[0]:8.2f} {std[1]:8.2f} {std[2]:8.2f}")

    fig, axes = plot_pppx(df, is_plot_all, is_scaled)

    fig.savefig(sys.argv[1][:-3]+'png', bbox_inches='tight', pad_inches=None)
    if is_interactive:
        plt.show()
