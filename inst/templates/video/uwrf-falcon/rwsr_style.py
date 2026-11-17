"""Shared look and reusable pieces for the series' Manim scenes.

Import from a scene file in videos/NN-slug/scenes/:

    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_shared"))
    from rwsr_style import *

lecturecast caches a rendered scene by its own file and the files named in
inputs=. A change to THIS module is not noticed, so list it in the slide:
    inputs="../../_shared/rwsr_style.py"

Palette and colour meanings come from the book's chapter banners
(chapter_visuals/banner_lib.py), so the videos look like the book:
    TEAL  the working thing, the true value, the thing that answers
    RUST  the misconception, the biased estimate, the rejected path
    OLIVE secondary marks, gridlines, notes
"""

import numpy as np
from manim import *

# ---- THEME MOCK-UP SWITCH (scratch copy only) ---------------------------------
import os
# Roles: PAPER background, INK text, OLIVE secondary/notes, TEAL median/primary,
# RUST mean/accent, THIRD mode. HEAD heading font, HSTYLE heading treatment.
THEMES = {
    "paper":     dict(PAPER="#F3E9D2", INK="#252A29", OLIVE="#687067", TEAL="#1E6F6D", RUST="#C65D3B",
                      THIRD="#687067", SANS="Avenir Next", HEAD="Avenir Next", HSTYLE="plain"),
    "editorial": dict(PAPER="#FBFAF6", INK="#141414", OLIVE="#6E6E6E", TEAL="#1F4E79", RUST="#D6402B",
                      THIRD="#C98F00", SANS="Avenir Next", HEAD="Charter", HSTYLE="rule"),
    "blueprint": dict(PAPER="#0E2A47", INK="#EAF2FA", OLIVE="#8FA9C4", TEAL="#5CC8F0", RUST="#FFB547",
                      THIRD="#F28DB2", SANS="DIN Alternate", HEAD="DIN Condensed", HSTYLE="caps", GRID=True),
    "midnight":  dict(PAPER="#17161C", INK="#F4EFE6", OLIVE="#9A948A", TEAL="#4FD1A5", RUST="#FF7A59",
                      THIRD="#F2C14E", SANS="Avenir Next", HEAD="Avenir Next", HSTYLE="plain"),
    "chalk":     dict(PAPER="#26362F", INK="#F1EFE6", OLIVE="#AEBBAE", TEAL="#8CC9E8", RUST="#F4A6A6",
                      THIRD="#F3E28B", SANS="Avenir Next", HEAD="Chalkboard SE", HSTYLE="plain"),
    # UWRF riff: colours sampled from the UWRF RSO Brand Standards Guide (2024)
    # red #D31144, dark red #8F181A, sky blue #41C7F4; condensed caps headings
    # stand in for the brand's condensed display face. No marks or wordmarks.
    "falcon":    dict(PAPER="#141414", INK="#FFFFFF", OLIVE="#A9A9A9", TEAL="#41C7F4", RUST="#E8325F",
                      THIRD="#F5F5F5", SANS="Avenir Next", HEAD="DIN Condensed", HSTYLE="band",
                      BAND="#D31144"),
    "falcon_light": dict(PAPER="#FFFFFF", INK="#141414", OLIVE="#6B6B6B", TEAL="#1593C4", RUST="#D31144",
                      THIRD="#8F181A", SANS="Avenir Next", HEAD="DIN Condensed", HSTYLE="band",
                      BAND="#D31144"),
}
THEME_NAME = os.environ.get("RWSR_THEME", "paper")
T = THEMES[THEME_NAME]
PAPER, INK, OLIVE, TEAL, RUST, THIRD = T["PAPER"], T["INK"], T["OLIVE"], T["TEAL"], T["RUST"], T["THIRD"]
# Light tints for fills and bands, mixed toward PAPER.
TEAL_LIGHT = ManimColor(TEAL).interpolate(ManimColor(PAPER), 0.65)
RUST_LIGHT = ManimColor(RUST).interpolate(ManimColor(PAPER), 0.65)
OLIVE_LIGHT = ManimColor(OLIVE).interpolate(ManimColor(PAPER), 0.6)

SANS = T["SANS"]
HEAD = T["HEAD"]
MONO = "Courier"

config.background_color = PAPER

