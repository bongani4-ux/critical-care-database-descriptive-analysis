"""Study-identification flow diagram (Figure S1).

PRISMA-ScR flow for the executed search. Every count is imported from
search/flow_data.py; nothing here is typed by hand.

Layout notes: two columns on one grid — the main flow on the left, the
records and resources removed at each stage on the right. Every box uses the
same internal grammar (label left, count right on the same baseline), so the
eye reads down one column and across one row without re-learning the layout.
Monochrome navy and slate: legible in greyscale, safe for any color vision.
"""
import os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from matplotlib.lines import Line2D

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "search"))
import dbdata as D
import flow_data as F

D.apply_style()
OUT = os.path.join(HERE, "figures")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ palette --
NAVY   = "#1F3B63"   # main flow: rules, headings, arrows
INK    = "#1A1A1A"   # body text
SLATE  = "#616E7C"   # removal column
SIDEBG = "#F3F5F7"   # removal column fill
INCBG  = "#DCE6F2"   # the one emphasized outcome
HAIR   = "#B9C2CC"

# ------------------------------------------------------------------- canvas --
X_HI = 100.0
Y_LO, Y_HI = 16.5, 99.0
UNIT = 0.075                       # inches per unit, identical on both axes
FIG_W = X_HI * UNIT
FIG_H = (Y_HI - Y_LO) * UNIT

fig = plt.figure(figsize=(FIG_W, FIG_H))
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, X_HI); ax.set_ylim(Y_LO, Y_HI)
ax.axis("off")

RAIL_X0, RAIL_X1 = 1.6, 7.4        # stage rail
MAIN_X0, MAIN_X1 = 10.5, 58.0      # flow column
SIDE_X0, SIDE_X1 = 61.5, 99.0      # removal column
PAD = 2.1                          # internal padding
PITCH = 2.5                        # baseline pitch


def box(x0, y1, x1, y0, *, fill="white", edge=NAVY, lw=0.85, ls="solid", r=0.8):
    ax.add_patch(FancyBboxPatch(
        (x0, y0), x1 - x0, y1 - y0,
        boxstyle=f"round,pad=0,rounding_size={r}",
        facecolor=fill, edgecolor=edge, linewidth=lw, linestyle=ls,
        mutation_aspect=1.0, zorder=2))


def txt(x, y, s, *, size=7.4, color=INK, ha="left", b=False, i=False):
    ax.text(x, y, s, ha=ha, va="center", fontsize=size, color=color,
            fontweight="bold" if b else "normal",
            style="italic" if i else "normal", zorder=3)


def row(x0, x1, y, label, value, *, size=7.4, color=INK, b=False, vcolor=None):
    """Label flush left, value flush right, one shared baseline."""
    txt(x0, y, label, size=size, color=color, b=b)
    if value is not None:
        txt(x1, y, value, size=size, color=vcolor or color, b=b, ha="right")


def down(x, y_top, y_bot, head=True):
    ax.annotate("", xy=(x, y_bot), xytext=(x, y_top),
                arrowprops=dict(arrowstyle="-|>" if head else "-", color=NAVY,
                                linewidth=0.85, shrinkA=0, shrinkB=0,
                                mutation_scale=8), zorder=1)


def across(x_from, x_to, y):
    ax.annotate("", xy=(x_to, y), xytext=(x_from, y),
                arrowprops=dict(arrowstyle="-|>", color=SLATE, linewidth=0.85,
                                shrinkA=0, shrinkB=0, mutation_scale=8), zorder=1)


def rail(label, y1, y0):
    ax.add_patch(FancyBboxPatch(
        (RAIL_X0, y0), RAIL_X1 - RAIL_X0, y1 - y0,
        boxstyle="round,pad=0,rounding_size=0.8",
        facecolor=NAVY, edgecolor="none", mutation_aspect=1.0, zorder=2))
    ax.text((RAIL_X0 + RAIL_X1) / 2, (y0 + y1) / 2, label.upper(), rotation=90,
            ha="center", va="center", fontsize=7.0, fontweight="bold",
            color="white", zorder=3)


def n(v):
    return f"{v:,}"


L, R = MAIN_X0 + PAD, MAIN_X1 - PAD          # main column text margins
SL, SR = SIDE_X0 + PAD, SIDE_X1 - PAD        # side column text margins
MID = (MAIN_X0 + MAIN_X1) / 2

