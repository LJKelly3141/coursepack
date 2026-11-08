# The parts of a submitted workbook other than cells and charts: pivot
# tables, comments, drawings (pictures, text boxes, shapes), hyperlinks,
# defined names, headers and footers, embedded documents, and the count of
# everything else. Each returns markdown lines; workbook_to_md() places them.
# Comment authors and person ids are never read; neither are the parts
# workbook_open() leaves unextracted.

# Relationships of the part at owner: id, type (last path segment), resolved
# target, and whether the target is outside the file.
rels_table <- function(root, owner) {
  rp <- file.path(root, dirname(owner), "_rels", paste0(basename(owner), ".rels"))
  empty <- data.frame(id = character(), type = character(), target = character(),
                      external = logical(), stringsAsFactors = FALSE)
  if (!file.exists(rp)) return(empty)
  r <- xml2::xml_find_all(xml2::xml_ns_strip(xml2::read_xml(rp)), "//Relationship")
  if (!length(r)) return(empty)
  ext <- xml2::xml_attr(r, "TargetMode") %in% "External"
  tg <- xml2::xml_attr(r, "Target")
  tg[!ext] <- vapply(tg[!ext], part_path, "", base_dir = dirname(owner))
  data.frame(id = xml2::xml_attr(r, "Id"), type = basename(xml2::xml_attr(r, "Type")),
             target = tg, external = ext, stringsAsFactors = FALSE)
}

rel_of <- function(rt, type) rt$target[rt$type == type & !rt$external]

# A sheet name as a formula would write it.
sheet_ref <- function(name) {
  if (grepl("^[A-Za-z_][A-Za-z0-9_.]*$", name)) name else paste0("'", gsub("'", "''", name), "'")
}

# Text of a node's a:p paragraphs (DrawingML), empty ones dropped.
para_text <- function(node) {
  t <- vapply(xml2::xml_find_all(node, ".//a:p", CHART_NS), function(p)
    paste(xml2::xml_text(xml2::xml_find_all(p, ".//a:t", CHART_NS)), collapse = ""), "")
  t[nzchar(trimws(t))]
}

one_line <- function(x) gsub("\\s*\n\\s*", " / ", trimws(x))

add_other <- function(st, kind, n = 1L, detail = NULL) {
  if (n <= 0) return(invisible())
  st$other[[kind]] <- (if (is.null(st$other[[kind]])) 0L else st$other[[kind]]) + as.integer(n)
  st$detail[[kind]] <- c(st$detail[[kind]], detail)
  invisible()
}

# ---- pivot tables ---------------------------------------------------------

