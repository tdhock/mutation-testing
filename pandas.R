library(data.table)
pandas.repo <- normalizePath("pandas")
pandas.module <- file.path(pandas.repo, "pandas")
pandas_libs <- file.path(pandas.module,"_libs")
pandas_include <- file.path(pandas_libs,"include")
c.file.vec <- Sys.glob(file.path(pandas_libs,"src","parser","*.c"))
system(paste("find",pandas.module,"-name '*.c' |grep -v vendored|xargs wc -l|sort -n"))
core.dir <- file.path(pandas.module,"core")
system(paste("find",core.dir,"-name '*.py'|xargs wc -l|grep -v '^ *0'|sort -n"),intern=TRUE)
get_files <- function(where,suffix){
  system(paste0("find ",where," -name '*.", suffix, "'"),intern=TRUE)
}
src.file.vec <- grep("/vendored/", c(get_files(core.dir,"py"),get_files(pandas.module,"c")), value=TRUE, invert=TRUE)
scratch.dir <- "/scratch/th798/mutation-testing"
gcc.flags <- paste0(
  "-fsyntax-only -Werror",
  " -I", pandas_include,
  " -I/home/th798/mambaforge/envs/pandas-dev/include/python3.10")

## coverage is computed here? https://github.com/pandas-dev/pandas/blob/main/ci/run_tests.sh says these args are passed to pytest:
'COVERAGE="-s --cov=pandas --cov-report=xml --cov-append --cov-config=pyproject.toml"'
## https://app.codecov.io/gh/pandas-dev/pandas/tree/main/pandas%2F_libs shows no _src subdir, but _libs/src/parser/io.c is one file that we mutation tested.
cov.commands <- "set -o errexit
TASKDIR=$TMPDIR/pandas-mutant/$SLURM_ARRAY_TASK_ID
PYLIB=$TASKDIR/pylib
mkdir -p $PYLIB
cd $TASKDIR
rm -rf pandas
git clone /projects/genomic-ml/projects/mutation-testing/pandas
eval \"$(/projects/genomic-ml/projects/mutation-testing/mambaforge/bin/conda shell.bash hook)\"
cd pandas
git checkout v2.2.1
conda activate pandas-dev
python -m pip install -v . --no-build-isolation --target=$PYLIB --config-settings editable-verbose=true 
PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas -s --cov=pandas --cov-report=xml --cov-append --cov-config=pyproject.toml"
system(cov.commands)
## Below --cov-report json ?
"PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas -s --cov=pandas --cov-report json:/projects/genomic-ml/projects/mutation-testing/pandas_coverage.json --cov-append --cov-config=pyproject.toml|tee /projects/genomic-ml/projects/mutation-testing/pandas_coverage.out" #->zero coverage
cov.list <- jsonlite::fromJSON("~/genomic-ml/projects/mutation-testing/pandas_coverage.json")
names(cov.list)
str(cov.list)
## below save both xml and json, --cov=$PYLIB/pandas instead of just pandas.
"PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas -s --cov=$PYLIB/pandas --cov-report json:/projects/genomic-ml/projects/mutation-testing/pandas_coverage.json --cov-report xml:/projects/genomic-ml/projects/mutation-testing/pandas_coverage.xml --cov-append --cov-config=pyproject.toml|tee /projects/genomic-ml/projects/mutation-testing/pandas_coverage.out"
system("tail -n 1 pandas_coverage.out")
## 220415 passed, 6469 skipped, 6933 deselected, 1809 xfailed, 93 xpassed, 23 warnings in 4715.40s (1:18:35)
res.dt <- fread("results-2024-03-28/pandas.mutant.results.csv")
## 217403 passed, 6477 skipped, 6933 deselected, 1809 xfailed, 93 xpassed, 23 warnings in 1042.55s (0:17:22)
system("head pandas_coverage.xml")

