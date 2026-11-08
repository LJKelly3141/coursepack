# Charts in a submitted workbook, described from the chart XML so a grader
# who cannot see the chart can still judge it: type, title, axes (scale,
# units, log, reversed), labels, legend, text boxes, categories in plotted
# order, and each series with its ranges and values. Any element of c:chart
# or c:plotArea (or of a plot group, series or axis) that is not interpreted
# is named "not described: <element>", so nothing is dropped silently.
# Names stay raw here: redaction runs later on the markdown this produces.
# Finding the charts and their positions is in anon-workbook-chart-find.R.

# ---- describing one chart --------------------------------------------------

indent <- function(pre, x) if (length(x)) paste0(pre, x) else character()
val_of <- function(node, xp) xml2::xml_attr(xml2::xml_find_first(node, xp, CHART_NS), "val")
on_flag <- function(node, xp) {
  v <- val_of(node, xp)
  !is.na(v) && v %in% c("1", "true")
}

rich_text <- function(node) {
  ps <- xml2::xml_find_all(node, ".//a:p", CHART_NS)
  t <- vapply(ps, function(p) paste(xml2::xml_text(xml2::xml_find_all(p, ".//a:t", CHART_NS)), collapse = ""), "")
  paste(t[nzchar(t)], collapse = " ")
}

# Values of a range like "'Pat Quill data'!$B$2:$B$5" (or several areas in
# parentheses) looked up in the tidyxl cells; NULL when it cannot be.
range_values <- function(f, cells) {
  areas <- strsplit(gsub("^\\(|\\)$", "", f), ",(?=(?:[^']*'[^']*')*[^']*$)", perl = TRUE)[[1]]
  vals <- character()
  for (a in areas) {
    m <- regmatches(a, regexec("^'?(.*?)'?!\\$?([A-Z]+)\\$?([0-9]+)(?::\\$?([A-Z]+)\\$?([0-9]+))?$", a))[[1]]
    if (!length(m) || is.null(cells)) return(NULL)
    sh <- gsub("''", "'", m[2])
    if (!sh %in% cells$sheet) return(NULL)
    cn <- function(l) sum((utf8ToInt(l) - 64) * 26^rev(seq_len(nchar(l)) - 1))
    c1 <- cn(m[3]); r1 <- as.numeric(m[4])
    c2 <- if (nzchar(m[5])) cn(m[5]) else c1; r2 <- if (nzchar(m[6])) as.numeric(m[6]) else r1
    g <- expand.grid(col = c1:c2, row = r1:r2)
    sc <- cells[cells$sheet == sh, ]
    vals <- c(vals, vapply(seq_len(nrow(g)), function(i) {
      k <- which(sc$row == g$row[i] & sc$col == g$col[i])
      if (!length(k)) return("")
      k <- k[1]
      if (!is.na(sc$numeric[k])) as.character(sc$numeric[k])
      else if (!is.na(sc$character[k])) sc$character[k]
      else if (!is.na(sc$logical[k])) as.character(sc$logical[k])
      else if (!is.na(sc$error[k])) sc$error[k] else ""
    }, ""))
  }
  if (!length(vals) || all(!nzchar(vals))) NULL else vals
}

# A data reference (c:tx, c:cat, c:val, c:xVal ...): its range, its values
# from the cache, else from cells, and the cache's number format.
ref_data <- function(node, cells) {
  if (inherits(node, "xml_missing")) return(NULL)
  lit <- xml2::xml_find_first(node, "c:v", CHART_NS)
  if (!inherits(lit, "xml_missing")) return(list(f = NA, v = xml2::xml_text(lit), src = "typed in"))
  f <- xml2::xml_text(xml2::xml_find_first(node, ".//c:f", CHART_NS))
  cache <- xml2::xml_find_first(node, ".//c:strCache | .//c:numCache | .//c:multiLvlStrCache/c:lvl | .//c:strLit | .//c:numLit", CHART_NS)
  fmt <- xml2::xml_text(xml2::xml_find_first(node, ".//c:numCache/c:formatCode | .//c:numLit/c:formatCode", CHART_NS))
  pts <- xml2::xml_find_all(cache, "c:pt", CHART_NS)
  # A cache with no points counts as no cache: fall back to the cells.
  if (!inherits(cache, "xml_missing") && length(pts)) {
    n <- as.numeric(val_of(cache, "c:ptCount"))
    idx <- as.numeric(xml2::xml_attr(pts, "idx"))
    if (is.na(n)) n <- if (length(idx)) max(idx) + 1 else 0
    v <- rep("", n)
    v[idx + 1] <- xml2::xml_text(xml2::xml_find_first(pts, "c:v", CHART_NS))
    return(list(f = f, v = v, src = if (is.na(f)) "typed in" else "", fmt = fmt))
  }
  v <- if (is.na(f)) NULL else range_values(f, cells)
  list(f = f, v = v, src = if (is.null(v)) "none" else "(from cells)", fmt = fmt)
}

