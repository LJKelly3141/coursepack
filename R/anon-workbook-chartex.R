# Newer Excel chart types (chartEx parts, xl/charts/chartEx*.xml: histogram,
# Pareto, box and whisker, waterfall, treemap, sunburst, funnel, filled map),
# described to the same standard as classic charts in anon-workbook-chart.R:
# type, title, axes, legend, and each series with its data ranges and values
# (from the cache, else from cells), its layout options and data labels. Any
# element of the chart, plot area, series, layout options, axis, data labels
# or data that is not interpreted is named "not described: <prefix:name>".

CX_LAYOUT <- c(clusteredColumn = "clustered column", paretoLine = "Pareto line",
               boxWhisker = "box and whisker", waterfall = "waterfall", treemap = "treemap",
               sunburst = "sunburst", funnel = "funnel", regionMap = "filled map")
CX_DIM <- c(cat = "category", val = "value", x = "x", y = "y", size = "size",
            colorVal = "color value", colorStr = "color")

cx_find <- function(node, xp) xml2::xml_find_first(node, xp, CHART_NS)
cx_has <- function(node, xp) !inherits(cx_find(node, xp), "xml_missing")
cx_on <- function(v) !is.na(v) && v %in% c("1", "true")

# The element's qualified name as written in the part (e.g. cx:fooBar).
qname <- function(e) sub("^<", "", regmatches(as.character(e), regexpr("^<[^ />]+", as.character(e))))

# "not described" lines for children of node not in known, and for every
# element inside its cx:extLst/cx:ext that is not on EXT_COSMETIC.
cx_not_described <- function(node, known) {
  kids <- xml2::xml_children(node)
  kids <- kids[!xml2::xml_name(kids) %in% known]
  ext <- xml2::xml_find_all(node, "cx:extLst/cx:ext/*", CHART_NS)
  key <- paste(vapply(ext, function(e) xml2::xml_find_chr(e, "string(namespace-uri())"), ""),
               xml2::xml_name(ext))
  ext <- ext[!key %in% EXT_COSMETIC]
  sprintf("- not described: %s", unique(c(vapply(kids, qname, ""), vapply(ext, qname, ""))))
}

# A cx:title (or any node with cx:tx): its text, NA when absent.
cx_text <- function(node, cells) {
  if (inherits(node, "xml_missing")) return(NA_character_)
  rich <- cx_find(node, "cx:tx/cx:rich")
  if (!inherits(rich, "xml_missing")) return(rich_text(rich))
  td <- cx_find(node, "cx:tx/cx:txData")
  if (inherits(td, "xml_missing")) return("automatic")
  v <- cx_find(td, "cx:v"); f <- xml2::xml_text(cx_find(td, "cx:f"))
  if (!inherits(v, "xml_missing")) {
    return(paste0(xml2::xml_text(v), if (!is.na(f)) paste0(" (linked to ", f, ")")))
  }
  vals <- if (is.na(f)) NULL else range_values(f, cells)
  if (is.null(vals)) "not available" else paste0(paste(vals, collapse = " "), " (from cells)")
}

# One cx:numDim or cx:strDim level as the list show_values() takes.
cx_level <- function(f, lvl, cells) {
  pts <- if (inherits(lvl, "xml_missing")) list() else xml2::xml_find_all(lvl, "cx:pt", CHART_NS)
  fmt <- if (inherits(lvl, "xml_missing")) NA else xml2::xml_attr(lvl, "formatCode")
  if (length(pts)) {
    n <- suppressWarnings(as.numeric(xml2::xml_attr(lvl, "ptCount")))
    idx <- as.numeric(xml2::xml_attr(pts, "idx"))
    if (is.na(n)) n <- max(idx) + 1
    v <- rep("", n)
    v[idx + 1] <- xml2::xml_text(pts)
    return(list(f = f, v = v, src = if (is.na(f)) "typed in" else "", fmt = fmt))
  }
  v <- if (is.na(f)) NULL else range_values(f, cells)
  list(f = f, v = v, src = if (is.null(v)) "none" else "(from cells)", fmt = fmt)
}