if T.get("GRID"):
    _orig_setup = Scene.setup

    def _grid_setup(self):
        _orig_setup(self)
        g = VGroup()
        for x in np.arange(-7.5, 7.6, 0.5):
            g.add(Line([x, -4.5, 0], [x, 4.5, 0], stroke_width=2.2 if x % 2 == 0 else 0.8,
                       color=INK, stroke_opacity=0.10 if x % 2 == 0 else 0.06))
        for y in np.arange(-4.5, 4.6, 0.5):
            g.add(Line([-8, y, 0], [8, y, 0], stroke_width=2.2 if y % 2 == 0 else 0.8,
                       color=INK, stroke_opacity=0.10 if y % 2 == 0 else 0.06))
        self.add(g)

    Scene.setup = _grid_setup

# Every MathTex in INK unless told otherwise.
MathTex.set_default(color=INK)
Tex.set_default(color=INK)


# ---- text ---------------------------------------------------------------------
def txt(s, size=32, color=INK, weight=NORMAL, **kw):
    return Text(s, font=SANS, font_size=size, color=color, weight=weight, **kw)


def heading(s, size=44):
    """Chapter-style heading at the top of the frame."""
    hs = T["HSTYLE"]
    if hs == "plain":
        return Text(s, font=HEAD, font_size=size, color=INK, weight=BOLD).to_edge(UP, buff=0.45)
    if hs == "rule":
        t = Text(s, font=HEAD, font_size=size, color=INK, weight=BOLD).to_edge(UP, buff=0.4)
        r = Line(LEFT, RIGHT, color=RUST, stroke_width=5).set_width(1.2)
        r.next_to(t, DOWN, buff=0.12).align_to(t, LEFT)
        return VGroup(t, r)
    if hs == "caps":
        return Text(s.upper(), font=HEAD, font_size=size * 1.15, color=INK).to_edge(UP, buff=0.4)
    # band: white condensed caps on a red slab across the top-left, slanted end
    t = Text(s.upper(), font=HEAD, font_size=size * 1.15, color="#FFFFFF")
    h = t.height + 0.42
    w = t.width + 1.6
    x0, y1 = -config.frame_x_radius, config.frame_y_radius - 0.25
    slab = Polygon([x0, y1, 0], [x0 + w + 0.5, y1, 0], [x0 + w, y1 - h, 0], [x0, y1 - h, 0],
                   stroke_width=0, fill_color=T["BAND"], fill_opacity=1)
    stripe = Polygon([x0 + w + 0.62, y1, 0], [x0 + w + 0.80, y1, 0], [x0 + w + 0.30, y1 - h, 0],
                     [x0 + w + 0.12, y1 - h, 0], stroke_width=0, fill_color="#41C7F4", fill_opacity=1)
    t.move_to(slab).align_to(slab, LEFT).shift(RIGHT * 0.6)
    # Invisible mirror point so the group is centred on x = 0, like the other
    # heading styles; scenes place content with next_to(title, DOWN).
    mirror = Dot([-x0, slab.get_center()[1], 0], radius=0.001, fill_opacity=0, stroke_opacity=0)
    return VGroup(slab, stripe, t, mirror)


def caption(s, size=24):
    """Small note or source line at the bottom."""
    return txt(s, size=size, color=OLIVE).to_edge(DOWN, buff=0.3)


def callout(s, target, direction=UP, color=INK, size=28, buff=0.25):
    """Label placed next to a mobject."""
    return txt(s, size=size, color=color).next_to(target, direction, buff=buff)


# ---- axes and plots -----------------------------------------------------------
def axes(x_range=(0, 10, 2), y_range=(0, 10, 2), x_length=10, y_length=5.5,
         xlab=None, ylab=None, numbers=False):
    """Plain axes in INK. Returns (axes, labels VGroup).
    Labels are placed where the axes are now, so position the two together:
        ax, labels = axes(...); VGroup(ax, labels).to_edge(LEFT)"""
    ax = Axes(x_range=list(x_range), y_range=list(y_range),
              x_length=x_length, y_length=y_length, tips=False,
              axis_config={"color": INK, "stroke_width": 2,
                           "include_ticks": numbers, "include_numbers": numbers,
                           "decimal_number_config": {"color": INK, "num_decimal_places": 0}})
    labels = VGroup()
    if xlab:
        labels.add(txt(xlab, 26, OLIVE).next_to(ax.x_axis, DOWN, buff=0.25))
    if ylab:
        labels.add(txt(ylab, 26, OLIVE).next_to(ax.y_axis, UP, buff=0.2))
    return ax, labels