show_values <- function(d) {
  if (is.null(d) || is.null(d$v)) return("values not available")
  s <- paste(d$v, collapse = ", ")
  if (identical(d$src, "(from cells)")) s <- paste(s, "(from cells)")
  if (!is.null(d$fmt) && !is.na(d$fmt) && d$fmt != "General") s <- paste0(s, " (format ", d$fmt, ")")
  s
}

title_of <- function(node, cells) {
  t <- xml2::xml_find_first(node, "c:title", CHART_NS)
  if (inherits(t, "xml_missing")) return(NA_character_)
  rich <- xml2::xml_find_first(t, "c:tx/c:rich", CHART_NS)
  if (!inherits(rich, "xml_missing")) return(rich_text(rich))
  d <- ref_data(xml2::xml_find_first(t, "c:tx/c:strRef", CHART_NS), cells)
  if (!is.null(d)) return(paste0(paste(d$v, collapse = " "), " (linked to ", d$f, ")"))
  "automatic"
}

DL_SHOW <- c(showVal = "value", showCatName = "category name", showSerName = "series name",
             showPercent = "percent", showBubbleSize = "bubble size", showLegendKey = "legend key")
DL_KNOWN <- c("delete", names(DL_SHOW), "numFmt", "spPr", "txPr", "dLblPos", "separator",
              "showLeaderLines", "leaderLines", "dLbl", "extLst")

# Data labels: first element is the on/off summary, the rest are detail
# lines (format, single-point labels, anything not described).
dlbls_text <- function(dl) {
  if (inherits(dl, "xml_missing")) return(NULL)
  if (on_flag(dl, "c:delete")) return("off")
  shown <- DL_SHOW[vapply(names(DL_SHOW), function(w) on_flag(dl, paste0("c:", w)), TRUE)]
  out <- if (!length(shown)) "off" else paste0("on, showing ", paste(shown, collapse = ", "))
  nf <- xml2::xml_attr(xml2::xml_find_first(dl, "c:numFmt", CHART_NS), "formatCode")
  if (!is.na(nf)) out <- c(out, paste0("- label number format: ", nf))
  for (p in xml2::xml_find_all(dl, "c:dLbl", CHART_NS)) {
    k <- as.numeric(val_of(p, "c:idx")) + 1
    rich <- xml2::xml_find_first(p, "c:tx/c:rich", CHART_NS)
    out <- c(out, if (on_flag(p, "c:delete")) sprintf("- label removed on point %d", k)
             else if (!inherits(rich, "xml_missing")) sprintf("- custom label on point %d: %s", k, rich_text(rich))
             else sprintf("- not described: dLbl (label settings for point %d)", k))
  }
  c(out, not_described(dl, DL_KNOWN))
}

# Extension elements that only carry ids or fill styling, safe to skip:
# c16:uniqueId is a series id; c14:invertSolidFillFmt is the fill used for
# negative bars.
EXT_COSMETIC <- c("http://schemas.microsoft.com/office/drawing/2014/chart uniqueId",
                  "http://schemas.microsoft.com/office/drawing/2007/8/2/chart invertSolidFillFmt")

# Children of node not in known, plus every element inside its extLst/ext
# (named with its prefix, e.g. c15:datalabelsRange) not on EXT_COSMETIC.
not_described <- function(node, known) {
  nm <- xml2::xml_name(xml2::xml_children(node))
  ext <- xml2::xml_find_all(node, "c:extLst/c:ext/*", CHART_NS)
  key <- paste(vapply(ext, function(e) xml2::xml_find_chr(e, "string(namespace-uri())"), ""),
               xml2::xml_name(ext))
  ext <- ext[!key %in% EXT_COSMETIC]
  qn <- vapply(ext, function(e) {
    pre <- regmatches(as.character(e), regexpr("^<[^ />]+", as.character(e)))
    sub("^<", "", pre)
  }, "")
  sprintf("- not described: %s", unique(c(nm[!nm %in% known], qn)))
}

