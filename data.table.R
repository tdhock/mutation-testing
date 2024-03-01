library(data.table)
system(paste("cd",tempdir(),"&& git clone ~/R/data.table"))
clone.dir <- file.path(tempdir(), "data.table")
system(paste("cd",clone.dir,"&& git checkout 1.15.0"))
c.file.vec <- Sys.glob(file.path(clone.dir,"src","*.c"))
scratch.dir <- "/scratch/th798/mutation-testing"

for(c.file in c.file.vec){
  print(c.file)
  relative.c <- sub(paste0(tempdir(),"/"), "", c.file)
  out.dir <- file.path(
    scratch.dir,
    relative.c)
  dir.JOBID <- paste0(out.dir, ".JOBID")
  if(!file.exists(dir.JOBID)){
    system(paste(
      'mkdir -p',out.dir,';',
      'cd',out.dir,';',
      'eval "$(/home/th798/mambaforge/bin/conda shell.bash hook)";',
      'conda activate pandas-dev;',
      'mutate',c.file))
    mutant.vec <- Sys.glob(file.path(out.dir,"*"))
    mutant.file <- mutant.vec[1]
    logs.dir <- paste0(dirname(mutant.file),".logs")
    dir.create(logs.dir, showWarnings = FALSE)
    log.txt <- file.path(logs.dir, sub("0.c$", "%a.c", basename(mutant.file)))
    mutant.c <- file.path(
      out.dir,
      sub("0.c$", "$SLURM_ARRAY_TASK_ID.c", basename(mutant.file)))
    job.name <- basename(sub(".mutant.0.c", "", mutant.file))
    run_one_contents = paste0("#!/bin/bash
#SBATCH --array=0-", length(mutant.vec), "
#SBATCH --time=0:10:00
#SBATCH --mem=2GB
#SBATCH --cpus-per-task=1
#SBATCH --output=", log.txt, "
#SBATCH --error=", log.txt, "
#SBATCH --job-name=", job.name, "
set -o errexit
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
      "Try a test run:\nSLURM_ARRAY_TASK_ID=1",
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
}

JOBID.glob <- file.path(scratch.dir, "data.table/src/*JOBID")
JOBID.vec <- Sys.glob(JOBID.glob)
unlink(JOBID.vec[file.size(JOBID.vec)==2])
JOBID.dt <- nc::capture_first_glob(
  JOBID.glob,
  scratch.dir,
  "/data.table/src/",
  file=".*?",
  ".JOBID",
  READ=function(f)fread(f,col.names="job"))
sacct.arg <- paste0("-j",paste(JOBID.dt$job, collapse=","))
raw.dt <- slurm::sacct_lines(sacct.arg)
sacct.dt <- slurm::sacct_tasks(raw.dt)[JOBID.dt, on="job"]
options(width=150)
wide.dt <- dcast(sacct.dt, job + file ~ State_blank + ExitCode_blank, length)
fwrite(wide.dt, "data.table.jobs.csv")

sacct.dt[State_blank=="OUT_OF_MEMORY"]
sacct.dt[State_blank=="RUNNING"]
sacct.dt[State_blank=="COMPLETED"][order(Elapsed)]

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
