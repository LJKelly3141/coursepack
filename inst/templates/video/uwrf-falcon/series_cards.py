"""Mock-up: a series intro sting and outro, the same in every video.

Intro (~6 s): data rain down and pile into a skewed distribution, three
markers rise (mode, median, mean), the series name lands.
Outro (~6 s): the pile settles under the series name, byline, thanks.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rwsr_style import *  # noqa: E402,F403

SERIES = "Statistics in Motion"
BYLINE = "Logan Kelly, Ph.D."


def _name(size=72):
    if T["HSTYLE"] in ("caps", "band"):
        return Text(SERIES.upper(), font=HEAD, font_size=size * 1.2, color=INK)
    return Text(SERIES, font=HEAD, font_size=size, color=INK, weight=BOLD)


def _pile(n=230, seed=730, base_y=-1.6, w=0.16, r=0.05):
    rng = np.random.default_rng(seed)
    v = np.clip(rng.lognormal(1.0, 0.55, n), 0.3, 11.5)
    bins = np.floor(v / 0.25).astype(int)
    h = {}
    dots, starts = VGroup(), []
    x0 = -5.6
    for b, val in sorted(zip(bins, v), key=lambda t: t[1]):
        k = h.get(b, 0)
        h[b] = k + 1
        p = np.array([x0 + b * 0.24, base_y + r + 2 * r * k, 0])
        dots.add(Dot(p, radius=r, color=OLIVE))
        starts.append(p + UP * (4.5 + rng.uniform(0, 1.5)))
    return v, dots, starts


class SeriesIntro(Scene):
    def construct(self):
        base_y = -1.6
        v, dots, starts = _pile(base_y=base_y)
        line = Line([-6, base_y, 0], [6, base_y, 0], color=INK, stroke_width=3)
        targets = [d.get_center() for d in dots]
        for d, s in zip(dots, starts):
            d.move_to(s)
        self.play(Create(line), run_time=0.5)
        self.play(LaggedStart(*[d.animate.move_to(t) for d, t in zip(dots, targets)], lag_ratio=0.008),
                  run_time=1.8, rate_func=rush_into)

        xs = sorted(d.get_center()[0] for d in dots)
        mode_x = max(set(round(x, 3) for x in xs), key=lambda q: sum(abs(x - q) < 1e-3 for x in xs))
        med_x = xs[len(xs) // 2]
        mean_x = float(np.mean(xs))
        flags = VGroup()
        for x, col, hgt in ((mode_x, THIRD, 2.2), (med_x, TEAL, 2.6), (mean_x, RUST, 3.0)):
            st = Line([x, base_y, 0], [x, base_y + hgt, 0], color=col, stroke_width=6)
            hd = Dot([x, base_y + hgt, 0], radius=0.11, color=col)
            flags.add(VGroup(st, hd))
        self.play(LaggedStart(*[GrowFromEdge(f, DOWN) for f in flags], lag_ratio=0.35), run_time=1.2)
        name = _name().move_to(UP * 2.5)
        if name.width > 12.5:
            name.scale_to_fit_width(12.5)
        if T["HSTYLE"] == "band":
            slab = Rectangle(width=name.width + 1.2, height=name.height + 0.5, stroke_width=0,
                             fill_color=T["BAND"], fill_opacity=1).move_to(name)
            name.set_color("#FFFFFF")
            self.play(GrowFromEdge(slab, LEFT), run_time=0.4)
        self.play(Write(name), run_time=1.0)
        by = Text(BYLINE, font=SANS, font_size=28, color=OLIVE).next_to(name, DOWN, buff=0.35)
        self.play(FadeIn(by), run_time=0.4)
        self.wait(0.8)


class SeriesOutro(Scene):
    def construct(self):
        base_y = -3.3
        v, dots, starts = _pile(base_y=base_y, seed=731, r=0.036)
        line = Line([-6, base_y, 0], [6, base_y, 0], color=INK, stroke_width=3)
        name = _name(64).move_to(UP * 2.5)
        if name.width > 12:
            name.scale_to_fit_width(12)
        parts = [name]
        if T["HSTYLE"] == "band":
            slab = Rectangle(width=name.width + 1.2, height=name.height + 0.5, stroke_width=0,
                             fill_color=T["BAND"], fill_opacity=1).move_to(name)
            name.set_color("#FFFFFF")
            parts = [slab, name]
        bar = Line(LEFT * 1.4, RIGHT * 1.4, color=TEAL, stroke_width=8).next_to(name, DOWN, buff=0.5)
        by = Text(BYLINE, font=SANS, font_size=30, color=OLIVE).next_to(bar, DOWN, buff=0.35)
        thanks = Text("Thanks for watching", font=SANS, font_size=34, color=INK).next_to(by, DOWN, buff=0.5)
        self.play(*[FadeIn(p) for p in parts], Create(line), run_time=0.8)
        self.play(Create(bar), FadeIn(by), run_time=0.6)
        self.play(FadeIn(dots, lag_ratio=0.01), run_time=1.2)
        self.play(FadeIn(thanks, shift=UP * 0.2), run_time=0.6)
        self.wait(2.0)