GROUP_KNOWN <- c("barDir", "grouping", "varyColors", "ser", "axId", "dLbls", "gapWidth",
                 "overlap", "marker", "scatterStyle", "firstSliceAng", "holeSize", "smooth",
                 "serLines", "hiLowLines", "dropLines", "upDownBars", "shape", "gapDepth",
                 "bubbleScale", "showNegBubbles", "radarStyle", "ofPieType", "splitType",
                 "splitPos", "secondPieSize", "extLst")
SER_KNOWN <- c("idx", "order", "tx", "spPr", "cat", "val", "xVal", "yVal", "bubbleSize",
               "trendline", "errBars", "dLbls", "dPt", "marker", "invertIfNegative",
               "smooth", "explosion", "shape", "bubble3D", "pictureOptions", "extLst")
AX_KNOWN <- c("axId", "scaling", "delete", "axPos", "majorGridlines", "minorGridlines", "title",
              "numFmt", "majorTickMark", "minorTickMark", "tickLblPos", "spPr", "txPr",
              "crossAx", "crosses", "crossesAt", "crossBetween", "majorUnit", "minorUnit",
              "dispUnits", "auto", "lblAlgn", "lblOffset", "noMultiLvlLbl", "tickLblSkip",
              "tickMarkSkip", "baseTimeUnit", "majorTimeUnit", "minorTimeUnit", "extLst")
AX_KIND <- c(catAx = "category axis", valAx = "value axis", dateAx = "date axis", serAx = "series axis")

group_type <- function(g) {
  nm <- sub("Chart$", "", xml2::xml_name(g))
  if (grepl("^bar", nm)) {
    base <- if (identical(val_of(g, "c:barDir"), "bar")) "bar" else "column"
    if (grepl("3D", nm)) base <- paste("3-D", base)
  } else base <- sub("3D$", " 3-D", nm)
  extra <- c(val_of(g, "c:grouping"), val_of(g, "c:scatterStyle"))
  extra <- extra[!is.na(extra)]
  paste0(base, " chart", if (length(extra)) paste0(", ", paste(extra, collapse = ", ")))
}

series_lines <- function(s, k, cells, is_scatter) {
  nm <- ref_data(xml2::xml_find_first(s, "c:tx", CHART_NS), cells)
  name <- if (is.null(nm)) "no name" else if (is.null(nm$v)) "name not available" else
    paste0(paste(nm$v, collapse = " "), if (identical(nm$src, "(from cells)")) " (from cells)")
  out <- sprintf("- Series %d: %s%s", k, name,
                 if (!is.null(nm) && !is.na(nm$f)) paste0(" (", nm$f, ")") else "")
  parts <- if (is_scatter) c(xVal = "x", yVal = "y", bubbleSize = "bubble size") else
    c(cat = "category", val = "value")
  for (p in names(parts)) {
    d <- ref_data(xml2::xml_find_first(s, paste0("c:", p), CHART_NS), cells)
    if (is.null(d)) next
    out <- c(out, sprintf("  - %s range: %s", parts[[p]], if (is.na(d$f)) "typed in" else d$f))
    if (p %in% c("val", "yVal")) {
      out <- c(out, paste0("  - values: ", show_values(d)))
      num <- suppressWarnings(as.numeric(d$v))
      if (length(num) >= 2 && !anyNA(num) && length(unique(num)) == 1)
        out <- c(out, "  - constant: likely reference line")
    }
  }
  for (t in xml2::xml_find_all(s, "c:trendline", CHART_NS)) {
    tn <- xml2::xml_text(xml2::xml_find_first(t, "c:name", CHART_NS))
    out <- c(out, paste0("  - trendline: ", val_of(t, "c:trendlineType"),
                         if (!is.na(tn)) paste0(" named ", tn),
                         if (on_flag(t, "c:dispEq")) ", equation shown",
                         if (on_flag(t, "c:dispRSqr")) ", R squared shown"))
  }
  for (e in xml2::xml_find_all(s, "c:errBars", CHART_NS)) {
    out <- c(out, sprintf("  - error bars: %s direction, %s, %s %s", val_of(e, "c:errDir"),
                          val_of(e, "c:errBarType"), val_of(e, "c:errValType"),
                          if (is.na(val_of(e, "c:val"))) "" else val_of(e, "c:val")))
  }
  dl <- dlbls_text(xml2::xml_find_first(s, "c:dLbls", CHART_NS))
  if (!is.null(dl)) out <- c(out, paste0("  - data labels: ", dl[1]), indent("    ", dl[-1]))
  nd <- not_described(s, SER_KNOWN)
  c(out, indent("  ", nd))
}