# ============================================================ IDENTIFICATION ==
SOURCES = [
    ("PhysioNet repository, six topic filters", F.REPO_RAW),
    ("PubMed, six title-phrase lines", F.PUBMED_RAW),
    ("Web of Science Core Collection", F.WOS_RAW),
    ("Europe PMC preprint index, three queries", F.EPMC_RAW),
    ("arXiv, two queries", F.ARXIV_RAW),
    ("Prior reviews and citation chasing", F.OTHER_RAW),
]

ID_Y1 = 97.0
ID_H = PAD + PITCH + 0.9 + len(SOURCES) * PITCH + PITCH - 0.5 + PAD
ID_Y0 = ID_Y1 - ID_H
box(MAIN_X0, ID_Y1, MAIN_X1, ID_Y0)

y = ID_Y1 - PAD - PITCH / 2
row(L, R, y, "Records identified from:", None, size=8.2, color=NAVY, b=True)
y -= PITCH + 0.9
for label, v in SOURCES:
    row(L + 1.4, R, y, label, n(v))
    y -= PITCH
rule_y = y + PITCH / 2 + 0.15
ax.add_line(Line2D([L + 1.4, R], [rule_y, rule_y], color=HAIR, linewidth=0.7, zorder=3))
row(L + 1.4, R, y - 0.6, "Total records identified", "n = " + n(F.IDENTIFIED), b=True, color=NAVY)

# duplicates removed --------------------------------------------------------
DUP_H = PAD + PITCH + 1.0 + 2 * 2.3 + PAD
DUP_Y1 = ID_Y1 - 5.5
DUP_Y0 = DUP_Y1 - DUP_H
box(SIDE_X0, DUP_Y1, SIDE_X1, DUP_Y0, fill=SIDEBG, edge=SLATE, lw=0.75)
yy = DUP_Y1 - PAD - PITCH / 2
row(SL, SR, yy, "Duplicate records removed", "n = " + n(F.DUPES),
    size=7.8, color=SLATE, b=True)
yy -= PITCH + 1.0
row(SL, SR, yy, "Across repository topic filters", n(F.REPO_DUPES), size=7.1, color=SLATE)
yy -= 2.3
row(SL, SR, yy, "Across preprint-index queries", n(F.EPMC_DUPES), size=7.1, color=SLATE)
across(MAIN_X1, SIDE_X0, (DUP_Y1 + DUP_Y0) / 2)

RAIL_ZONES = []  # filled as the flow is laid out

# ================================================================= SCREENING ==
GAP = 5.4
SC_Y1 = ID_Y0 - GAP
SC_H = PAD + PITCH + PAD
SC_Y0 = SC_Y1 - SC_H
down(MID, ID_Y0, SC_Y1)
box(MAIN_X0, SC_Y1, MAIN_X1, SC_Y0)
row(L, R, (SC_Y1 + SC_Y0) / 2, "Records screened on title and abstract",
    "n = " + n(F.SCREENED), size=8.2, color=NAVY, b=True)

EX_H = PAD + PITCH + 1.0 + 2.3 + PAD
EX_Y1 = SC_Y1 + (EX_H - SC_H) / 2
EX_Y0 = EX_Y1 - EX_H
box(SIDE_X0, EX_Y1, SIDE_X1, EX_Y0, fill=SIDEBG, edge=SLATE, lw=0.75)
yy = EX_Y1 - PAD - PITCH / 2
row(SL, SR, yy, "Records excluded", "n = " + n(F.SCREEN_EXCLUDED),
    size=7.8, color=SLATE, b=True)
yy -= PITCH + 1.0
txt(SL, yy, "No named data resource described", size=7.1, color=SLATE)
across(MAIN_X1, SIDE_X0, (SC_Y1 + SC_Y0) / 2)



# =============================================================== ELIGIBILITY ==
EL_Y1 = SC_Y0 - GAP
EL_H = PAD + PITCH + PAD
EL_Y0 = EL_Y1 - EL_H
down(MID, SC_Y0, EL_Y1)
box(MAIN_X0, EL_Y1, MAIN_X1, EL_Y0)
row(L, R, (EL_Y1 + EL_Y0) / 2, "Resources assessed at full-record level",
    "n = " + n(F.ASSESSED), size=8.2, color=NAVY, b=True)

