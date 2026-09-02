#' Build a course's LMS dashboard card image
#'
#' Draws the small image a learning management system shows on its dashboard,
#' from the course's own `course.yml`. Canvas documents this card as 262 by 146
#' pixels, a 131:73 ratio, which is the default here.
#'
#' @section Why this is generated rather than drawn once:
#'
#' The card carries the course code and title, which change on every rollover
#' and again when a course is reused as a template. A checked-in PNG has to be
#' reopened in an image editor by whoever inherits it, which in practice means
#' it goes stale silently: a card reading the previous course's code looks
#' deliberate and nothing in a build can notice. Generating it from the same
#' YAML that drives the cartridge means the card cannot disagree with the
#' course.
#'
#' @section Why it is drawn large and then shrunk:
#'
#' Type drawn directly at 262 pixels wide is ragged, because there are too few
#' pixels for the renderer to antialias into. The art is drawn at
#' `supersample` times the final size and reduced once with a Lanczos filter.
#' Every measurement below is written as its FINAL pixel size, so the numbers
#' mean what they say on a real dashboard.
#'
#' @section What a card this size can hold:
#'
#' A course code, a title, and one shape. Nothing else survives. A tagline set
#' small enough to fit renders about five pixels tall and reads as grey mush,
#' so this function does not draw one and offers no option to.
#'
#' @param proj Course project root. Read for `course.yml` and written to under
#'   `assets/images/`.
#' @param out Output path. Defaults to `assets/images/course-tile.png` under
#'   `proj`.
#' @param width,height Final pixel size. Defaults are Canvas's documented card.
#' @param supersample Integer factor to draw at before reducing. 1 disables the
#'   reduction and draws directly at final size, which is faster and worse.
#' @param seed Integer seed for the scatter, so a given course's card is
#'   reproducible byte for byte across machines.
#'
#' @section Course-specific values:
#'
#' Read from `course.yml`, never hardcoded here:
#' `title`, `code`, and an optional `card:` block giving `ink`, `paper`,
#' `accent` and `muted` as hex colours. A course that declares no `card:` block
#' gets the defaults below.
#'
#' @return The output path, invisibly.
#' @export
course_tile <- function(proj,
                        out = NULL,
                        width = 262L,
                        height = 146L,
                        supersample = 4L,
                        seed = 1L) {
  stopifnot(is.character(proj), length(proj) == 1L, dir.exists(proj))
  stopifnot(supersample >= 1L)

  yml <- file.path(proj, "course.yml")
  if (!file.exists(yml)) stop("no course.yml under ", proj)
  course <- yaml::yaml.load_file(yml)

  if (is.null(out)) out <- file.path(proj, "assets", "images", "course-tile.png")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

  # Defaults are a dark ground with one accent. They are defaults, not house
  # style: a course that wants its own sets card: in its own course.yml.
  card   <- course$card %||% list()
  ink    <- card$ink    %||% "#0f1f33"
  paper  <- card$paper  %||% "#f4f6f8"
  accent <- card$accent %||% "#4a9eff"
  muted  <- card$muted  %||% "#6d8bb0"

  subject <- toupper(course$code %||% "COURSE")
  title   <- course$title %||% "Untitled Course"
  # Wrap at the last space. One line of a two-word title at this width would
  # have to be about eleven pixels tall to fit, which is unreadable.
  title <- sub(" ([^ ]+)$", "\n\\1", title)

  ss <- as.integer(supersample)
  px <- function(final) final * ss          # a final-size length, in canvas px
  tx <- function(final) px(final) / 12      # cex, against the 12pt base at res 72

  # A downward relationship with visible spread. Decoration, not data: it says
  # "this course is quantitative" at a size where nothing else can.
  set.seed(seed)
  n <- 26L
  x <- stats::runif(n, 1.6, 5.4)
  y <- 37 - 5.34 * x + stats::rnorm(n, 0, 2.0)
  fit  <- stats::lm(y ~ x)
  endx <- range(x)
  endy <- stats::predict(fit, data.frame(x = endx))

  grDevices::png(out, width = width * ss, height = height * ss, res = 72,
                 bg = ink, type = "cairo")
  on.exit(grDevices::dev.off(), add = TRUE)

  grid::grid.newpage()
  grid::grid.rect(gp = grid::gpar(fill = ink, col = NA))

  # The plot sits right of the type. Its left edge is set by the widest line of
  # type, which is the course code at title size, not by taste.
  pad <- function(v, f = 0.08) range(v) + c(-1, 1) * diff(range(v)) * f
  grid::pushViewport(grid::viewport(x = 0.775, y = 0.50, width = 0.40, height = 0.76,
                                    xscale = pad(x), yscale = pad(y)))
  grid::grid.points(grid::unit(x, "native"), grid::unit(y, "native"),
                    pch = 16, size = grid::unit(px(3.6), "bigpts"),
                    gp = grid::gpar(col = muted))
  grid::grid.lines(grid::unit(endx, "native"), grid::unit(endy, "native"),
                   gp = grid::gpar(col = accent, lwd = px(1.6), lineend = "round"))
  grid::popViewport()

  grid::grid.text(subject, x = 0.07, y = 0.775, just = c("left", "centre"),
                  gp = grid::gpar(col = accent, fontfamily = "Helvetica Neue",
                                  fontface = "bold", cex = tx(23)))

  # A hairline rule, the only ornament. It separates code from title without a
  # box, which would read as clutter at this size.
  grid::grid.lines(x = grid::unit(c(0.07, 0.155), "npc"),
                   y = grid::unit(0.645, "npc"),
                   gp = grid::gpar(col = accent, lwd = px(2), lineend = "butt"))

  grid::grid.text(title, x = 0.07, y = 0.375, just = c("left", "centre"),
                  gp = grid::gpar(col = paper, fontfamily = "Helvetica Neue",
                                  fontface = "bold", cex = tx(23), lineheight = 0.95))

  grDevices::dev.off()
  on.exit()

  if (ss > 1L) {
    img <- magick::image_read(out)
    img <- magick::image_resize(img, paste0(width, "x", height, "!"), filter = "Lanczos")
    magick::image_write(img, out, format = "png")
  }

  invisible(out)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
