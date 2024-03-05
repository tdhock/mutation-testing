library(data.table)
module.dir <- normalizePath("pandas/pandas")
c.file.vec <- Sys.glob(file.path(module.dir,"_libs","src","parser","*.c"))
system(paste("find",module.dir,"-name '*.c' |grep -v vendored|xargs wc -l|sort -n"))
system(paste("find",module.dir,"-name '*.py'|xargs wc -l|grep -v '^ *0'|sort -n"))
scratch.dir <- "/scratch/th798/mutation-testing"

for(c.file in c.file.vec){
  print(c.file)
  relative.c <- sub(paste0(module.dir,"/"), "", c.file)
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
#SBATCH --time=2:00:00
#SBATCH --mem=4GB
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
if [ -e ", mutant.c, " ]; then cp ", mutant.c, " pandas/", relative.c, "; fi
conda activate pandas-dev
##python -m pip install -ve . --no-build-isolation --config-settings editable-verbose=true
python -m pip install -v . --no-build-isolation --target=$PYLIB --config-settings editable-verbose=true 
PYTHONPATH=$PYLIB PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' pandas
## https://docs.pytest.org/en/7.1.x/getting-started.html
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

## https://pip.pypa.io/en/stable/cli/pip_install/#obtaining-information-about-what-was-installed
## The install command has a --report option that will generate a JSON report of what pip has installed.
## -e, --editable <path/url> Install a project in editable mode (i.e. setuptools “develop mode”) from a local project path or a VCS url. https://setuptools.pypa.io/en/latest/userguide/development_mode.html https://pip.pypa.io/en/stable/topics/local-project-installs/#editable-installs
## --no-build-isolation Disable isolation when building a modern source distribution. Build dependencies specified by PEP 518 must be already installed if this option is used.
## -C, --config-settings <settings> Configuration settings to be passed to the PEP 517 build backend. Settings take the form KEY=VALUE. Use multiple --config-settings options to pass multiple keys to the backend.
## https://pip.pypa.io/en/stable/cli/pip_uninstall/

## Installing collected packages: pandas
##   Attempting uninstall: pandas
##     Found existing installation: pandas 2.2.1+0.gbdc79c146c.dirty
##     Uninstalling pandas-2.2.1+0.gbdc79c146c.dirty:
##       Removing file or directory /projects/genomic-ml/projects/mutation-testing/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/__pycache__/_pandas_editable_loader.cpython-310.pyc
##       Removing file or directory /projects/genomic-ml/projects/mutation-testing/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pandas_editable_loader.py
##       Removing file or directory /projects/genomic-ml/projects/mutation-testing/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pandas-2.2.1+0.gbdc79c146c.dirty.dist-info/
##       Removing file or directory /projects/genomic-ml/projects/mutation-testing/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pandas-editable.pth
##       Successfully uninstalled pandas-2.2.1+0.gbdc79c146c.dirty
## Successfully installed pandas-2.2.1
## (pandas-dev) th798@cn105:~/genomic-ml/projects/mutation-testing/pandas((HEAD detached at v2.2.1))$ python 
## Python 3.10.13 | packaged by conda-forge | (main, Dec 23 2023, 15:36:39) [GCC 12.3.0] on linux
## Type "help", "copyright", "credits" or "license" for more information.
## >>> import pandas
## + /home/th798/mambaforge/envs/pandas-dev/bin/ninja
## [1/1] Generating write_version_file with a custom command
## >>> pandas
## <module 'pandas' from '/projects/genomic-ml/projects/mutation-testing/pandas/pandas/__init__.py'>
## >>> 

JOBID.glob <- file.path(scratch.dir, "_libs/src/parser/*JOBID")
JOBID.dt <- nc::capture_first_glob(
  JOBID.glob,
  scratch.dir,
  "/_libs/src/parser/",
  file=".*?",
  ".JOBID",
  READ=function(f)fread(f,col.names="job"))
sacct.arg <- paste0("-j",paste(JOBID.dt$job, collapse=","))
raw.dt <- slurm::sacct_lines(sacct.arg)
sacct.dt <- slurm::sacct_tasks(raw.dt)[JOBID.dt, on="job"]
options(width=150)
(wide.dt <- dcast(sacct.dt, job + file ~ State_blank + ExitCode_blank, length))

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