def dots(ax, x, y, color=INK, radius=0.06, opacity=0.85):
    """Scatter of points (numpy arrays or lists) on an axes."""
    return VGroup(*[Dot(ax.c2p(a, b), radius=radius, color=color, fill_opacity=opacity)
                    for a, b in zip(x, y)])


def fit_line(ax, intercept, slope, x_min=None, x_max=None, color=TEAL, width=5):
    """Straight line y = intercept + slope * x across the axes."""
    lo = ax.x_range[0] if x_min is None else x_min
    hi = ax.x_range[1] if x_max is None else x_max
    return ax.plot(lambda x: intercept + slope * x, x_range=[lo, hi], color=color, stroke_width=width)


def ols(x, y):
    """Least-squares intercept and slope (for scenes that refit live)."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    b = np.cov(x, y, bias=True)[0, 1] / np.var(x)
    return y.mean() - b * x.mean(), b


def residuals(ax, x, y, intercept, slope, color=RUST, width=2.5):
    """Vertical segments from each point to the line."""
    return VGroup(*[Line(ax.c2p(a, b), ax.c2p(a, intercept + slope * a), color=color, stroke_width=width)
                    for a, b in zip(x, y)])


def squares(ax, x, y, intercept, slope, color=RUST, opacity=0.25):
    """Squared residuals drawn as squares (for least-squares scenes).
    Side length is the residual in y units, drawn to the right of the point."""
    out = VGroup()
    for a, b in zip(x, y):
        r = b - (intercept + slope * a)
        p0 = ax.c2p(a, b)
        p1 = ax.c2p(a, intercept + slope * a)
        side = abs(p1[1] - p0[1])
        sq = Square(side_length=max(side, 1e-3), stroke_width=1, stroke_color=color,
                    fill_color=color, fill_opacity=opacity)
        sq.move_to(np.array([p0[0] + side / 2, (p0[1] + p1[1]) / 2, 0]))
        out.add(sq)
    return out


# ---- distributions and sampling -----------------------------------------------
def histogram(ax, values, bins, color=TEAL, opacity=0.75, scale=1.0):
    """Bars on an existing axes. `bins` are edges; heights are counts * scale."""
    counts, edges = np.histogram(values, bins=bins)
    bars = VGroup()
    for c, lo, hi in zip(counts, edges[:-1], edges[1:]):
        if c == 0:
            continue
        bl, tr = ax.c2p(lo, 0), ax.c2p(hi, c * scale)
        bars.add(Rectangle(width=tr[0] - bl[0], height=tr[1] - bl[1], stroke_color=PAPER,
                           stroke_width=1, fill_color=color, fill_opacity=opacity)
                 .move_to((np.array(bl) + np.array(tr)) / 2))
    return bars


def density_curve(ax, f, x_min, x_max, color=INK, width=4):
    """Smooth curve y = f(x), e.g. a normal density scaled to the histogram."""
    return ax.plot(f, x_range=[x_min, x_max], color=color, stroke_width=width)


def marker(ax, x, label=None, color=TEAL, height=None, size=26):
    """Vertical line at x (a mean, a median, a true value), with optional label."""
    top = ax.y_range[1] if height is None else height
    ln = DashedLine(ax.c2p(x, 0), ax.c2p(x, top), color=color, stroke_width=3)
    if label is None:
        return ln
    return VGroup(ln, txt(label, size, color).next_to(ln, UP, buff=0.15))


# ---- title and end cards --------------------------------------------------------
# Series name, decided by Logan 2026-11-12.
SERIES_NAME = "Statistics in Motion"
# Byline: name only, no book title (Logan, 2026-11-12, whole series).
BOOK_LINE = "Logan Kelly, Ph.D."


class TitleCard(Scene):
    """Animated opening card. In a video's scenes/cards.py:

        class Title(TitleCard):
            title = "What Does “Typical” Mean?"

    Scattered points drift into a teal line under the title: the series motif.
    Sections: "title" (whole build). The finished frame is the thumbnail.
    """
    title = "VIDEO TITLE"
    series = None
    byline = BOOK_LINE
    seed = 730

    def construct(self):
        self.next_section("title")
        rng = np.random.default_rng(self.seed)
        t = (Text(self.title.upper(), font=HEAD, font_size=74, color=INK) if T["HSTYLE"] in ("caps", "band")
             else Text(self.title, font=HEAD, font_size=64, color=INK, weight=BOLD))
        if t.width > 12:
            t.scale_to_fit_width(12)
        s = txt(self.series or SERIES_NAME, size=34, color=TEAL, weight=BOLD)
        b = txt(self.byline, size=26, color=OLIVE)
        VGroup(t, s, b).arrange(DOWN, buff=0.45).shift(UP * 0.6)

        # Motif: a line of best fit forming under the title.
        y0 = b.get_bottom()[1] - 1.1
        xs = np.linspace(-5, 5, 26)
        ys = y0 + 0.08 * xs + rng.normal(0, 0.35, xs.size)
        pts = VGroup(*[Dot([x, rng.uniform(-3.8, -2.2), 0], radius=0.06, color=OLIVE) for x in xs])
        targets = [np.array([x, y, 0]) for x, y in zip(xs, ys)]
        line = Line([-5.4, y0 - 0.43, 0], [5.4, y0 + 0.43, 0], color=TEAL, stroke_width=6)

        self.play(LaggedStart(*[FadeIn(p, scale=0.5) for p in pts], lag_ratio=0.03), run_time=0.8)
        self.play(*[p.animate.move_to(tg) for p, tg in zip(pts, targets)],
                  Write(t), run_time=1.6)
        self.play(Create(line), FadeIn(s, shift=UP * 0.2), run_time=0.9)
        self.play(FadeIn(b), run_time=0.5)
        self.wait(0.6)


class EndCard(Scene):
    """Animated closing card.

        class End(EndCard):
            pass                      # standalone: series name and byline

        class End(EndCard):
            next_title = "Skew"       # optional "Up next" line
            book_ref = "..."          # optional line under it

    Video 1 stands alone with no next-video or book reference (Logan,
    2026-11-12), so both are off by default.
    Sections: "end" (whole build).
    """
    next_title = None
    book_ref = None
    series = None
    byline = BOOK_LINE

    def construct(self):
        self.next_section("end")
        sr = txt(self.series or SERIES_NAME, size=56, color=TEAL, weight=BOLD)
        bar = Line(LEFT * 1.6, RIGHT * 1.6, color=TEAL, stroke_width=8)
        by = txt(self.byline, size=30, color=OLIVE)
        parts = []
        if self.next_title:
            parts += [txt("Up next", size=34, color=OLIVE), txt(self.next_title, size=48, color=INK, weight=BOLD)]
            if self.book_ref:
                parts.append(txt(self.book_ref, size=26, color=OLIVE))
        g = VGroup(sr, bar, by, *parts).arrange(DOWN, buff=0.4)
        if sr.width > 12:
            sr.scale_to_fit_width(12)
        self.play(Write(sr), run_time=1.0)
        self.play(Create(bar), run_time=0.5)
        self.play(FadeIn(by), *[FadeIn(p) for p in parts], run_time=0.6)
        self.wait(1.2)


class Stacker:
    """Drops values one at a time into a dot plot that piles up by bin.
    The sampling-many-times animation used by the CLT, sampling-distribution
    and bias-versus-precision videos.

        st = Stacker(ax, bin_width=0.25, dot_radius=0.05)
        self.play(st.drop(value))            # one at a time, early on
        self.play(*st.drop_many(values))     # then in bulk
    """

    def __init__(self, ax, bin_width, dot_radius=0.05, color=TEAL):
        self.ax, self.w, self.r, self.color = ax, bin_width, dot_radius, color
        self.heights = {}
        self.group = VGroup()

    def _target(self, value):
        k = int(np.floor(value / self.w))
        n = self.heights.get(k, 0)
        self.heights[k] = n + 1
        x = (k + 0.5) * self.w
        base = self.ax.c2p(x, 0)
        return np.array([base[0], base[1] + self.r * (2 * n + 1), 0])

    def drop(self, value, start=None, run_time=0.4):
        d = Dot(radius=self.r, color=self.color)
        target = self._target(value)
        d.move_to(start if start is not None else target + UP * 3)
        self.group.add(d)
        return d.animate(run_time=run_time).move_to(target)

    def drop_many(self, values, run_time=1.0):
        anims = []
        for v in values:
            d = Dot(radius=self.r, color=self.color).move_to(self._target(v))
            self.group.add(d)
            anims.append(FadeIn(d, run_time=run_time))
        return anims