# Lines for one cx:data block: each dimension's range and values. Returns the
# lines and the first category level's values (for naming subtotal points).
cx_data_lines <- function(data, cells) {
  out <- character(); cats <- NULL
  for (dim in xml2::xml_find_all(data, "cx:numDim | cx:strDim", CHART_NS)) {
    ty <- xml2::xml_attr(dim, "type")
    lab <- if (!is.na(ty) && ty %in% names(CX_DIM)) CX_DIM[[ty]] else paste("data", ty)
    f <- xml2::xml_text(cx_find(dim, "cx:f"))
    out <- c(out, sprintf("  - %s range: %s", lab, if (is.na(f)) "typed in" else f))
    # Hierarchical categories (treemap, sunburst) have one cx:lvl per level;
    # with no cached level at all, the values come from the cells.
    lvls <- xml2::xml_find_all(dim, "cx:lvl", CHART_NS)
    if (!length(lvls)) lvls <- list(cx_find(dim, "cx:lvl"))
    for (k in seq_along(lvls)) {
      d <- cx_level(f, lvls[[k]], cells)
      if (identical(ty, "cat") && is.null(cats)) cats <- d$v
      # Categories get a count line only; numbers also get min and max.
      sv <- show_values(d, range = !identical(ty, "cat"))
      name <- if (identical(ty, "val")) "values" else paste(lab, "values")
      if (length(lvls) > 1) name <- sprintf("%s (level %d)", name, k)
      out <- c(out, sprintf("  - %s: %s", name, sv$text), indent("  - ", sv$note))
    }
    out <- c(out, indent("  ", cx_not_described(dim, c("f", "nf", "lvl", "extLst"))))
  }
  out <- c(out, indent("  ", cx_not_described(data, c("numDim", "strDim", "extLst"))))
  list(lines = out, cats = cats)
}

cx_bins <- function(lp) {
  if (cx_has(lp, "cx:aggregation")) return("  - bins: by category")
  b <- cx_find(lp, "cx:binning")
  if (inherits(b, "xml_missing")) return(character())
  size <- xml2::xml_attr(cx_find(b, "cx:binSize"), "val")
  count <- xml2::xml_attr(cx_find(b, "cx:binCount"), "val")
  bins <- if (!is.na(size)) paste("bin width", size) else if (!is.na(count)) paste(count, "bins") else "automatic"
  edge <- function(a, word, side) {
    v <- xml2::xml_attr(b, a)
    if (is.na(v)) sprintf("no %s bin", word) else if (v == "auto") sprintf("%s bin automatic", word)
    else sprintf("%s bin %s %s", word, side, v)
  }
  ic <- c(r = "intervals closed on the right", l = "intervals closed on the left")[xml2::xml_attr(b, "intervalClosed")]
  parts <- c(bins, edge("underflow", "underflow", "at or below"), edge("overflow", "overflow", "above"),
             if (!is.na(ic)) ic)
  c(paste0("  - bins: ", paste(parts, collapse = "; ")),
    indent("  ", cx_not_described(b, c("binSize", "binCount"))))
}

cx_box <- function(lp) {
  out <- character()
  qm <- xml2::xml_attr(cx_find(lp, "cx:statistics"), "quartileMethod")
  if (!is.na(qm)) out <- c(out, paste0("  - quartile method: ", qm))
  vis <- cx_find(lp, "cx:visibility")
  if (!inherits(vis, "xml_missing")) {
    w <- c(meanLine = "mean line", meanMarker = "mean markers", nonoutliers = "inner points", outliers = "outliers")
    v <- vapply(names(w), function(a) xml2::xml_attr(vis, a), "")
    on <- w[!is.na(v) & v %in% c("1", "true")]; off <- w[!is.na(v) & v %in% c("0", "false")]
    out <- c(out, paste0("  - ", paste(c(if (length(on)) paste0("shown: ", paste(on, collapse = ", ")),
                                          if (length(off)) paste0("hidden: ", paste(off, collapse = ", "))),
                                        collapse = "; ")))
  }
  out
}

