"src/base-prerelease/R-devel.tar.gz"
cran.url <- "http://cloud.r-project.org/"
path.tar.gz <- "src/base/R-4/R-4.3.2.tar.gz"
R.tar.gz <- basename(path.tar.gz)
R.dir <- sub(".tar.gz", "", R.tar.gz)
R.src.prefix <- "src"
dir.create(R.src.prefix, showWarnings = FALSE)
local.tar.gz <- file.path(R.src.prefix, R.tar.gz)
if(!file.exists(local.tar.gz)){
  R.url <- paste0(cran.url, path.tar.gz)
  download.file(R.url, local.tar.gz)
}
R.ver.path <- normalizePath(
  file.path(R.src.prefix, R.dir),
  mustWork = FALSE)
if(!dir.exists(R.ver.path)){
  system(paste("cd src && tar xf", R.tar.gz))
}

library(data.table)
(lines.dt <- data.table(glob=c(
  "src/library/*/src/*.[fc]",
  "src/library/*/R/*.R",
  "src/*/*.[fc]"
))[, {
  wc.cmd <- paste(
    "wc -l",
    file.path(R.ver.path, glob),
    "|grep -v total$")
  fread(cmd=wc.cmd, col.names=c("lines","path"))
}, by=glob
][, suffix := sub(".*[.]", "", path)][])
lines.dt[, .(
  files=.N,
  lines=sum(lines)
), by=suffix]