RS_H = PAD + PITCH + 1.4 + len(F.ORDER) * 2.45 + PAD
RS_Y1 = EX_Y0 - 3.4
RS_Y0 = RS_Y1 - RS_H
box(SIDE_X0, RS_Y1, SIDE_X1, RS_Y0, fill=SIDEBG, edge=SLATE, lw=0.75)
yy = RS_Y1 - PAD - PITCH / 2
row(SL, SR, yy, "Resources excluded, with reasons", "n = " + n(F.EXCLUDED),
    size=7.8, color=SLATE, b=True)
yy -= PITCH + 1.4
for code in F.ORDER:
    row(SL, SR, yy, F.REASON_LABEL[code], n(F.REASONS[code]), size=7.1, color=SLATE)
    yy -= 2.45
across(MAIN_X1, SIDE_X0, (EL_Y1 + EL_Y0) / 2)



# ================================================================== INCLUDED ==
JUNC = EL_Y0 - 3.0
OUT_Y1 = JUNC - 2.4
OUT_H = PAD + PITCH + PITCH + 3.2 + 2.4 + PAD
OUT_Y0 = OUT_Y1 - OUT_H

INC_X0, INC_X1 = MAIN_X0, 33.0
NC_X0, NC_X1 = 35.5, MAIN_X1
inc_mid = (INC_X0 + INC_X1) / 2
nc_mid = (NC_X0 + NC_X1) / 2

down(MID, EL_Y0, JUNC, head=False)
ax.add_line(Line2D([inc_mid, nc_mid], [JUNC, JUNC], color=NAVY, linewidth=0.85, zorder=1))
down(inc_mid, JUNC, OUT_Y1)
down(nc_mid, JUNC, OUT_Y1)


def outcome(x0, x1, line1, line2, value, caption=None, **kw):
    box(x0, OUT_Y1, x1, OUT_Y0, **kw)
    yy = OUT_Y1 - PAD - PITCH / 2
    txt(x0 + PAD, yy, line1, size=8.2, color=NAVY, b=True)
    txt(x0 + PAD, yy - PITCH, line2, size=8.2, color=NAVY, b=True)
    txt(x0 + PAD, yy - PITCH - 3.2, value, size=11.5, color=NAVY, b=True)
    if caption:
        txt(x0 + PAD, yy - PITCH - 3.2 - 2.6, caption, size=6.5, color=SLATE, i=True)


outcome(INC_X0, INC_X1, "Resources included", "and charted", f"n = {F.INCLUDED}",
        caption="Tables 1\u20134; Figures 1\u20135", fill=INCBG, lw=1.25)
outcome(NC_X0, NC_X1, "Meeting the criteria", "but not charted", f"n = {F.N_NOT_CHARTED}",
        caption="Additional file 3, Table S1", ls=(0, (2.6, 2.0)), lw=0.85)

# ---------------------------------------------------------- stage rails --
# One contiguous column down the left, hairline-separated, so each stage is
# named without stealing width from the flow.
SPLIT1 = (ID_Y0 + SC_Y1) / 2
SPLIT2 = (SC_Y0 + EL_Y1) / 2
SPLIT3 = (EL_Y0 + OUT_Y1) / 2
G = 0.8
rail("Identification", ID_Y1, SPLIT1 + G / 2)
rail("Screening", SPLIT1 - G / 2, SPLIT2 + G / 2)
rail("Eligibility", SPLIT2 - G / 2, SPLIT3 + G / 2)
rail("Included", SPLIT3 - G / 2, OUT_Y0)

# The explanatory text that used to sit inside the artwork now lives in the
# Figure S1 legend in Supplemental file 2, so the figure carries no caption.

for ext, kw in (("png", dict(dpi=600)),
                ("tiff", dict(dpi=600, pil_kwargs={"compression": "tiff_lzw"})),
                ("pdf", {})):
    fig.savefig(os.path.join(OUT, f"FigureS1_flow.{ext}"), facecolor="white", **kw)
plt.close(fig)
print(f"wrote FigureS1_flow  ({FIG_W:.2f} x {FIG_H:.2f} in)")
print(f"identified {F.IDENTIFIED}  screened {F.SCREENED}  assessed {F.ASSESSED}  "
      f"included {F.INCLUDED}  not charted {F.N_NOT_CHARTED}  excluded {F.EXCLUDED}")