cx_labels <- function(dl) {
  if (inherits(dl, "xml_missing")) return("  - data labels: off")
  vis <- cx_find(dl, "cx:visibility")
  w <- c(value = "value", categoryName = "category name", seriesName = "series name")
  shown <- if (inherits(vis, "xml_missing")) character() else
    w[vapply(names(w), function(a) cx_on(xml2::xml_attr(vis, a)), TRUE)]
  pos <- xml2::xml_attr(dl, "pos")
  out <- paste0("  - data labels: ", if (inherits(vis, "xml_missing")) "on" else if (!length(shown)) "off" else
    paste0("on, showing ", paste(shown, collapse = ", ")), if (!is.na(pos)) paste0(", position ", pos))
  nf <- xml2::xml_attr(cx_find(dl, "cx:numFmt"), "formatCode")
  if (!is.na(nf)) out <- c(out, paste0("    - label number format: ", nf))
  hid <- xml2::xml_attr(xml2::xml_find_all(dl, "cx:dataLabelHidden", CHART_NS), "idx")
  if (length(hid)) {
    cl <- capped_list(as.character(as.numeric(hid) + 1), range = FALSE)
    out <- c(out, paste0("    - labels removed on points: ", cl$text), indent("    - ", cl$note))
  }
  for (p in xml2::xml_find_all(dl, "cx:dataLabel", CHART_NS)) {
    out <- c(out, sprintf("    - not described: cx:dataLabel (label settings for point %d)",
                          as.numeric(xml2::xml_attr(p, "idx")) + 1))
  }
  c(out, indent("    ", cx_not_described(dl, c("numFmt", "spPr", "txPr", "visibility", "separator",
                                                  "dataLabel", "dataLabelHidden", "extLst"))))
}

cx_series_lines <- function(s, k, datas, cells) {
  tx <- cx_find(s, "cx:tx")
  name <- if (inherits(tx, "xml_missing")) "no name" else {
    t <- cx_text(s, cells)
    if (identical(t, "not available")) "name not available" else sub(" \\(linked to [^)]*\\)$", "", t)
  }
  f <- xml2::xml_text(cx_find(s, "cx:tx/cx:txData/cx:f"))
  out <- sprintf("- Series %d: %s%s", k, name, if (!is.na(f)) paste0(" (", f, ")") else "")
  lid <- xml2::xml_attr(s, "layoutId")
  lp <- cx_find(s, "cx:layoutPr")
  hist <- identical(lid, "clusteredColumn") && !inherits(lp, "xml_missing") &&
    (cx_has(lp, "cx:binning") || cx_has(lp, "cx:aggregation"))
  type <- if (hist) "histogram" else if (identical(lid, "paretoLine")) {
    owner <- suppressWarnings(as.numeric(xml2::xml_attr(s, "ownerIdx")))
    if (is.na(owner)) "Pareto line (cumulative percent)" else
      sprintf("Pareto line (cumulative percent of series %d)", owner + 1)
  } else if (!is.na(lid) && lid %in% names(CX_LAYOUT)) CX_LAYOUT[[lid]] else
    paste0("not described: layout ", if (is.na(lid)) "(none)" else lid)
  out <- c(out, paste0("  - type: ", type))
  if (cx_on(xml2::xml_attr(s, "hidden"))) out <- c(out, "  - hidden")
  did <- xml2::xml_attr(cx_find(s, "cx:dataId"), "val")
  cats <- NULL
  if (!is.na(did)) {
    d <- datas[[did]]
    if (is.null(d)) out <- c(out, "  - data: not available") else {
      dl <- cx_data_lines(d, cells)
      out <- c(out, dl$lines)
      cats <- dl$cats
    }
  }
  if (!inherits(lp, "xml_missing")) {
    out <- c(out, cx_bins(lp), cx_box(lp))
    st <- xml2::xml_attr(xml2::xml_find_all(lp, "cx:subtotals/cx:idx", CHART_NS), "val")
    if (length(st)) {
      i <- as.numeric(st) + 1
      nm <- if (is.null(cats)) rep(NA, length(i)) else cats[i]
      out <- c(out, paste0("  - subtotal points: ", paste0(i, ifelse(is.na(nm) | !nzchar(nm), "", paste0(" (", nm, ")")),
                                                          collapse = ", ")))
    }
    out <- c(out, indent("  ", cx_not_described(lp, c("binning", "aggregation", "statistics", "visibility",
                                                      "subtotals", "extLst"))))
  }
  if (!identical(lid, "paretoLine")) out <- c(out, cx_labels(cx_find(s, "cx:dataLabels")))
  c(out, indent("  ", cx_not_described(s, c("tx", "spPr", "valueColors", "valueColorPositions", "dataPt",
                                            "dataLabels", "dataId", "layoutPr", "axisId", "extLst"))))
}