pivot_lines <- function(root, pp, sname) {
  pd <- xml2::read_xml(file.path(root, pp))
  at <- function(node, xp, a) xml2::xml_attr(xml2::xml_find_all(node, xp, CHART_NS), a)
  loc <- at(pd, "m:location", "ref")
  out <- sprintf("- %s on %s at %s", xml2::xml_attr(pd, "name"), sheet_ref(sname), loc)
  cp <- rel_of(rels_table(root, pp), "pivotCacheDefinition")
  if (!length(cp) || !file.exists(file.path(root, cp[1]))) {
    return(c(out, "  - not described: pivot cache (missing from the file)"))
  }
  cd <- xml2::read_xml(file.path(root, cp[1]))
  ws <- xml2::xml_find_first(cd, "m:cacheSource/m:worksheetSource", CHART_NS)
  src <- if (inherits(ws, "xml_missing")) {
    sprintf("%s data (not read)", xml2::xml_attr(xml2::xml_find_first(cd, "m:cacheSource", CHART_NS), "type"))
  } else if (!is.na(xml2::xml_attr(ws, "name"))) {
    xml2::xml_attr(ws, "name")
  } else {
    sh <- xml2::xml_attr(ws, "sheet")
    paste0(if (is.na(sh)) "" else paste0(sheet_ref(sh), "!"), xml2::xml_attr(ws, "ref"))
  }
  cf <- xml2::xml_find_all(cd, "m:cacheFields/m:cacheField", CHART_NS)
  fname <- xml2::xml_attr(cf, "name")
  fld <- function(x) {
    x <- as.integer(x)
    ifelse(x == -2L, "Values", ifelse(x + 1L <= length(fname), fname[pmax(x + 1L, 1L)], "(unknown field)"))
  }
  shared <- lapply(cf, function(f) {
    it <- xml2::xml_children(xml2::xml_find_first(f, "m:sharedItems", CHART_NS))
    v <- xml2::xml_attr(it, "v")
    ifelse(is.na(v), "(blank)", v)
  })
  item_val <- function(fi, x) {
    s <- shared[[fi + 1L]]
    if (length(s) >= x + 1L) s[x + 1L] else "(unknown item)"
  }
  list_or_none <- function(x) if (length(x)) paste(x, collapse = ", ") else "none"
  out <- c(out, paste0("  - source: ", src),
           paste0("  - rows: ", list_or_none(fld(at(pd, "m:rowFields/m:field", "x")))),
           paste0("  - columns: ", list_or_none(fld(at(pd, "m:colFields/m:field", "x")))))
  df <- xml2::xml_find_all(pd, "m:dataFields/m:dataField", CHART_NS)
  vals <- vapply(df, function(d) {
    sub <- xml2::xml_attr(d, "subtotal"); sda <- xml2::xml_attr(d, "showDataAs")
    sprintf("%s (%s of %s%s)", xml2::xml_attr(d, "name"), if (is.na(sub)) "sum" else sub,
            fld(xml2::xml_attr(d, "fld")), if (is.na(sda)) "" else paste0(", shown as ", sda))
  }, "")
  out <- c(out, paste0("  - values: ", list_or_none(vals)))
  pf <- xml2::xml_find_all(pd, "m:pageFields/m:pageField", CHART_NS)
  pivot_fields <- xml2::xml_find_all(pd, "m:pivotFields/m:pivotField", CHART_NS)
  filt <- vapply(pf, function(p) {
    fi <- as.integer(xml2::xml_attr(p, "fld")); item <- xml2::xml_attr(p, "item")
    shown <- if (is.na(item)) "all" else {
      x <- xml2::xml_attr(xml2::xml_find_all(pivot_fields[[fi + 1L]], "m:items/m:item", CHART_NS), "x")
      xi <- x[as.integer(item) + 1L]
      if (is.na(xi)) "(unknown item)" else item_val(fi, as.integer(xi))
    }
    sprintf("%s = %s", fld(fi), shown)
  }, "")
  out <- c(out, paste0("  - report filters: ", list_or_none(filt)))
  for (i in seq_along(pivot_fields)) {
    h <- xml2::xml_attr(xml2::xml_find_all(pivot_fields[[i]], "m:items/m:item[@h='1' or @h='true']", CHART_NS), "x")
    if (length(h)) {
      cl <- capped_list(vapply(as.integer(h), item_val, "", fi = i - 1L), "items", range = FALSE)
      out <- c(out, sprintf("  - hidden items in %s: %s", fname[i], cl$text), indent("    - ", cl$note))
    }
  }
  for (f in xml2::xml_find_all(pd, "m:filters/m:filter", CHART_NS)) {
    v <- xml2::xml_attr(f, c("stringValue1", "stringValue2"))
    out <- c(out, sprintf("  - filter on %s: %s %s", fld(xml2::xml_attr(f, "fld")), xml2::xml_attr(f, "type"),
                          paste(v[!is.na(v)], collapse = " and ")))
  }
  calc <- !is.na(xml2::xml_attr(cf, "formula"))
  if (any(calc)) out <- c(out, sprintf("  - calculated field %s: `=%s`", fname[calc], xml2::xml_attr(cf[calc], "formula")))
  out
}

# ---- comments -------------------------------------------------------------