axis_lines <- function(ax, primary_ids, cells) {
  id <- val_of(ax, "c:axId")
  pos <- c(b = "bottom", l = "left", r = "right", t = "top")[val_of(ax, "c:axPos")]
  out <- sprintf("- Axis: %s, %s, %s%s", AX_KIND[[xml2::xml_name(ax)]],
                 if (id %in% primary_ids) "primary" else "secondary",
                 if (is.na(pos)) "position not set" else pos,
                 if (on_flag(ax, "c:delete")) ", hidden" else "")
  tt <- title_of(ax, cells)
  out <- c(out, paste0("  - title: ", if (is.na(tt)) "none" else tt))
  auto <- function(v) if (is.na(v)) "automatic" else v
  out <- c(out, sprintf("  - scale: min %s, max %s, major unit %s, minor unit %s",
                        auto(val_of(ax, "c:scaling/c:min")), auto(val_of(ax, "c:scaling/c:max")),
                        auto(val_of(ax, "c:majorUnit")), auto(val_of(ax, "c:minorUnit"))))
  lb <- val_of(ax, "c:scaling/c:logBase")
  if (!is.na(lb)) out <- c(out, paste0("  - log scale, base ", lb))
  out <- c(out, paste0("  - orientation: ",
                       if (identical(val_of(ax, "c:scaling/c:orientation"), "maxMin")) "reversed" else "normal"))
  nf <- xml2::xml_find_first(ax, "c:numFmt", CHART_NS)
  if (!inherits(nf, "xml_missing"))
    out <- c(out, paste0("  - number format: ", xml2::xml_attr(nf, "formatCode"),
                         if (xml2::xml_attr(nf, "sourceLinked") %in% "1") " (linked to source)"))
  du <- xml2::xml_find_first(ax, "c:dispUnits", CHART_NS)
  if (!inherits(du, "xml_missing"))
    out <- c(out, paste0("  - display units: ", auto(val_of(du, "c:builtInUnit")),
                         if (!is.na(val_of(du, "c:custUnit"))) paste(" custom", val_of(du, "c:custUnit"))))
  ca <- val_of(ax, "c:crossesAt")
  out <- c(out, paste0("  - crosses: ", if (!is.na(ca)) paste("at", ca) else auto(val_of(ax, "c:crosses"))))
  gl <- c(major = "c:majorGridlines", minor = "c:minorGridlines")
  has <- names(gl)[vapply(gl, function(x) !inherits(xml2::xml_find_first(ax, x, CHART_NS), "xml_missing"), TRUE)]
  out <- c(out, paste0("  - gridlines: ", if (length(has)) paste(has, collapse = " and ") else "none"))
  if (identical(val_of(ax, "c:tickLblPos"), "none")) out <- c(out, "  - tick labels hidden")
  nd <- not_described(ax, AX_KNOWN)
  c(out, indent("  ", nd))
}

