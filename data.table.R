library(data.table)
system(paste("cd",tempdir(),"&& git clone ~/R/data.table"))
Rlib <- file.path(tempdir(), "Rlib")
clone.dir <- file.path(tempdir(), "data.table")
system(paste("cd",clone.dir,"&& git checkout 1.15.0"))
src.file.vec.c <- Sys.glob(file.path(clone.dir,"src","*.c"))
src.file.vec.R <- Sys.glob(file.path(clone.dir,"R","*.R"))
src.file.vec <- c(src.file.vec.R, src.file.vec.c)
scratch.dir <- "/scratch/th798/mutation-testing"
gcc.flags <- paste(
  "-fsyntax-only -Werror",
  "-I/home/th798/lib64/R/include",
  "-I/home/th798/.conda/envs/emacs1/include",
  "-I/home/th798/include")
## https://app.codecov.io/gh/rdatatable/data.table/tree/master/src shows that coverage is computed for lots of C code files.
## https://github.com/Rdatatable/data.table/blob/master/.github/workflows/test-coverage.yaml says covr::codecov() is used to compute and upload coverage.
if(file.exists("data.table.1.15.0.coverage.rds")){
  cov.res <- readRDS("data.table.1.15.0.coverage.rds")
}else{
  cov.res <- covr::package_coverage(clone.dir)
  saveRDS(cov.res, "data.table.1.15.0.coverage.rds")
}
tally.df <- covr::tally_coverage(cov.res, "line")
## Table with one row per line that could be covered (or not) -- these
## are typically lines in functions. Some lines, such as 1-10 in
## AllS4.R, are always executed, when the package is loaded, so those
## lines do not appear as rows in this table.
(tally.dt <- data.table(
  tally.df
)[
, file := sub(".*/", "", filename)
][])
(tally.out <- tally.dt[, .(file, line, coverage=value)])
fwrite(tally.out, "data.table.coverage.csv")
covered.dt <- tally.dt[0<value]#covered lines.