# A legacy note's text. Excel starts a note with a bold "Name:" run and a
# line break; that run is the author, so it is replaced by a visible marker
# without reading the author list (Logan's ruling, 2026-11-08).
note_text <- function(tx) {
  runs <- xml2::xml_find_all(tx, "m:r", CHART_NS)
  rt <- vapply(runs, function(r) paste(xml2::xml_text(xml2::xml_find_all(r, "m:t", CHART_NS)), collapse = ""), "")
  if (length(runs) >= 2 && !inherits(xml2::xml_find_first(runs[[1]], "m:rPr/m:b", CHART_NS), "xml_missing") &&
      grepl(":\\s*$", rt[1]) && grepl("^\\s*\n", rt[2])) {
    rt <- c("[author removed]: ", sub("^\\s*\n\\s*", "", rt[2]), rt[-(1:2)])
  }
  paste(c(xml2::xml_text(xml2::xml_find_all(tx, "m:t", CHART_NS)), rt), collapse = "")
}

comment_lines <- function(root, rt, sname) {
  out <- character(); threaded_refs <- character()
  tns <- c(t = "http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments")
  for (tp in rel_of(rt, "threadedComment")) {
    if (!file.exists(file.path(root, tp))) next
    for (tc in xml2::xml_find_all(xml2::read_xml(file.path(root, tp)), "//t:threadedComment", tns)) {
      ref <- xml2::xml_attr(tc, "ref")
      txt <- one_line(xml2::xml_text(xml2::xml_find_first(tc, "t:text", tns)))
      if (is.na(xml2::xml_attr(tc, "parentId"))) {
        threaded_refs <- c(threaded_refs, ref)
        out <- c(out, sprintf("- %s!%s (threaded comment): %s", sheet_ref(sname), ref, txt))
      } else {
        out <- c(out, sprintf("  - reply on %s!%s: %s", sheet_ref(sname), ref, txt))
      }
    }
  }
  for (cp in rel_of(rt, "comments")) {
    if (!file.exists(file.path(root, cp))) next
    for (cm in xml2::xml_find_all(xml2::read_xml(file.path(root, cp)), "//m:commentList/m:comment", CHART_NS)) {
      ref <- xml2::xml_attr(cm, "ref")
      txt <- note_text(xml2::xml_find_first(cm, "m:text", CHART_NS))
      # The stand-in Excel writes for a threaded comment, already listed.
      if (ref %in% threaded_refs && startsWith(txt, "[Threaded comment]")) next
      out <- c(out, sprintf("- %s!%s (note): %s", sheet_ref(sname), ref, one_line(txt)))
    }
  }
  out
}

# ---- drawings -------------------------------------------------------------