line.count.dt.list <- list()
for(src.file.i in seq_along(src.file.vec)){
  src.file <- src.file.vec[[src.file.i]]
  cat(sprintf("%4d / %4d files %s\n", src.file.i, length(src.file.vec), src.file))
  relative.src <- sub(paste0(pandas.repo,"/"), "", src.file)
  out.dir <- file.path(
    scratch.dir,
    relative.src)
  suffix <- sub(".*[.]", "", src.file)
  dir.JOBID <- paste0(out.dir, ".JOBID")
  if(!file.exists(dir.JOBID)){
    mutate.out <- paste0(out.dir,".mutate.out")
    (mutate.cmd <- paste(
      'mkdir -p',out.dir,';',
      'cd',tempdir(),';',
      'eval "$(/home/th798/mambaforge/bin/conda shell.bash hook)";',
      'conda activate pandas-dev;',
      'mutate',src.file,
      if(suffix=="c")paste('--cmd', shQuote(paste("gcc",src.file,gcc.flags))),
      '--mutantDir',out.dir,
      "|tee",mutate.out))
    system(mutate.cmd)
    mutant.vec <- Sys.glob(file.path(out.dir,"*"))
    no.suffix <- sub(paste0(suffix,"$"), "", basename(out.dir))
    mutant.file <- file.path(out.dir, paste0(no.suffix, "mutant.0.py"))
    logs.dir <- paste0(out.dir,".logs")
    dir.create(logs.dir, showWarnings = FALSE)
    FIND.TASK <- paste0("0.",suffix,"$")
    log.txt <- file.path(logs.dir, sub(FIND.TASK, paste0("%a.",suffix), basename(mutant.file)))
    mutant.src <- file.path(
      out.dir,
      sub(FIND.TASK, paste0("$SLURM_ARRAY_TASK_ID.",suffix), basename(mutant.file)))
    job.name <- basename(sub(paste0(".mutant.0.",suffix), "", mutant.file))
    run_one_contents = paste0("#!/bin/bash
#SBATCH --array=0-", length(mutant.vec), "
#SBATCH --time=2:00:00
#SBATCH --mem=6GB
#SBATCH --cpus-per-task=1
#SBATCH --output=", log.txt, "
#SBATCH --error=", log.txt, "
#SBATCH --job-name=", job.name, "
set -o errexit
TASKDIR=$TMPDIR/pandas-mutant/$SLURM_ARRAY_TASK_ID
PYLIB=$TASKDIR/pylib
mkdir -p $PYLIB
cd $TASKDIR
rm -rf pandas
git clone /projects/genomic-ml/projects/mutation-testing/pandas
eval \"$(/projects/genomic-ml/projects/mutation-testing/mambaforge/bin/conda shell.bash hook)\"
cd pandas
git checkout v2.2.1
if [ -e ", mutant.src, " ]; then cp ", mutant.src, " ", relative.src, "; fi
conda activate pandas-dev
python -m pip install -v . --no-build-isolation --target=$PYLIB --config-settings editable-verbose=true 
PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas
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
  line.count.dt.list[[src.file.i]] <- data.table(
    file=sub(".*pandas/", "", src.file),
    lines=length(readLines(src.file)))
}
(line.count.dt <- rbindlist(line.count.dt.list))
fwrite(line.count.dt, "pandas.lines.csv")

mutant.count.dt.list <- list()
for(src.file.i in seq_along(src.file.vec)){
  src.file <- src.file.vec[[src.file.i]]
  cat(sprintf("%4d / %4d files %s\n", src.file.i, length(src.file.vec), src.file))
  relative.src <- sub(paste0(pandas.repo,"/"), "", src.file)
  out.dir <- file.path(
    scratch.dir,
    relative.src)
  mutant.vec <- dir(out.dir)
  suffix <- sub(".*[.]", "", src.file)
  dir.JOBID <- paste0(out.dir, ".JOBID")
  mutant.count.dt.list[[src.file.i]] <- data.table(
    relative.src, mutants=length(mutant.vec))
}
(mutant.count.dt <- rbindlist(mutant.count.dt.list))
JOBID.files <- mutant.count.dt[mutants==0, file.path(scratch.dir, paste0(relative.src, '.JOBID'))]
file.exists(JOBID.files)
unlink(JOBID.files)

scratch.pandas <- file.path(scratch.dir, "pandas")
JOBID.file.vec <- system(paste("find",scratch.pandas,"-name '*.JOBID'"), intern=TRUE)
subdir.file.pattern <- list(
  ".*/pandas/",
  file=".*?")  
JOBID.dt <- nc::capture_first_vec(
  JOBID.file.vec,
  path=list(
    subdir.file.pattern,
    ".JOBID")
)[, fread(path,col.names="job"), by=file]
sacct.arg <- paste0("-j",paste(JOBID.dt$job, collapse=","))
raw.dt <- slurm::sacct_lines(sacct.arg)
code.names <- c(
  "compile|test"=1,
  pip=2,
  import=4,
  memory=6,
  bus=7,
  float=8,
  segfault=11)
(code.dt <- data.table(
  ExitCode_blank=paste0(code.names,":0"),
  ExitCode=names(code.names)))
sacct.dt <- slurm::sacct_tasks(
  raw.dt
)[
  JOBID.dt, on="job"
]
sacct.join <- code.dt[
  sacct.dt, on="ExitCode_blank"
][
  is.na(ExitCode), ExitCode := ExitCode_blank
][]
sacct.join[, .SD[which.max(task)], keyby=.(job,file)][State_blank != "COMPLETED"]
options(width=80)
(wide.dt <- dcast(sacct.join, job + file ~ State_blank + ExitCode, length))

dcast(sacct.join, job + file + State_blank + ExitCode ~., list(min, median, max), value.var="megabytes")[order(megabytes_median)]
sacct.join[order(-megabytes)][!is.na(megabytes)][1:100]

log.glob <- "/scratch/th798/mutation-testing/pandas/_libs/src/parser/io.c.logs/*"
system(paste("grep 'short test summary info'",log.glob),intern=TRUE)
system(paste("grep 'failed,'",log.glob),intern=TRUE)

out.file.vec <- sub("JOBID$", "mutate.out", JOBID.file.vec)
cat.out.cmd <- paste("cat", paste(out.file.vec, collapse=" "))
out.lines <- fread(cmd=cat.out.cmd,sep="\n",header=FALSE)[[1]]
write.lines <- grep("VALID [written to", out.lines, value=TRUE, fixed=TRUE)
suffix.pattern <- list(
  "[.]",
  "(?:c|py)")
file.pattern <- list(
  "[.]{3}VALID [[]written to ",
  subdir.file.pattern,
  task="[0-9]+", as.integer,
  suffix.pattern
)
write.dt <- nc::capture_first_vec(write.lines, file.pattern)
mutant.dt <- nc::capture_all_str(
  out.lines,
  "\nPROCESSING MUTANT: ",
  line="[0-9]+",
  ": +",
  original=".*?",
  " +==> +",
  mutated="(?:\n(?!PROCESSING)|.)*?",
  file.pattern)
mutant.dt[1]
stopifnot(nrow(mutant.dt)==nrow(write.dt))
(INVALID <- mutant.dt[grepl("INVALID", mutated)])
dim(mutant.dt)
mutant.dt[, myfile := sub("/[^/]+$", "", file)]

log.dir.vec <- system(paste("find",scratch.pandas,"-name '*.logs'"), intern=TRUE)
Status.lines.list <- list()
for(log.dir.i in seq_along(log.dir.vec)){
  log.dir <- log.dir.vec[[log.dir.i]]
  cat(sprintf("%4d / %4d dirs %s\n", log.dir.i, length(log.dir.vec), log.dir))
  Status.lines.list[[log.dir.i]] <- system(paste(
    "tail -n 1",
    file.path(log.dir, "*")
  ), intern=TRUE)
}
Status.dt <- nc::capture_all_str(
  unlist(Status.lines.list),
  "==> ",
  subdir.file.pattern,
  "[.]logs/.*?",
  task="[0-9]+", as.integer,
  suffix.pattern,
  " <==\n= ",
  Status=".*?",
  " =")


nrow(mutant.dt)
nrow(Status.dt)
nrow(sacct.join)
names(mutant.dt)
names(Status.dt)
names(sacct.join)
on.vec <- c("file","task")
mjoin <- mutant.dt[, .(line, original, mutated, file=myfile, task)]
join.dt <- mjoin[
  Status.dt[sacct.join, on=on.vec],
  on=on.vec]
join.dt[is.na(line)][, .(count=.N), by=.(file)][order(count)]
#pandas/core/indexes/base.py mutant 996 worked