cx_axis_lines <- function(ax, k, cells) {
  cat_ax <- cx_has(ax, "cx:catScaling")
  out <- sprintf("- Axis %d: %s%s", k, if (cat_ax) "category axis" else "value axis",
                 if (cx_on(xml2::xml_attr(ax, "hidden"))) ", hidden" else "")
  tt <- cx_text(cx_find(ax, "cx:title"), cells)
  out <- c(out, paste0("  - title: ", if (is.na(tt)) "none" else tt))
  auto <- function(v) if (is.na(v) || v == "auto") "automatic" else v
  if (cat_ax) {
    gw <- xml2::xml_attr(cx_find(ax, "cx:catScaling"), "gapWidth")
    out <- c(out, paste0("  - scale: ", if (is.na(gw)) "categories" else paste("gap width", gw)))
  } else {
    vs <- cx_find(ax, "cx:valScaling")
    a <- function(n) auto(if (inherits(vs, "xml_missing")) NA else xml2::xml_attr(vs, n))
    out <- c(out, sprintf("  - scale: min %s, max %s, major unit %s, minor unit %s",
                          a("min"), a("max"), a("majorUnit"), a("minorUnit")))
  }
  un <- xml2::xml_attr(cx_find(ax, "cx:units"), "unit")
  if (!is.na(un)) out <- c(out, paste0("  - display units: ", un))
  nf <- cx_find(ax, "cx:numFmt")
  if (!inherits(nf, "xml_missing"))
    out <- c(out, paste0("  - number format: ", xml2::xml_attr(nf, "formatCode"),
                         if (xml2::xml_attr(nf, "sourceLinked") %in% "1") " (linked to source)"))
  gl <- c(major = "cx:majorGridlines", minor = "cx:minorGridlines")
  has <- names(gl)[vapply(gl, function(x) cx_has(ax, x), TRUE)]
  out <- c(out, paste0("  - gridlines: ", if (length(has)) paste(has, collapse = " and ") else "none"))
  # In a chartEx axis, tick labels are drawn only when cx:tickLabels is present.
  if (!cx_has(ax, "cx:tickLabels")) out <- c(out, "  - tick labels hidden")
  c(out, indent("  ", cx_not_described(ax, c("catScaling", "valScaling", "title", "units", "majorGridlines",
                                             "minorGridlines", "majorTickMarks", "minorTickMarks",
                                             "tickLabels", "numFmt", "spPr", "txPr", "extLst"))))
}