# Pictures (linked under the sheet), text boxes and shapes (listed in their
# own section), and a count of any other drawing object. Charts are skipped:
# workbook_charts() already has them.
drawing_lines <- function(root, rt, sdoc, sname, chartsheet, st, media_dir, media_rel) {
  pics <- character(); text <- character()
  for (dp in rel_of(rt, "drawing")) {
    if (!file.exists(file.path(root, dp))) next
    dd <- xml2::read_xml(file.path(root, dp))
    # Keep what Excel shows; a Fallback is a stand-in for older versions.
    xml2::xml_remove(xml2::xml_find_all(dd, "//*[local-name()='Fallback']"))
    drel <- rels_table(root, dp)
    for (top in xml2::xml_children(dd)) {
      at <- if (chartsheet) "whole sheet" else tryCatch(anchor_of(top, sdoc), error = function(e) "position unknown")
      where <- sprintf("on %s at %s", sname, at)
      for (pic in xml2::xml_find_all(top, ".//xdr:pic", CHART_NS)) {
        bl <- xml2::xml_find_first(pic, ".//a:blip", CHART_NS)
        id <- xml2::xml_attr(bl, "r:embed", CHART_NS)
        mp <- drel$target[drel$id %in% id & !drel$external]
        alt <- xml2::xml_attr(xml2::xml_find_first(pic, ".//xdr:cNvPr", CHART_NS), "descr")
        alt <- if (is.na(alt) || !nzchar(trimws(alt))) "" else sprintf(", alt text \"%s\"", one_line(alt))
        if (!length(mp) || !file.exists(file.path(root, mp[1]))) {
          add_other(st, "other_pictures", detail = "linked or missing picture"); next
        }
        # Only a media part is copied out as a picture.
        if (!grepl("^xl/media/[^/]+$", mp[1])) {
          add_other(st, "other_pictures", detail = "picture pointing outside xl/media (not copied)"); next
        }
        mp <- mp[1]
        if (is.null(st$media[[mp]])) {
          st$n_image <- st$n_image + 1L
          dest <- sprintf("image%d.%s", st$n_image, tolower(tools::file_ext(mp)))
          dir.create(media_dir, recursive = TRUE, showWarnings = FALSE)
          file.copy(file.path(root, mp), file.path(media_dir, dest))
          st$media[[mp]] <- dest
        }
        pics <- c(pics, sprintf("- Picture at %s%s: ![picture](%s/%s)", at, alt, media_rel, st$media[[mp]]))
      }
      for (sp in xml2::xml_find_all(top, ".//xdr:sp", CHART_NS)) {
        tx <- para_text(sp)
        link <- xml2::xml_attr(sp, "textlink")
        link <- if (is.na(link) || !nzchar(link)) "" else sprintf(" (text linked to `=%s`)", link)
        box <- !is.na(xml2::xml_attr(xml2::xml_find_first(sp, ".//xdr:cNvSpPr", CHART_NS), "txBox"))
        kind <- if (box) "Text box" else {
          g <- xml2::xml_attr(xml2::xml_find_first(sp, ".//a:prstGeom", CHART_NS), "prst")
          paste0("Shape", if (is.na(g)) "" else paste0(" (", g, ")"))
        }
        text <- c(text, if (length(tx) <= 1) {
          sprintf("- %s %s%s: %s", kind, where, link, if (length(tx)) tx else "no text")
        } else c(sprintf("- %s %s%s:", kind, where, link), paste0("  - ", tx)))
      }
      n_cx <- length(xml2::xml_find_all(top, ".//xdr:cxnSp", CHART_NS))
      if (n_cx) text <- c(text, sprintf("- Connector line %s", where))
      for (gf in xml2::xml_find_all(top, ".//xdr:graphicFrame", CHART_NS)) {
        if (inherits(xml2::xml_find_first(gf, ".//c:chart | .//cx:chart", CHART_NS), "xml_missing")) {
          gd <- xml2::xml_attr(xml2::xml_find_first(gf, ".//a:graphicData", CHART_NS), "uri")
          add_other(st, "drawing_objects", detail = basename(if (is.na(gd)) "graphic frame" else gd))
        }
      }
      other <- xml2::xml_find_all(top, "./*[local-name()='contentPart'] | .//*[local-name()='contentPart']")
      if (length(other)) add_other(st, "drawing_objects", length(other), "ink")
    }
  }
  list(pictures = pics, text = text)
}

# Form controls and the like live in the sheet's VML drawing. VML is often
# not well-formed XML, so object types are counted from the text.
vml_controls <- function(root, rt, st) {
  for (vp in rel_of(rt, "vmlDrawing")) {
    if (!file.exists(file.path(root, vp))) next
    txt <- paste(readLines(file.path(root, vp), warn = FALSE), collapse = "\n")
    ty <- sub('ObjectType="([^"]*)"', "\\1", regmatches(txt, gregexpr('ObjectType="[^"]*"', txt))[[1]])
    ty <- ty[ty != "Note"]
    add_other(st, "form_controls", length(ty), unique(ty))
  }
}

# ---- hyperlinks, defined names, headers and footers -----------------------

