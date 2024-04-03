dir.create("results-figures", showWarnings=FALSE)
results.dir <- "results-2024-04-01"
results.tgz <- paste0(results.dir, ".tgz")
if(!dir.exists(results.dir)){
  system(paste0("scp th798@monsoon.hpc.nau.edu:genomic-ml/projects/mutation-testing/", results.tgz, " ."))
  system(paste("tar xf", results.tgz))
}
library(data.table)
data.list <- list()
for(data.type in c("lines", "mutant.results")){
  dt.list <- list()
  for(software in c("pandas", "data.table")){
    f <- file.path(
      results.dir,
      paste0(software, ".", data.type, ".csv"))
    dt.list[[software]] <- data.table(software, fread(f))
  }
  save.dt <- rbindlist(dt.list, use.names=TRUE)
  save.csv <- file.path(results.dir, paste0(data.type, ".csv"))
  fwrite(save.dt, save.csv)
  data.list[[data.type]] <- save.dt
}
with(data.list, lines[!mutant.results, on="file"])
with(data.list, mutant.results[!lines, on="file"])
data.list$mutant[, .(software, file, line)]
data.list$lines
only.controls <- data.list$mutant.results[, .(results=.N), by=.(software, file)][results==1]
some.mutants <- data.list$mutant[!only.controls, on="file"]