# Markdown lines describing one chart from workbook_charts().
describe_chart <- function(chart, cells) {
  out <- if (is.na(chart$sheet)) sprintf("### Chart %d (not on any sheet)", chart$n) else
    sprintf("### Chart %d (sheet %s, %s)", chart$n, chart$sheet, chart$anchor)
  if (!is.null(chart$problem)) return(c(out, paste0("- not described: ", chart$problem)))
  doc <- xml2::read_xml(chart$xml)
  ch <- xml2::xml_find_first(doc, "/c:chartSpace/c:chart", CHART_NS)
  if (inherits(ch, "xml_missing")) {
    return(c(out, "- not described: chartex chart (a newer Excel chart type such as waterfall, histogram or box plot)"))
  }
  pa <- xml2::xml_find_first(ch, "c:plotArea", CHART_NS)
  pkids <- xml2::xml_children(pa)
  groups <- pkids[grepl("Chart$", xml2::xml_name(pkids))]
  axes <- pkids[xml2::xml_name(pkids) %in% names(AX_KIND)]
  gids <- lapply(groups, function(g) xml2::xml_attr(xml2::xml_find_all(g, "c:axId", CHART_NS), "val"))
  primary <- if (length(gids)) gids[[1]] else character()
  for (i in seq_along(groups)) {
    sec <- length(gids[[i]]) && !any(gids[[i]] %in% primary)
    out <- c(out, sprintf("- Part %d: %s%s", i, group_type(groups[[i]]), if (sec) ", on secondary axes" else ""))
  }
  tt <- title_of(ch, cells)
  out <- c(out, paste0("- Title: ", if (!is.na(tt)) tt else if (on_flag(ch, "c:autoTitleDeleted")) "none (deleted)"
                       else "none set (Excel may show the series name)"))
  for (ax in axes) out <- c(out, axis_lines(ax, primary, cells))
  for (i in seq_along(groups)) {
    dl <- dlbls_text(xml2::xml_find_first(groups[[i]], "c:dLbls", CHART_NS))
    out <- c(out, sprintf("- Data labels (part %d): %s", i, if (is.null(dl)) "off" else dl[1]),
             indent("  ", dl[-1]))
  }
  lg <- xml2::xml_find_first(ch, "c:legend", CHART_NS)
  out <- c(out, if (inherits(lg, "xml_missing")) "- Legend: none" else {
    lp <- c(b = "bottom", t = "top", l = "left", r = "right", tr = "top right")[val_of(lg, "c:legendPos")]
    nd <- length(xml2::xml_find_all(lg, "c:legendEntry[c:delete[@val='1' or @val='true']]", CHART_NS))
    paste0("- Legend: on, ", if (is.na(lp)) "right" else lp,
           if (nd) sprintf(", %d entr%s removed", nd, if (nd == 1) "y" else "ies"))
  })
  if (!inherits(xml2::xml_find_first(pa, "c:dTable", CHART_NS), "xml_missing"))
    out <- c(out, "- Data table shown under the chart")
  out <- c(out, if (length(chart$shapes)) paste0("- Other text on the chart: ", chart$shapes)
           else "- Other text on the chart: none")
  if (!on_flag(ch, "c:plotVisOnly") && !is.na(val_of(ch, "c:plotVisOnly")))
    out <- c(out, "- Plots hidden rows and columns too")
  db <- val_of(ch, "c:dispBlanksAs")
  if (!is.na(db)) out <- c(out, paste0("- Empty cells shown as: ", db))
  if (length(groups)) {
    g1 <- groups[[1]]
    s1 <- xml2::xml_find_first(g1, "c:ser", CHART_NS)
    cd <- ref_data(xml2::xml_find_first(s1, "c:cat", CHART_NS), cells)
    if (grepl("^(scatter|bubble)", xml2::xml_name(g1))) {
      out <- c(out, "- Categories (plotted order): none (x values are listed with each series)")
    } else if (is.null(cd) || is.null(cd$v)) {
      out <- c(out, "- Categories (plotted order): not available")
    } else {
      cax <- axes[vapply(axes, function(a) val_of(a, "c:axId") %in% gids[[1]] &&
                           xml2::xml_name(a) %in% c("catAx", "dateAx"), TRUE)]
      rev_ax <- length(cax) && identical(val_of(cax[[1]], "c:scaling/c:orientation"), "maxMin")
      horiz <- identical(val_of(g1, "c:barDir"), "bar")
      # A horizontal bar chart plots the first category at the bottom.
      v <- if (xor(rev_ax, horiz)) rev(cd$v) else cd$v
      out <- c(out, sprintf("- Categories (plotted order): %s%s (%s)", paste(v, collapse = ", "),
                            if (identical(cd$src, "(from cells)")) " (from cells)" else "",
                            if (horiz) "top to bottom" else "left to right"))
    }
  }
  k <- 0
  for (g in groups) {
    sc <- grepl("^(scatter|bubble)", xml2::xml_name(g))
    for (s in xml2::xml_find_all(g, "c:ser", CHART_NS)) {
      k <- k + 1
      out <- c(out, series_lines(s, k, cells, sc))
    }
    out <- c(out, not_described(g, GROUP_KNOWN))
  }
  out <- c(out, not_described(pa, c("layout", "spPr", "dTable", "extLst",
                                    xml2::xml_name(groups), names(AX_KIND))))
  c(out, not_described(ch, c("title", "autoTitleDeleted", "plotArea", "legend", "plotVisOnly",
                             "dispBlanksAs", "showDLblsOverMax", "pivotFmts", "extLst")))
}