hyperlink_lines <- function(rt, sdoc, sname, cells) {
  out <- character()
  for (h in xml2::xml_find_all(sdoc, "/m:worksheet/m:hyperlinks/m:hyperlink", CHART_NS)) {
    ref <- xml2::xml_attr(h, "ref")
    id <- xml2::xml_attr(h, "r:id", CHART_NS)
    tg <- rt$target[rt$id %in% id]
    loc <- xml2::xml_attr(h, "location")
    to <- c(if (length(tg)) tg[1], if (!is.na(loc)) paste0("#", loc))
    disp <- xml2::xml_attr(h, "display")
    if (is.na(disp)) {
      cc <- cells$character[cells$sheet == sname & cells$address == ref]
      disp <- if (length(cc) && !is.na(cc[1])) cc[1] else ""
    }
    tip <- xml2::xml_attr(h, "tooltip")
    out <- c(out, sprintf("- %s!%s: \"%s\" -> %s%s", sheet_ref(sname), ref, one_line(disp),
                          if (length(to)) paste(to, collapse = " ") else "(no target)",
                          if (is.na(tip)) "" else sprintf(" (tooltip \"%s\")", one_line(tip))))
  }
  out
}

# chart_names: the _xlchart names a chart uses (attr "xlchart_used" of
# workbook_charts()); they are described with the chart, not listed here.
defined_name_lines <- function(wbx, sheet_names, chart_names = character()) {
  out <- character()
  for (d in xml2::xml_find_all(wbx, "//m:definedNames/m:definedName", CHART_NS)) {
    nm <- xml2::xml_attr(d, "name")
    # Excel's own names: a filter's range, and the hidden names that hold a
    # newer chart type's data formulas (described with the chart instead).
    if (nm == "_xlnm._FilterDatabase" || nm %in% chart_names) next
    ls <- suppressWarnings(as.integer(xml2::xml_attr(d, "localSheetId")))
    scope <- if (is.na(ls)) "" else sprintf(" (scope: %s)",
                                            if (ls + 1L <= length(sheet_names)) sheet_names[ls + 1L] else "unknown sheet")
    hid <- if (xml2::xml_attr(d, "hidden") %in% c("1", "true")) " (hidden)" else ""
    out <- c(out, sprintf("- %s: %s%s%s", sub("^_xlnm\\.", "", nm), xml2::xml_text(d), scope, hid))
  }
  out
}

HF_KIND <- c(oddHeader = "header", oddFooter = "footer", evenHeader = "even-page header",
             evenFooter = "even-page footer", firstHeader = "first-page header",
             firstFooter = "first-page footer")

# Split a header/footer string on its &L, &C, &R sections and turn the codes
# into words.
hf_sections <- function(s) {
  s <- gsub("&&", "\001", s, fixed = TRUE)
  pos <- gregexpr("&[LCR]", s)[[1]]
  if (pos[1] == -1) {
    parts <- c(C = s)
  } else {
    starts <- c(1, pos + 2); ends <- c(pos - 1, nchar(s))
    keys <- c("C", substring(s, pos + 1, pos + 1))
    parts <- stats::setNames(substring(s, starts, ends), keys)
  }
  clean <- function(x) {
    x <- gsub('&"[^"]*"', "", x)
    x <- gsub("&K([0-9A-Fa-f]{6}|[0-9]{2}[+-][0-9]{3})", "", x)
    x <- gsub("&[0-9]+", "", x)
    for (k in names(HF_CODES)) x <- gsub(paste0("&", k), HF_CODES[[k]], x, fixed = TRUE)
    x <- gsub("&[BIUSEXYO]", "", x)
    gsub("\001", "&", x, fixed = TRUE)
  }
  parts <- vapply(parts, clean, "")
  parts <- tapply(parts, names(parts), paste, collapse = "")
  lab <- c(L = "left", C = "center", R = "right")
  keep <- intersect(c("L", "C", "R"), names(parts)[nzchar(trimws(parts))])
  paste(sprintf("%s: %s", lab[keep], trimws(parts[keep])), collapse = "; ")
}
HF_CODES <- c(P = "[page]", N = "[pages]", D = "[date]", T = "[time]", F = "[file name]",
              A = "[sheet name]", Z = "[file path]", G = "[picture]")