# Markdown lines (after the heading) for a chartEx part.
describe_chartex <- function(doc, chart, cells) {
  ch <- xml2::xml_find_first(doc, "/cx:chartSpace/cx:chart", CHART_NS)
  if (inherits(ch, "xml_missing")) return("- not described: chart part with no chart in it")
  # A formula that is one of Excel's hidden _xlchart names is replaced by the
  # range it stands for (from workbook.xml), so the range is shown and the
  # cells fallback reads it. A name that cannot be resolved reads "range not
  # available", which looks up no cells, so its values are "values not available".
  xn <- chart$xlnames
  for (f in xml2::xml_find_all(doc, "//cx:f", CHART_NS)) {
    t <- trimws(xml2::xml_text(f))
    if (!startsWith(t, "_xlchart.")) next
    r <- if (!is.null(xn) && t %in% names(xn)) unname(xn[[t]]) else NA
    xml2::xml_text(f) <- if (is.na(r) || !nzchar(r)) "range not available" else r
  }
  datas <- xml2::xml_find_all(doc, "/cx:chartSpace/cx:chartData/cx:data", CHART_NS)
  datas <- stats::setNames(as.list(datas), xml2::xml_attr(datas, "id"))
  pa <- cx_find(ch, "cx:plotArea")
  reg <- cx_find(pa, "cx:plotAreaRegion")
  sers <- if (inherits(reg, "xml_missing")) list() else xml2::xml_find_all(reg, "cx:series", CHART_NS)
  lids <- xml2::xml_attr(sers, "layoutId")
  hist <- vapply(sers, function(s) cx_has(s, "cx:layoutPr/cx:binning") || cx_has(s, "cx:layoutPr/cx:aggregation"), TRUE)
  kinds <- unique(ifelse(lids %in% "clusteredColumn" & hist, "histogram",
                         ifelse(lids %in% names(CX_LAYOUT), CX_LAYOUT[lids],
                                ifelse(is.na(lids), "type not named", paste("layout", lids)))))
  out <- if ("paretoLine" %in% lids) {
    "- Type: Pareto (a histogram with a cumulative percent line; a newer Excel chart type)"
  } else if (length(kinds)) {
    sprintf("- Type: %s (a newer Excel chart type)", paste(kinds, collapse = " and "))
  } else "- Type: newer Excel chart type with no series"
  tt <- cx_text(cx_find(ch, "cx:title"), cells)
  out <- c(out, paste0("- Title: ", if (is.na(tt)) "none" else tt))
  axes <- if (inherits(pa, "xml_missing")) list() else xml2::xml_find_all(pa, "cx:axis", CHART_NS)
  for (k in seq_along(axes)) out <- c(out, cx_axis_lines(axes[[k]], k, cells))
  lg <- cx_find(ch, "cx:legend")
  out <- c(out, if (inherits(lg, "xml_missing")) "- Legend: none" else {
    lp <- c(b = "bottom", t = "top", l = "left", r = "right")[xml2::xml_attr(lg, "pos")]
    c(paste0("- Legend: on, ", if (is.na(lp)) "position not set" else lp),
      indent("  ", cx_not_described(lg, c("spPr", "txPr", "extLst"))))
  })
  out <- c(out, if (length(chart$shapes)) paste0("- Other text on the chart: ", chart$shapes)
           else "- Other text on the chart: none")
  for (k in seq_along(sers)) out <- c(out, cx_series_lines(sers[[k]], k, datas, cells))
  if (!inherits(reg, "xml_missing")) out <- c(out, cx_not_described(reg, c("plotSurface", "series", "extLst")))
  if (!inherits(pa, "xml_missing")) out <- c(out, cx_not_described(pa, c("plotAreaRegion", "axis", "spPr", "extLst")))
  out <- c(out, cx_not_described(ch, c("title", "plotArea", "legend", "extLst")))
  c(out, cx_not_described(xml2::xml_root(doc), c("chartData", "chart", "spPr", "txPr", "clrMapOvr",
                                                 "fmtOvrs", "printSettings", "extLst")))
}
