system("tar xf results-2024-03-27.tgz")

library(data.table)
data.list <- list()
for(data.type in c("lines", "mutant.results")){
  dt.list <- list()
  for(software in c("pandas", "data.table")){
    f <- file.path(
      "results-2024-03-27",
      paste0(software, ".", data.type, ".csv"))
    dt.list[[software]] <- data.table(software, fread(f))
  }
  data.list[[data.type]] <- rbindlist(dt.list, use.names=TRUE)
}
with(data.list, lines[!mutant.results, on="file"])
with(data.list, mutant.results[!lines, on="file"])
data.list$mutant[, .(software, file, line)]
data.list$lines

data.list$mutant[is.na(line), table(ExitCode)]
passing.codes <- c("NOTE:installed package size", "0:0")
mutants <- data.list$mutant[!is.na(line)]
mutant.counts <- mutants[, .(
  n.mutants=.N,
  n.passing=sum(ExitCode %in% passing.codes)
), by=.(software, file, line)
][
, `:=`(
  passing = fcase(
    n.mutants==n.passing, "all",
    n.passing==0, "none",
    default="some"),
  pass.prop=n.passing/n.mutants
)
][]
line.counts <- mutant.counts[, .(
  mutated.lines=.N,
  n.mutants=sum(n.mutants),
  n.passing=sum(n.passing),
  ## if some mutants pass, that is a bad line. good if none pass (all fail).
  n.all=sum(passing=="all"),
  n.some=sum(passing=="some"),
  n.none=sum(passing=="none")
), by=.(software, file)]
line.dt <- line.counts[
  data.list$lines, on=.(software,file)
][
  is.na(mutated.lines), `:=`(
    mutated.lines=0,
    n.mutants=0,
    n.passing=0,
    n.all=0,
    n.some=0,
    n.none=0)
][
, type := sub(".*[.]", "", file)
]
out.dt <- line.dt[, .(
  files=.N,
  lines=sum(lines),
  mutated=sum(mutated.lines),
  "mutated%"=sprintf("%.1f", sum(mutated.lines)/sum(lines)),
  "MPL"=sprintf("%.1f", sum(n.mutants)/sum(mutated.lines)),#mutants per line
  ## all.pass=sum(n.all),
  ## some.pass=sum(n.some),
  ## none.pass=sum(n.none),
  linesOK=sum(n.none),
  "lineOK%"=sprintf("%.1f", 100*sum(n.none)/sum(mutated.lines)),
  mutants=sum(n.mutants),
  ##total.passing=sum(n.passing),
  ##percent.passing=100*sum(n.passing)/sum(n.mutants)
  fails=sum(n.mutants)-sum(n.passing)
), by=.(software, type)
][
, "fail%" := sprintf("%.1f", 100*fails/mutants)
][]
library(xtable)
xt <- xtable(out.dt)
print(xt, type="latex", floating=FALSE)