header_lines <- function(sdoc, sname) {
  out <- character()
  for (h in xml2::xml_find_all(sdoc, "/*/m:headerFooter/*", CHART_NS)) {
    k <- HF_KIND[xml2::xml_name(h)]
    tx <- hf_sections(xml2::xml_text(h))
    if (!is.na(k) && nzchar(tx)) out <- c(out, sprintf("- %s, %s: %s", sname, k, tx))
  }
  out
}

# ---- embedded documents ---------------------------------------------------

# "docx", "odt" or "pdf" with the bytes to convert, or NULL.
embedded_kind <- function(path) {
  raw <- readBin(path, "raw", file.size(path))
  if (length(raw) >= 4 && identical(raw[1:2], charToRaw("PK"))) {
    nm <- tryCatch(utils::unzip(path, list = TRUE)$Name, error = function(e) character())
    if ("word/document.xml" %in% nm) return(list(ext = "docx", bytes = raw))
    if ("content.xml" %in% nm && "mimetype" %in% nm) return(list(ext = "odt", bytes = raw))
    return(NULL)
  }
  st <- grepRaw("%PDF-", raw, fixed = TRUE)
  if (!length(st)) return(NULL)
  en <- grepRaw("%%EOF", raw, fixed = TRUE, all = TRUE)
  en <- en[en > st]
  if (!length(en)) return(NULL)
  list(ext = "pdf", bytes = raw[st:(max(en) + 4L)], from_ole = st > 1L)
}

# Each Word, OpenDocument or PDF file pasted into the workbook, converted
# through the document path; anything else is counted.
embedded_lines <- function(root, nm, st, media_dir, media_rel) {
  out <- character(); k <- 0L
  for (p in sort(grep("^xl/embeddings/[^/]+$", nm, value = TRUE))) {
    f <- file.path(root, p)
    kind <- if (file.exists(f)) embedded_kind(f) else NULL
    if (is.null(kind)) { add_other(st, "embedded_objects", detail = basename(p)); next }
    src <- tempfile(fileext = paste0(".", kind$ext))
    writeBin(kind$bytes, src)
    k <- k + 1L
    dir.create(media_dir, recursive = TRUE, showWarnings = FALSE)
    sub_dir <- file.path(media_dir, sprintf("embedded%d", k))
    md <- file.path(media_dir, sprintf("embedded%d.md", k))
    txt <- tryCatch({
      convert_to_text(src, md, sub_dir)
      readLines(md, warn = FALSE, encoding = "UTF-8")
    }, error = function(e) NULL)
    unlink(c(md, src))
    if (dir.exists(sub_dir) && !length(list.files(sub_dir, recursive = TRUE))) unlink(sub_dir, recursive = TRUE)
    if (is.null(txt)) {
      unlink(sub_dir, recursive = TRUE); k <- k - 1L
      add_other(st, "embedded_objects", detail = sprintf("%s (could not be converted)", basename(p)))
      next
    }
    txt <- gsub(sprintf("](%s/", basename(sub_dir)), sprintf("](%s/%s/", media_rel, basename(sub_dir)),
                txt, fixed = TRUE)
    # Its headings sit below this one.
    txt <- sub("^(#{1,4}) ", "##\\1 ", txt)
    note <- if (isTRUE(kind$from_ole))
      c("*This document was taken out of an embedded object; it may be incomplete.*", "")
    # pdfimages output is not linked from the text, so link it here.
    imgs <- if (kind$ext == "pdf" && dir.exists(sub_dir))
      sort(list.files(sub_dir, pattern = "\\.(png|jpe?g|ppm|pbm|tif)$")) else character()
    links <- if (length(imgs))
      c("", sprintf("![image](%s/%s/%s)", media_rel, basename(sub_dir), imgs)) else character()
    out <- c(out, sprintf("## Embedded document %d", k), "", note, txt, links, "")
  }
  out
}