src.file <- "/tmp/th798/9309543/Rtmp7GmkM5/data.table/src/frank.c"
line.count.dt.list <- list()
for(src.file in src.file.vec){
  print(src.file)
  relative.c <- sub(paste0(tempdir(),"/"), "", src.file)
  out.dir <- file.path(
    scratch.dir,
    relative.c)
  src.is.R <- grepl("R$", src.file)
  test.cmd <- if(src.is.R){
    paste0("R -e 'parse(\"", src.file, "\")'")
  }else{
    paste("gcc",src.file,gcc.flags)
  }
  dir.JOBID <- paste0(out.dir, ".JOBID")
  if(!file.exists(dir.JOBID)){
    mutate.out <- paste0(out.dir,".mutate.out")
    (mutate.cmd <- paste(
      'mkdir -p',out.dir,';',
      'cd',tempdir(),';',
      'eval "$(/home/th798/mambaforge/bin/conda shell.bash hook)";',
      'conda activate pandas-dev;',
      'mutate',src.file,
      '--cmd', shQuote(test.cmd),
      '--mutantDir',out.dir,
      "|tee",mutate.out))
    cat(mutate.cmd)
    system(mutate.cmd)
    mutant.vec <- Sys.glob(file.path(out.dir,"*"))
    mutant.file <- mutant.vec[1]
    logs.dir <- paste0(dirname(mutant.file),".logs")
    dir.create(logs.dir, showWarnings = FALSE)
    suffix <- if(src.is.R)"R" else "c"
    s <- function(num,ext)paste0(num,".",ext)
    s.end <- paste0(suffix,"$")
    log.txt <- file.path(logs.dir, sub(s(0,s.end), s("%a",suffix), basename(mutant.file)))
    mutant.c <- file.path(
      out.dir,
      sub(s("0",s.end), s("$SLURM_ARRAY_TASK_ID",suffix), basename(mutant.file)))
    job.name <- basename(sub(".mutant.0.[cR]", "", mutant.file))
    ## success runtime is less than 5 min, memory usage is less than
    ## 1GB, so these --time and --mem limits are very generous.
    run_one_contents = paste0("#!/bin/bash
#SBATCH --array=0-", length(mutant.vec), "
#SBATCH --time=1:00:00
#SBATCH --mem=4GB
#SBATCH --cpus-per-task=1
#SBATCH --output=", log.txt, "
#SBATCH --error=", log.txt, "
#SBATCH --job-name=", job.name, "
set -o errexit
unset LC_ADDRESS LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME LC_CTYPE LC_MESSAGES LC_ALL
cd $TMPDIR
mkdir -p data.table-mutant/$SLURM_ARRAY_TASK_ID
cd data.table-mutant/$SLURM_ARRAY_TASK_ID
rm -rf data.table
git clone ~/R/data.table
cd data.table
git checkout 1.15.0
cd ..
if [ -e ", mutant.c, " ]; then cp ", mutant.c, " ", relative.c, "; fi
R CMD build data.table
R CMD check data.table_1.15.0.tar.gz
")
    run_one_sh = paste0(out.dir, ".sh")
    writeLines(run_one_contents, run_one_sh)
    cat(
      "Try a test run:\nSLURM_ARRAY_TASK_ID=", length(mutant.vec),
      " bash ", run_one_sh, "\n", sep="")
    sbatch.cmd <- paste("sbatch", run_one_sh)
    sbatch.out <- system(sbatch.cmd, intern=TRUE)
    JOBID <- gsub("[^0-9]", "", sbatch.out)
    if(is.finite(as.integer(JOBID))){
      cat(JOBID, "\n", file=dir.JOBID)
    }else{
      stop(JOBID)
    }
  }
  cloc.dt <- suppressWarnings({
    fread(cmd=paste("cloc/cloc-2.00/cloc --csv",src.file), drop=6)
  })
  line.count.dt.list[[src.file]] <- data.table(
    file=sub(".*/", "", src.file),
    cloc=cloc.dt[language=="SUM", .(blank,comment,code)],
    lines=length(readLines(src.file)))
}
(line.count.dt <- rbindlist(line.count.dt.list))
fwrite(line.count.dt, "data.table.lines.csv")

JOBID.glob <- file.path(scratch.dir, "data.table/*/*JOBID")
JOBID.vec <- Sys.glob(JOBID.glob)
unlink(JOBID.vec[file.size(JOBID.vec)==2])
subdir.file.pattern <- list(
  ".*?",
  "/",
  file=".*?")
JOBID.dt <- nc::capture_first_glob(
  JOBID.glob,
  scratch.dir,
  "/data.table/",
  subdir.file.pattern,
  ".JOBID",
  READ=function(f)fread(f,col.names="job"))
sacct.arg <- paste0("-j",paste(JOBID.dt$job, collapse=","))
raw.dt <- slurm::sacct_lines(sacct.arg)
sacct.dt <- slurm::sacct_tasks(raw.dt)[JOBID.dt, on="job"]
dcast(sacct.dt, job + file ~ State_blank + ExitCode_blank, median, value.var="megabytes")
sacct.dt[State_blank=="OUT_OF_MEMORY"]
sacct.dt[State_blank=="RUNNING"]
sacct.dt[State_blank=="COMPLETED"][order(Elapsed)]
options(width=160)
sacct.dt[, .SD[which.max(task)], by=.(job,file)]#supposed to complete/succeed
(wide.dt <- dcast(sacct.dt, job + file ~ State_blank + ExitCode_batch, length))
fwrite(wide.dt, "data.table.jobs.csv")

out.lines <- fread("cat /scratch/th798/mutation-testing/data.table/*/*.mutate.out",sep="\n",header=FALSE)[[1]]
write.lines <- grep("VALID [written to", out.lines, value=TRUE, fixed=TRUE)
suffix.pattern <- list(
  "[.]",
  "[cR]")
file.pattern <- list(
  "[.]{3}VALID [[]written to ",
  ".*/",
  subdir.file.pattern,
  "/.*?",
  task="[0-9]+", as.integer,
  suffix.pattern
)
write.dt <- nc::capture_first_vec(write.lines, file.pattern)
mutant.dt <- nc::capture_all_str(
  out.lines,
  "\nPROCESSING MUTANT: ",
  line="[0-9]+", as.integer,
  ": +",
  original=".*?",
  " +==> +",
  mutated="(?:\n(?!PROCESSING)|.)*?",
  file.pattern)
mutant.dt[1]
stopifnot(nrow(mutant.dt)==nrow(write.dt))
stopifnot(nrow(mutant.dt[grepl("INVALID", mutated)])==0)
dim(mutant.dt)

msg.ord <- c("ERROR","WARNING","NOTE")
msg_count_str <- function(DT){
  bad.counts <- DT[, .(checks=.N), by=msg][msg.ord, on="msg", nomatch=0L]
  count.vec <- bad.counts[, sprintf("%d %s%s", checks, msg, ifelse(checks!=1, "s", ""))]
  paste(count.vec, collapse=", ")
}

if(file.exists("data.table.status.csv")){
  Status.dt <- fread("data.table.status.csv")
}else{
  log.dir.vec <- Sys.glob(file.path(scratch.dir, "data.table", "*", "*.logs"))
  Status.lines.list <- list()
  for(log.dir.i in seq_along(log.dir.vec)){
    log.dir <- log.dir.vec[[log.dir.i]]
    cat(sprintf("%4d / %4d dirs %s\n", log.dir.i, length(log.dir.vec), log.dir))
    Status.lines.list[[log.dir.i]] <- system(paste(
      "grep '^Status:'",
      file.path(log.dir, "*")
    ), intern=TRUE)
  }
  Status.dt <- nc::capture_first_vec(
    unlist(Status.lines.list),
    ".*/",
    subdir.file.pattern,
    "[.]logs/.*?",
    task="[0-9]+", as.integer,
    suffix.pattern,
    ":",
    nc::field("Status", ": ", ".*"))
  Status.dt[, ExitCode := NA_character_]
  indices.todo <- Status.dt[,which(is.na(ExitCode))]
  for(Status.i in indices.todo){
    cat(sprintf("%4d / %4d logs\n", Status.i, nrow(Status.dt)))
    Status.row <- Status.dt[Status.i]
    rel.path <- file.path(
      if(grepl("R$", Status.row$file))"R" else "src",
      paste0(Status.row$file, ".logs"))
    mutant.path <- file.path(
      scratch.dir, "data.table", rel.path,
      sub("([^.]*)$", paste0("mutant.", Status.row$task, ".\\1"), Status.row$file))
    some.lines <- system(paste("grep -v '[0-9]*:'", mutant.path),intern=TRUE)
    msg.dt <- nc::capture_all_str(
      some.lines,
      "[*] ",
      nc::field("checking", " ", '.*'),
      " [.]{3}",
      "(?:.*\n(?![*]))*",
      " ",
      msg="[A-Z]+",
      "\n")
    bad.dt <- msg.dt[msg%in%msg.ord]
    parsed.status <- msg_count_str(bad.dt)
    bad.vec <- bad.dt[, paste0(msg,":",checking)]
    stopifnot(identical(Status.row$Status, parsed.status))
    if(FALSE){
      parsed.status
      Status.row$Status
      cat(readLines(mutant.path),sep="\n")
    }
    Status.dt[Status.i, ExitCode := paste(bad.vec, collapse=", ")]
  }
  fwrite(Status.dt, "data.table.status.csv")
}

nrow(mutant.dt)
nrow(Status.dt)
nrow(sacct.dt)
nrow(tally.out)

on.vec <- c("file","task")
join.dt <- tally.out[
  mutant.dt[
    Status.dt[sacct.dt, on=on.vec],
    on=on.vec],
  on=.(file,line)]
nrow(join.dt)

## covered lines which were mutated but still passed tests.
join.dt[ExitCode=="NOTE:installed package size" & 0<coverage & !is.na(line)]

join.dt[is.na(line)]
length(JOBID.vec)
join.dt[State_blank=="COMPLETED", table(Status)]
comp.dt <- join.dt[State_blank=="COMPLETED"]
for(comp.i in 1:nrow(comp.dt)){
  comp.row <- comp.dt[comp.i]
  comp.row[, cat(sprintf("##### %s line %s\n%s\n%s\n\n", file, line, original, mutated))]
}
fwrite(join.dt, "data.table.mutant.results.csv")
note1 <- join.dt[Status=="1 NOTE"]
completed <- join.dt[State_blank=="COMPLETED"]
nrow(join.dt[State_batch=="COMPLETED"])
nrow(join.dt[State_blank=="COMPLETED"])
nrow(join.dt[Status=="1 NOTE"])
note1[!completed, on=.(task,file)]
completed[!note1, on=.(task,file)]
join.dt[Status!="1 NOTE", table(Status)]

failed.vec <- system("grep 'package installation failed' /scratch/th798/mutation-testing/data.table/src/wrappers.c.logs/*", intern=TRUE)
failed.dt <- nc::capture_first_vec(
  failed.vec,
  file=".*?",
  ":",
  msg=".*")
failed.dt[, .(count=.N), by=file][order(count)]

## > analyze_mutants <filename of file being mutated> "<shell command to run tests>" --timeout <how long tests should take to run, maximum, plus a modest additional factor for variance> – I often add a five minute factor for long-running test suites
## --prefix <arg> added to that stores the results in files named <arg>.killed.txt and <arg>.notkilled.txt
## mutate and analyze_mutants can take a --mutantDir <dir> parameter (expects dir to exist) to put generated mutants in a directory, and --sourceDir if you need to run analyze_mutants from another directory specifies where the file to be mutated is
## When you analyze_mutants, you need to force a (partial?) rebuild of pandas.  Is there a way to install it --develop so changes to in-place python files are made automatically?  Then it's just C files that need to force rebuild...
