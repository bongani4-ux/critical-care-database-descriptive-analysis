"""
Generates Figures 1-7 for the scoping review, at 600 dpi, serif type,
colour-blind-checked palette. Every figure is drawn from dbdata.py.
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.lines import Line2D

import dbdata as D

D.apply_style()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures")
os.makedirs(OUT, exist_ok=True)

# --- validated categorical tokens (see palette validation in methods log) ----
BLUE, AMBER, GREEN, RED = "#2266CC", "#E08A00", "#178A5A", "#CC3B2E"
INK, MUTED, HAIR = "#1A1A1A", "#5A6470", "#C8CDD4"

SEQ_BLUE = LinearSegmentedColormap.from_list("seqblue", ["#F2F6FC", "#9EC0E8", "#4E8FD6", "#1B4F91"])
SEQ_WARM = LinearSegmentedColormap.from_list("seqwarm", ["#FDF4E8", "#F3CE95", "#DE9A33", "#95590A"])


def save(fig, stem):
    for ext in ("png", "tif", "pdf"):
        kw = dict(pil_kwargs={"compression": "tiff_lzw"}) if ext == "tif" else {}
        fig.savefig(os.path.join(OUT, f"{stem}.{ext}"), dpi=600, **kw)
    plt.close(fig)
    print("  wrote", stem)


def ptitle(ax, letter, text, x=0.0):
    ax.set_title(f"({letter})  {text}", loc="left", x=x, pad=10,
                 fontweight="bold", fontsize=9.8, color=INK)


def footnote(fig, text, y=0.005, size=7.4):
    """No-op. Explanatory text lives in the manuscript figure legends; repeating
    it inside the artwork duplicates the legend and is disallowed by most
    journals. The calls are kept so the legend text stays with the code that
    draws each panel."""
    return


# ============================================================ FIGURE 1 ======
def figure1():
    fig, ax = plt.subplots(figsize=(6.6, 6.4))
    ax.set_xlim(0, 10); ax.set_ylim(-0.6, 8.35); ax.axis("off")

    stages = [("Identification", 8.05, 4.75), ("Eligibility", 4.30, 3.10), ("Included", 2.20, 0.90)]
    boxes = [
        (8.05, 1.55,
         "Databases identified by consolidating four prior comparative reviews\n"
         "of publicly available critical-care and perioperative databases,\n"
         "each updated to its current version and access status (June 2026)"),
        (6.30, 1.55,
         "Supplemented by direct screening of the PhysioNet repository listing\n"
         "(9 of 11 included resources) and by hand-searching each database's\n"
         "own project page; MOVER and AmsterdamUMCdb are hosted independently"),
        (4.30, 1.20,
         "Each candidate resource checked independently against the\n"
         "Population–Concept–Context eligibility criteria (Methods)"),
        (2.20, 1.30, None),
    ]
    for i, (ytop, h, text) in enumerate(boxes):
        last = text is None
        ax.add_patch(FancyBboxPatch(
            (1.55, ytop - h), 7.9, h,
            boxstyle="round,pad=0.02,rounding_size=0.12",
            linewidth=1.5 if last else 1.0,
            edgecolor="#1B3A63", facecolor="white", zorder=2))
        if last:
            ax.text(5.5, ytop - h / 2,
                    "Database resources included in the scoping review\n(n = 11)",
                    ha="center", va="center", fontsize=10.5, fontweight="bold",
                    color=INK, linespacing=1.5, zorder=3)
        else:
            ax.text(1.85, ytop - h / 2, text, ha="left", va="center",
                    fontsize=8.6, color=INK, linespacing=1.55, zorder=3)
        if i < len(boxes) - 1:
            y0 = ytop - h
            y1 = boxes[i + 1][0]
            ax.annotate("", xy=(5.5, y1), xytext=(5.5, y0),
                        arrowprops=dict(arrowstyle="-|>", color="#1B3A63", linewidth=1.1,
                                        shrinkA=0, shrinkB=0))

    for label, ytop, ybot in stages:
        ax.add_patch(FancyBboxPatch(
            (0.28, ybot), 0.62, ytop - ybot,
            boxstyle="round,pad=0.01,rounding_size=0.10",
            linewidth=0, facecolor="#1B3A63", zorder=2))
        ax.text(0.59, (ytop + ybot) / 2, label.upper(), rotation=90, ha="center",
                va="center", fontsize=7.0, fontweight="bold", color="white",
                zorder=3)

    ax.text(5.5, 0.10,
            "No independent bibliographic search or title/abstract screening was performed under this identification\n"
            "strategy; screening and exclusion counts are therefore not reportable (Methods; Limitations).\n"
            "A fully reproducible boolean search strategy for future systematic updates is given in Supplement S2.",
            ha="center", va="center", fontsize=7.4, color=MUTED, style="italic", linespacing=1.5)
    save(fig, "Figure_1")


# ============================================================ FIGURE 2 ======
def figure2():
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 4.1),
                             gridspec_kw=dict(width_ratios=[1.32, 1.0], wspace=0.34))

    # --- (A) cohort size ----------------------------------------------------
    ax = axes[0]
    rows = sorted(D.DATABASES, key=lambda r: r[4])
    names = [r[0] for r in rows]
    vals = [r[4] for r in rows]
    cols = [{"USA": BLUE, "Europe": GREEN, "Asia": AMBER}[r[1]] for r in rows]
    y = np.arange(len(rows))
    ax.barh(y, vals, color=cols, height=0.66, zorder=3)
    ax.set_xscale("log")
    ax.set_xlim(1000, 1.4e6)
    ax.set_yticks(y); ax.set_yticklabels(names)
    ax.set_xlabel("Cohort size (log scale)")
    ax.set_ylim(-0.75, len(rows) - 0.25)
    ax.xaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    ax.set_axisbelow(True)
    for yi, v in zip(y, vals):
        ax.text(v * 1.16, yi, f"{v:,}", va="center", ha="left",
                fontsize=8.2, color=INK)
    handles = [Rectangle((0, 0), 1, 1, facecolor=c, edgecolor="none")
               for c in (BLUE, AMBER, GREEN)]
    ax.legend(handles, ["United States", "Asia", "Europe"], loc="lower right",
              title="Region", title_fontsize=8.2, handlelength=1.1,
              handleheight=0.9, borderpad=0.4, labelspacing=0.35)
    ptitle(ax, "A", "Cohort size by database", x=-0.30)

    # --- (B) patients by region --------------------------------------------
    ax = axes[1]
    agg = {}
    for name, region, *_r, n, _b in D.DATABASES:
        a = agg.setdefault(region, [0, []])
        a[0] += n; a[1].append(name)
    order = sorted(agg, key=lambda r: -agg[r][0])
    x = np.arange(len(order))
    tot = [agg[r][0] for r in order]
    ax.bar(x, tot, width=0.58, color=[{"USA": BLUE, "Europe": GREEN, "Asia": AMBER}[r] for r in order], zorder=3)
    ax.set_xticks(x)
    ax.set_xticklabels(
        [f"{lbl}\n" + "\n".join(agg[r][1]) for lbl, r in
         zip(["United States", "Asia", "Europe"], order)], linespacing=1.55)
    for t in ax.get_xticklabels():
        t.set_fontsize(7.4)
    ax.set_ylabel("Patients (thousands)")
    ax.set_ylim(0, 700000)
    ax.set_yticks(np.arange(0, 700001, 100000))
    ax.set_yticklabels([f"{int(v/1000)}" for v in np.arange(0, 700001, 100000)])
    ax.yaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    ax.set_axisbelow(True)
    for xi, r in zip(x, order):
        n, dbs = agg[r]
        ax.text(xi, n + 16000, f"{n:,}\n({len(dbs)} databases)", ha="center",
                va="bottom", fontsize=8.2, color=INK, linespacing=1.35)
    ptitle(ax, "B", "Total patients by region", x=-0.20)

    footnote(fig,
             f"Eleven database resources, {D.TOTAL_N:,} patients in total, from six countries on three continents. "
             "MOVER is reported as a single resource pooling its EPIC and SIS sub-cohorts.\n"
             "VitalDB is counted as 6,388 surgical cases, the only entry whose denominator is not a unique-patient count.",
             y=-0.30)
    save(fig, "Figure_1")


# ============================================================ FIGURE 3 ======
def figure3():
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 4.3),
                             gridspec_kw=dict(width_ratios=[1.0, 1.0], wspace=0.42))

    setting_style = {
        "Perioperative":   (BLUE, None),
        "Adult ICU":       (RED, None),
        "ICU (infection)": (RED, "///"),
        "Pediatric ICU":  (AMBER, None),
        "Mixed":           (BLUE, "///"),
    }

    # --- (A) age ------------------------------------------------------------
    ax = axes[0]
    rows = sorted(D.DEMOGRAPHICS.items(), key=lambda kv: kv[1][0])
    names = [k for k, _ in rows]
    med = [v[0] for _, v in rows]
    lo = [v[0] - v[1] for _, v in rows]
    hi = [v[2] - v[0] for _, v in rows]
    y = np.arange(len(rows))
    for yi, (name, v) in zip(y, rows):
        c, h = setting_style[D.SETTING_OF[name]]
        ax.barh(yi, v[0], color=c, height=0.62, hatch=h, edgecolor="white",
                linewidth=0.0, zorder=3)
    ax.errorbar(med, y, xerr=[lo, hi], fmt="none", ecolor=INK,
                elinewidth=0.9, capsize=2.6, capthick=0.9, zorder=4)
    ax.set_yticks(y); ax.set_yticklabels(names)
    ax.set_xlabel("Age (years)")
    ax.set_xlim(0, 108)
    ax.set_ylim(-0.7, len(rows) - 0.3)
    ax.xaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    ax.set_axisbelow(True)
    for yi, (name, v) in zip(y, rows):
        lab = f"{v[0]:.1f} [{v[1]}–{v[2]}]" if name == "PIC" else f"{v[0]:.0f} [{v[1]:.0f}–{v[2]:.0f}]"
        if name == "MOVER":
            lab += "*"
        ax.text(v[2] + 3, yi, lab, va="center", ha="left", fontsize=7.9, color=INK)
    ptitle(ax, "A", "Median age with interquartile range", x=-0.34)

    # --- (B) sex ------------------------------------------------------------
    ax = axes[1]
    rows_s = sorted(D.DEMOGRAPHICS.items(), key=lambda kv: kv[1][3])
    names_s = [k for k, _ in rows_s]
    male = np.array([v[3] for _, v in rows_s])
    y = np.arange(len(rows_s))
    ax.barh(y, male, color=BLUE, height=0.62, zorder=3, label="Male")
    ax.barh(y, 100 - male, left=male, color=AMBER, height=0.62, zorder=3, label="Female")
    for yi, m in zip(y, male):
        ax.text(m / 2, yi, f"{m:.1f}", va="center", ha="center", fontsize=7.7,
                color="white", fontweight="bold")
        ax.text(m + (100 - m) / 2, yi, f"{100 - m:.1f}", va="center", ha="center",
                fontsize=7.7, color="white", fontweight="bold")
    ax.axvline(50, color="white", linewidth=0.8, linestyle=(0, (3, 2)), zorder=4)
    ax.set_yticks(y); ax.set_yticklabels(names_s)
    ax.set_xlabel("Proportion of cohort (%)")
    ax.set_xlim(0, 100); ax.set_ylim(-0.7, len(rows_s) - 0.3)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.135), ncol=2,
              handlelength=1.1, handleheight=0.9)
    ptitle(ax, "B", "Sex distribution", x=-0.34)

    handles = [Rectangle((0, 0), 1, 1, facecolor=c, hatch=h, edgecolor="white", linewidth=0.6)
               for c, h in (setting_style[k] for k in
                            ["Perioperative", "Adult ICU", "ICU (infection)", "Pediatric ICU", "Mixed"])]
    fig.legend(handles,
               ["Perioperative", "Adult ICU", "Adult ICU (infection-specific)",
                "Pediatric ICU", "Mixed hospital and ICU"],
               loc="lower center", bbox_to_anchor=(0.5, -0.10), ncol=5,
               handlelength=1.1, handleheight=0.9, columnspacing=1.1, fontsize=7.8)
    footnote(fig,
             "* MOVER is shown as a single resource: its median age is the patient-weighted mean of the EPIC "
             "(57 [42–68]) and SIS (53 [37–65]) sub-cohort medians, and the\nwhiskers span the union of the two "
             "sub-cohort interquartile ranges. PIC is a pediatric cohort; its position on the age axis is not "
             "comparable with the adult resources.",
             y=-0.20)
    save(fig, "Figure_2")


# ============================================================ FIGURE 4 ======
def _heat(ax, matrix, rowlabels, collabels, cmap, vmax, fmt="{:.1f}"):
    m = np.array(matrix, dtype=float)
    masked = np.ma.masked_invalid(m)
    norm = matplotlib.colors.PowerNorm(gamma=0.55, vmin=0, vmax=vmax)
    cmap = cmap.copy(); cmap.set_bad("#F4F5F6")
    ax.imshow(masked, cmap=cmap, norm=norm, aspect="auto")
    ax.set_xticks(np.arange(len(collabels)))
    ax.set_xticklabels(collabels, rotation=38, ha="right", rotation_mode="anchor")
    ax.set_yticks(np.arange(len(rowlabels)))
    ax.set_yticklabels(rowlabels)
    ax.set_xticks(np.arange(-0.5, len(collabels), 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(rowlabels), 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=1.4)
    ax.tick_params(which="minor", length=0)
    ax.tick_params(which="major", length=0)
    for s in ax.spines.values():
        s.set_visible(False)
    for i in range(m.shape[0]):
        for j in range(m.shape[1]):
            v = m[i, j]
            if np.isnan(v):
                ax.text(j, i, "—", ha="center", va="center", fontsize=8, color="#9AA1A9")
            else:
                dark = norm(v) > 0.62
                txt = "<0.1" if 0 < v < 0.05 else fmt.format(v)
                ax.text(j, i, txt, ha="center", va="center", fontsize=7.6,
                        color="white" if dark else INK,
                        fontweight="bold" if dark else "normal")


def figure4():
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 4.5),
                             gridspec_kw=dict(width_ratios=[1.0, 1.0], wspace=0.42))

    vm = [[D.VITALS[r][j] if D.VITALS[r][j] is not None else np.nan
           for j in range(len(D.VITAL_DBS))] for r in D.VITAL_ROWS]
    _heat(axes[0], vm, D.VITAL_ROWS, D.VITAL_DBS, SEQ_BLUE, vmax=57, fmt="{:.1f}")
    ptitle(axes[0], "A", "Vital signs (records per hour)", x=-0.42)

    lm = [[D.LABS[r][j] for j in range(len(D.LAB_DBS))] for r in D.LAB_ROWS]
    _heat(axes[1], lm, D.LAB_ROWS, D.LAB_DBS, SEQ_WARM, vmax=8.2, fmt="{:.1f}")
    ptitle(axes[1], "B", "Laboratory tests (records per day)", x=-0.52)

    footnote(fig,
             "Cell shading is scaled within each panel; the two panels use different units and are not directly comparable. "
             "Em dash denotes a measurement not recorded in that\nresource. Databases are ordered by overall recording frequency "
             "within each panel; only resources reporting granularity data are shown. ALT, alanine aminotransferase;\nBP, blood "
             "pressure; CRP, C-reactive protein; FiO₂, fraction of inspired oxygen; PaO₂, arterial partial pressure of oxygen; "
             "PEEP, positive end-expiratory pressure;\nSpO₂, peripheral oxygen saturation.",
             y=-0.16)
    save(fig, "FigureS2_granularity")


# ============================================================ FIGURE 5 ======
def figure5():
    cols = D.PERIOP_COLS + D.ICU_COLS
    m = np.array([[np.nan if v is None else float(v) for v in D.DOMAIN[r]] for r in D.DOMAIN_ROWS])
    overall = np.array(D.overall_coverage())
    rowavg = np.nanmean(np.nan_to_num(m, nan=0.0), axis=1)

    fig = plt.figure(figsize=(7.2, 7.4))
    gs = fig.add_gridspec(2, 2, height_ratios=[0.20, 1.0], width_ratios=[1.0, 0.20],
                          hspace=0.06, wspace=0.035)
    axt = fig.add_subplot(gs[0, 0])
    axh = fig.add_subplot(gs[1, 0])
    axr = fig.add_subplot(gs[1, 1])

    # top bar: overall coverage
    x = np.arange(len(cols))
    barcols = [BLUE] * len(D.PERIOP_COLS) + [RED] * len(D.ICU_COLS)
    axt.bar(x, overall, width=0.62, color=barcols, zorder=3)
    for xi, v in zip(x, overall):
        axt.text(xi, v + 2.5, f"{v:.0f}", ha="center", va="bottom", fontsize=7.6, color=INK)
    axt.set_xlim(-0.6, len(cols) - 0.4)
    axt.set_ylim(0, 100)
    axt.set_yticks([0, 50, 100])
    axt.set_ylabel("Overall\ncoverage (%)", fontsize=8)
    axt.set_xticks([])
    axt.yaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    axt.set_axisbelow(True)
    axt.axvline(len(D.PERIOP_COLS) - 0.5, color=INK, linewidth=0.9)
    axt.text((len(D.PERIOP_COLS) - 1) / 2, 106, "PERIOPERATIVE", ha="center", va="bottom",
             fontsize=8, fontweight="bold", color=BLUE)
    axt.text(len(D.PERIOP_COLS) + (len(D.ICU_COLS) - 1) / 2, 106, "CRITICAL CARE / ICU",
             ha="center", va="bottom", fontsize=8, fontweight="bold", color=RED)

    _heat(axh, m, D.DOMAIN_ROWS, cols, SEQ_BLUE, vmax=100, fmt="{:.0f}")
    axh.axvline(len(D.PERIOP_COLS) - 0.5, color=INK, linewidth=1.1)
    for lbl, c in zip(axh.get_xticklabels(),
                      [BLUE] * len(D.PERIOP_COLS) + [RED] * len(D.ICU_COLS)):
        lbl.set_color(c)
        lbl.set_fontweight("bold")

    # right bar: cross-database average per domain
    yy = np.arange(len(D.DOMAIN_ROWS))
    axr.barh(yy, rowavg, color="#8792A2", height=0.62, zorder=3)
    axr.set_ylim(len(D.DOMAIN_ROWS) - 0.5, -0.5)
    axr.set_xlim(0, 118)
    axr.set_yticks([])
    axr.set_xticks([0, 50, 100])
    axr.set_xlabel("Mean across\ndatabases (%)", fontsize=8)
    axr.xaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    axr.set_axisbelow(True)
    for yi, v in zip(yy, rowavg):
        axr.text(v + 4, yi, f"{v:.0f}", va="center", ha="left", fontsize=7.2, color=INK)

    footnote(fig,
             "Each cell is the percentage of charted subdomains documented within that domain group (85 subdomains across "
             "17 domain groups). Bars above give the percentage of all\n85 subdomains documented by each database; bars to "
             "the right give each domain group's mean across the eleven databases. Em dash denotes a domain group with no\n"
             "documented subdomain. Databases are ordered by overall coverage within each cluster.",
             y=0.004)
    fig.subplots_adjust(bottom=0.185)
    save(fig, "Figure_3")


# ============================================================ FIGURE 6 ======
def figure6():
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 4.4),
                             gridspec_kw=dict(width_ratios=[1.42, 1.0], wspace=0.26))

    # --- (A) grouped bars ---------------------------------------------------
    ax = axes[0]
    order = [d[0] for d in D.DATABASES]
    icu = [D.MORTALITY[n]["icu"] for n in order]
    hosp = []
    for n in order:
        m = D.MORTALITY[n]
        hosp.append(m["hosp"] if m["hosp"] is not None else m["last"])
    x = np.arange(len(order)); w = 0.38
    for xi, v in zip(x - w / 2, icu):
        if v is not None:
            ax.bar(xi, v, width=w, color=BLUE, zorder=3)
            ax.text(xi, v + 0.6, f"{v:.1f}", ha="center", va="bottom", fontsize=7.0,
                    color=INK, rotation=90)
        else:
            ax.text(xi, 0.55, "NR", ha="center", va="bottom", fontsize=6.6,
                    color="#9AA1A9", style="italic", rotation=90)
    for xi, n, v in zip(x + w / 2, order, hosp):
        if v is not None:
            star = "*" if n == "AmsterdamUMCdb" else ("†" if n == "SICdb" else "")
            ax.bar(xi, v, width=w, color=AMBER, zorder=3)
            ax.text(xi, v + 0.6, f"{v:.1f}{star}", ha="center", va="bottom", fontsize=7.0,
                    color=INK, rotation=90)
        else:
            ax.text(xi, 0.55, "NR", ha="center", va="bottom", fontsize=6.6,
                    color="#9AA1A9", style="italic", rotation=90)
    ax.set_xticks(x)
    ax.set_xticklabels(order, rotation=38, ha="right", rotation_mode="anchor")
    ax.set_ylabel("Mortality (%)")
    ax.set_ylim(0, 44)
    ax.yaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    ax.set_axisbelow(True)
    handles = [Rectangle((0, 0), 1, 1, facecolor=c, edgecolor="none") for c in (BLUE, AMBER)]
    ax.legend(handles, ["ICU mortality", "In-hospital or last-follow-up mortality"],
              loc="upper left", handlelength=1.1, handleheight=0.9)
    ptitle(ax, "A", "ICU and in-hospital mortality", x=-0.13)

    # --- (B) trajectory -----------------------------------------------------
    ax = axes[1]
    tp = ["In-hospital", "30-day", "90-day", "1-year /\nall-cause"]
    series = [("Zigong (ZFPH)", RED, "o"), ("INSPIRE", BLUE, "s"), ("MIMIC-IV", AMBER, "^")]
    xs = np.arange(4)
    for name, colour, marker in series:
        m = D.MORTALITY[name]
        ys = [m["hosp"], m["d30"], m["d90"], m["y1"]]
        ax.plot(xs, ys, color=colour, linewidth=1.8, marker=marker, markersize=5.2,
                markeredgecolor="white", markeredgewidth=0.9, zorder=3, label=name)
        for xi, yv in zip(xs, ys):
            off = 2.0 if name != "MIMIC-IV" else -3.4
            ax.text(xi, yv + off, f"{yv:.1f}", ha="center",
                    va="bottom" if off > 0 else "top", fontsize=7.4, color=colour)
    ax.set_xticks(xs); ax.set_xticklabels(tp)
    ax.set_ylabel("Cumulative mortality (%)")
    ax.set_ylim(-3, 56)
    ax.set_xlim(-0.28, 3.28)
    ax.yaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    ax.set_axisbelow(True)
    ax.legend(loc="upper left", handlelength=1.6)
    ptitle(ax, "B", "Mortality trajectory", x=-0.16)

    footnote(fig,
             "NR, not reported. * Death at last follow-up (6,241/20,109), mixing in-hospital and post-discharge death; not comparable with the "
             "in-hospital values shown.\n† A longer-term, not an in-hospital, endpoint. INSPIRE's final timepoint is cumulative all-cause mortality "
             "over variable follow-up (2011–2020), not a fixed one-year\nlandmark. NWICU's in-hospital value is the patient-level estimate "
             "(3,554/25,923); the admission-level estimate is 5.8% (3,558/61,843). See Table 3.",
             y=-0.26)
    save(fig, "Figure_4")


# ============================================================ FIGURE 7 ======
def figure7():
    fig, ax = plt.subplots(figsize=(7.2, 3.9))
    order = ["AmsterdamUMCdb", "HiRID", "Zigong (ZFPH)", "MIMIC-IV", "SICdb", "NWICU", "eICU-CRD"]
    labels = ["Mechanical ventilation", "Vasopressors or inotropes", "Renal replacement therapy"]
    colours = [BLUE, AMBER, GREEN]
    x = np.arange(len(order)); w = 0.26
    for k in range(3):
        for xi, name in zip(x, order):
            v = D.ORGAN_SUPPORT[name][k]
            pos = xi + (k - 1) * w
            if v is None:
                ax.text(pos, 1.1, "NR", ha="center", va="bottom", fontsize=6.8,
                        color="#9AA1A9", style="italic", rotation=90)
            else:
                ax.bar(pos, v, width=w * 0.90, color=colours[k], zorder=3)
                ax.text(pos, v + 1.1, f"{v:g}", ha="center", va="bottom",
                        fontsize=7.4, color=INK)
    ax.set_xticks(x); ax.set_xticklabels(order)
    ax.set_ylabel("Proportion of cohort receiving support (%)")
    ax.set_ylim(0, 82)
    ax.yaxis.grid(True, color=HAIR, linewidth=0.5, zorder=0)
    ax.set_axisbelow(True)
    handles = [Rectangle((0, 0), 1, 1, facecolor=c, edgecolor="none") for c in colours]
    ax.legend(handles, labels, loc="upper right", ncol=1, handlelength=1.1, handleheight=0.9)
    footnote(fig,
             "NR, not reported. All seven resources shown are intensive-care databases; MIMIC-IV is a mixed hospital-and-ICU resource "
             "whose values reflect its ICU-admitted subset.\nNo perioperative resource (INSPIRE, MOVER, VitalDB) and no pediatric resource "
             "(PIC) reports organ-support utilization. Databases are ordered by ventilation rate.",
             y=-0.16)
    save(fig, "Figure_5")


if __name__ == "__main__":
    print("Generating figures ...")
    figure2(); figure3(); figure5(); figure6(); figure7(); figure4()
    print("Done ->", OUT)