some.mutants[is.na(line), table(ExitCode)]
passing.codes <- c("NOTE:installed package size", "0:0")
some.mutants[
, passed := ExitCode %in% passing.codes & State_blank=="COMPLETED"
][]
cov.but.mut.pass <- some.mutants[passed==TRUE & 0<coverage]
fwrite(cov.but.mut.pass, file.path(results.dir, "cov.but.mut.pass.csv"))
mutant.counts <- some.mutants[!is.na(line), .(
  n.mutants=.N,
  n.passing=sum(passed)
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
  data.list$lines[lines>0], on=.(software,file)
][
  is.na(mutated.lines), `:=`(
    mutated.lines=0,
    n.mutants=0,
    n.passing=0,
    n.all=0,
    n.some=0,
    n.none=0)
][
, `:=`(
  type = sub(".*[.]", "", file)
)
][]
get.out <- function(process){
  process(line.dt)[, {
    Mutated <- sum(mutated.lines)
    Lines <- sum(lines)
    Mutants <- sum(n.mutants)
    LinesOK <- sum(n.none)
    MutantsOK <- sum(n.mutants)-sum(n.passing)
    data.table(
      Files=.N,
      Lines,
      "Lines/File"=Lines/.N,
      Mutated,
      "M%"=100*Mutated/sum(Lines),
      "Mutants/Line"=Mutants/Mutated,#mutants per line
      ## all.pass=sum(n.all),
      ## some.pass=sum(n.some),
      ## none.pass=sum(n.none),
      ## LinesOK,
      ## "LOK%"=100*LinesOK/Mutated,
      Mutants,
      ##total.passing=sum(n.passing),
      ##percent.passing=100*sum(n.passing)/sum(n.mutants)
      MutantsOK,
      "MOK%" = 100*MutantsOK/Mutants
    )
  }, by=.(Software=software,Type=type)]
}
ord.dt <- rbind(
  data.table(Software="pandas", Type=c("py","c","total")),
  data.table(Software="data.table", Type=c("R","c","total")))
out.dt <- rbind(
  get.out(identity),
  get.out(function(DT)data.table(DT)[, type := rep("total",.N)])
)[ord.dt, on=.(Software,Type)]
library(xtable)
xt <- xtable(out.dt, digits=1)
print(
  xt,
  type="latex", floating=FALSE, include.rownames=FALSE,
  format.args = list(big.mark = ","),
  file="results-figures/table-summary.tex")

##TODO time.
library(ggplot2)
some.mutants[, `:=`(
  result = factor(fcase(
    is.na(line), "control",
    passed, "pass",
    Status=="", "error",
    default="fail"),
    c("error","fail","pass","control")),
  minutes = hours*60,
  days=hours/24
)][
, weeks := days/7
][
, years := days/365.25
][]
time_sum <- function(form){
  form.stats <- dcast(
    some.mutants,
    form,
    list(length, median, sum),
    value.var=c("hours","minutes","days","weeks","years")
  )[, time_sum := NA_character_][]
  for(unit.name in c("year","week","day","hour")){
    units <- paste0(unit.name,"s")
    unit.col <- paste0(units,"_sum")
    sum.vec <- form.stats[[unit.col]]
    form.stats[
      sum.vec>1 & is.na(time_sum),
      time_sum := sprintf("%.1f %s", get(unit.col), units)
    ][]
  }
  form.stats
}
software.stats <- time_sum(software ~ .)[, .(
  software,
  time_total=time_sum,
  mutants=paste(days_length, "mutants")
)][
, soft.time.mutants := paste0(software, ", ", mutants, ", ", time_total)
][]
med.color="red"
text.size <- 3
addMeta <- function(DT){
  DT[software.stats, on=.(software)]
}
hist.dt <- addMeta(some.mutants)
result.stats <- addMeta(time_sum(result + software ~ .))
gg <- ggplot()+
  geom_histogram(aes(
    minutes),
    bins=100,
    data=hist.dt)+
  geom_vline(aes(
    xintercept=minutes_median),
    color=med.color,
    data=result.stats)+
  geom_label(aes(
    minutes_median, Inf,
    label=sprintf("median=%.1f minutes", minutes_median)),
    color=med.color,
    alpha=0.5,
    hjust=0,
    size=text.size,
    vjust=1,
    data=result.stats)+
  geom_text(aes(
    ifelse(software=="pandas" & result=="error", 50, 0), Inf,
    label=sprintf("%s mutants\n%s",hours_length,time_sum)),
    size=text.size,
    hjust=0,
    vjust=1,
    data=result.stats)+
  facet_grid(result ~ soft.time.mutants, scales="free")+
  scale_x_log10(
    "Time to build and check (minutes)",
    breaks=c(0.1, 0.2, 0.4, 1, 2, 4, 10, 20, 40, 100, 200))+
  scale_y_continuous(
    "Number of mutants")
png("results-figures/time-hist.png", width=7, height=3, units="in", res=300)
print(gg)
dev.off()
##why is pandas bimodal?

##how many data.table failures include test failures?
dt.failures <- some.mutants[
  software=="data.table" & result=="fail"
][
, tests.failed := grepl("ERROR:tests", ExitCode)
][]
dt.failures[, table(tests.failed)]
(msg.counts <- dt.failures[tests.failed==FALSE, .(
  check=unlist(strsplit(ExitCode, split=", "))
)][, .(count=.N), by=check][order(-count)])
(out.counts <- msg.counts[!check %in% passing.codes])
xt <- xtable(out.counts, digits=1)
print(
  xt,
  type="latex", floating=FALSE, include.rownames=FALSE,
  format.args = list(big.mark = ","),
  file="results-figures/table-useful-checks.tex")

ggplot()+
  geom_point(aes(
    lines, n.mutants, color=software),
    data=line.dt)+
  scale_x_log10()+
  scale_y_log10()

dl.dt <- line.dt[, .(
  files=.N
), by=software][
, label := sprintf("%s\n%d files", software, files)
][line.dt, on="software"]
gg <- ggplot(mapping=aes(    n.mutants, lines))+
  geom_point(aes(
    fill=type,
    color=software),
    shape=21,
    data=line.dt)+
  directlabels::geom_dl(aes(
    label=label),
    method=list(cex=0.7, "smart.grid"),
    data=dl.dt)+
  scale_y_log10(
    "Lines of code per file")+
  scale_x_log10(
    "Mutants generated per file")+
  coord_equal()+
  scale_color_manual(
    values=c(data.table="white", pandas="black"))
png("results-figures/scatter-mutants-lines.png", width=4, height=2.6, units="in", res=300)
print(gg)
dev.off()

ggplot()+
  geom_point(aes(
    n.mutants-n.passing, n.mutants, 
    fill=type,
    color=software),
    shape=21,
    data=line.dt)+
  scale_x_log10(
    "Number of mutants OK per file")+
  scale_y_log10(
    "Mutants generated per file")+
  coord_equal()+
  scale_color_manual(
    values=c(data.table="white", pandas="black"))

line.dt[, OK.percent := 100*(n.mutants-n.passing)/n.mutants]
gg <- ggplot()+
  geom_point(aes(
    OK.percent, lines, 
    fill=type,
    color=software),
    shape=21,
    data=line.dt)+
  scale_x_continuous(
    "Percent of mutants OK per file")+
  scale_y_log10(
    "Lines of code per file")+
  scale_color_manual(
    values=c(data.table="white", pandas="black"))
png("results-figures/scatter-OK-lines.png", width=4, height=2.6, units="in", res=300)
print(gg)
dev.off()