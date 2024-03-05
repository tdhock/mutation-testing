library(data.table)
pandas.repo <- normalizePath("pandas")
pandas.module <- file.path(pandas.repo, "pandas")
c.file.vec <- Sys.glob(file.path(pandas.module,"_libs","src","parser","*.c"))
system(paste("find",pandas.module,"-name '*.c' |grep -v vendored|xargs wc -l|sort -n"))
system(paste("find",pandas.module,"-name '*.py'|xargs wc -l|grep -v '^ *0'|sort -n"))
scratch.dir <- "/scratch/th798/mutation-testing"

for(c.file in c.file.vec){
  print(c.file)
  relative.c <- sub(paste0(pandas.repo,"/"), "", c.file)
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
if [ -e ", mutant.c, " ]; then cp ", mutant.c, " ", relative.c, "; fi
conda activate pandas-dev
python -m pip install -v . --no-build-isolation --target=$PYLIB --config-settings editable-verbose=true 
PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas
")
    ## or import pandas; pandas.test()
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

scratch.pandas <- file.path(scratch.dir, "pandas")
JOBID.file.vec <- system(paste("find",scratch.pandas,"-name '*.JOBID'"), intern=TRUE)
JOBID.dt <- nc::capture_first_vec(
  JOBID.file.vec,
  path=list(
    ".*/",
    file=".*?",
    ".JOBID")
)[, fread(path,col.names="job"), by=file]
sacct.arg <- paste0("-j",paste(JOBID.dt$job, collapse=","))
raw.dt <- slurm::sacct_lines(sacct.arg)
code.names <- c("compile|test"=1, import=4, segfault=11)
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
options(width=80)
(wide.dt <- dcast(sacct.join, job + file ~ State_blank + ExitCode, length))

log.glob <- "/scratch/th798/mutation-testing/pandas/_libs/src/parser/io.c.logs/*"
system(paste("grep 'short test summary info'",log.glob),intern=TRUE)
system(paste("grep 'failed,'",log.glob),intern=TRUE)

## FAILED 1:0 means compilation error or test failure as below.
## ============================= short test summary info =============================
## FAILED ../pylib/pandas/tests/config/test_localization.py::test_encoding_detected
## FAILED ../pylib/pandas/tests/indexes/period/test_formats.py::TestPeriodIndexFormat::test_period_non_ascii_fmt[(None, None)]
## = 2 failed, 217345 passed, 6533 skipped, 6933 deselected, 1809 xfailed, 93 xpassed, 23 warnings in 1180.86s (0:19:40) =

## ==================================== FAILURES =====================================
## _____________________________ test_encoding_detected ______________________________

##     def test_encoding_detected():
##         system_locale = os.environ.get("LC_ALL")
##         system_encoding = system_locale.split(".")[-1] if system_locale else "utf-8"
    
## >       assert (
##             codecs.lookup(pd.options.display.encoding).name
##             == codecs.lookup(system_encoding).name
##         )
## E       LookupError: unknown encoding: C

## ../pylib/pandas/tests/config/test_localization.py:153: LookupError
## __________ TestPeriodIndexFormat.test_period_non_ascii_fmt[(None, None)] __________

## self = <pandas.tests.indexes.period.test_formats.TestPeriodIndexFormat object at 0x153e224060e0>
## locale_str = None

##     @pytest.mark.parametrize(
##         "locale_str",
##         [
##             pytest.param(None, id=str(locale.getlocale())),
##             "it_IT.utf8",
##             "it_IT",  # Note: encoding will be 'ISO8859-1'
##             "zh_CN.utf8",
##             "zh_CN",  # Note: encoding will be 'gb2312'
##         ],
##     )
##     def test_period_non_ascii_fmt(self, locale_str):
##         # GH#46468 non-ascii char in input format string leads to wrong output
    
##         # Skip if locale cannot be set
##         if locale_str is not None and not tm.can_set_locale(locale_str, locale.LC_ALL):
##             pytest.skip(f"Skipping as locale '{locale_str}' cannot be set on host.")
    
##         # Change locale temporarily for this test.
##         with tm.set_locale(locale_str, locale.LC_ALL) if locale_str else nullcontext():
##             # Scalar
##             per = pd.Period("2018-03-11 13:00", freq="h")
## >           assert per.strftime("%y é") == "18 é"

## ../pylib/pandas/tests/indexes/period/test_formats.py:308: 
## _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
## period.pyx:2659: in pandas._libs.tslibs.period._Period.strftime
##     ???
## period.pyx:1250: in pandas._libs.tslibs.period.period_format
##     ???
## _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

## >   ???
## E   UnicodeEncodeError: 'locale' codec can't encode character '\xe9' in position 3: encoding error

## util.pxd:190: UnicodeEncodeError
## ================================ warnings summary =================================
## tests/groupby/test_categorical.py::test_basic
##   /tmp/th798/8159179/pandas-mutant/115/pylib/numpy/core/fromnumeric.py:86: FutureWarning: The behavior of DataFrame.sum with axis=None is deprecated, in a future version this will reduce over both axes and return a scalar. To retain the old behavior, pass axis=0 (or do not pass axis)
##     return reduction(axis=axis, out=out, **passkwargs)

## tests/plotting/frame/test_frame.py: 11 warnings
##   /home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/matplotlib/transforms.py:2652: RuntimeWarning: divide by zero encountered in scalar divide
##     x_scale = 1.0 / inw

## tests/plotting/frame/test_frame.py: 11 warnings
##   /home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/matplotlib/transforms.py:2654: RuntimeWarning: invalid value encountered in scalar multiply
##     self._mtx = np.array([[x_scale, 0.0    , (-inl*x_scale)],

## -- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
## -- generated xml file: /tmp/th798/8159179/pandas-mutant/115/pandas/test-data.xml --



## > system("eval \"$(/projects/genomic-ml/projects/mutation-testing/mambaforge/bin/conda shell.bash hook)\" && conda activate pandas-dev && PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' /tmp/th798/8158726/pandas-mutant/5/pylib/pandas")
## ============================== test session starts ==============================
## platform linux -- Python 3.10.13, pytest-8.0.0, pluggy-1.4.0
## PyQt5 5.15.9 -- Qt runtime 5.15.8 -- Qt compiled 5.15.8
## rootdir: /tmp/th798/8158726/pandas-mutant/5/pylib/pandas
## configfile: pyproject.toml
## plugins: cov-4.1.0, xdist-3.5.0, anyio-4.2.0, hypothesis-6.98.2, qt-4.3.1, cython-0.2.1
## collected 232715 items / 6933 deselected / 225782 selected                      
## ...
## ============================ short test summary info ============================
## FAILED ../../../../tmp/th798/8158726/pandas-mutant/5/pylib/pandas/tests/config/test_localization.py::test_encoding_detected
## FAILED ../../../../tmp/th798/8158726/pandas-mutant/5/pylib/pandas/tests/indexes/period/test_formats.py::TestPeriodIndexFormat::test_period_non_ascii_fmt[(None, None)]
## FAILED ../../../../tmp/th798/8158726/pandas-mutant/5/pylib/pandas/tests/io/formats/style/test_html.py::test_html_template_extends_options
## = 3 failed, 217344 passed, 6533 skipped, 6933 deselected, 1809 xfailed, 93 xpassed, 23 warnings in 3735.90s (1:02:15) =



## (pandas-dev) th798@cn59:~$ PYTHONPATH=$PYLIB python
## Python 3.10.13 | packaged by conda-forge | (main, Dec 23 2023, 15:36:39) [GCC 12.3.0] on linux
## Type "help", "copyright", "credits" or "license" for more information.
## >>> import pandas
## >>> pandas.test()
## running: pytest -m not slow and not network and not db /tmp/th798/8158726/pandas-mutant/5/pylib/pandas
## ============================== test session starts ==============================
## platform linux -- Python 3.10.13, pytest-8.0.0, pluggy-1.4.0
## PyQt5 5.15.9 -- Qt runtime 5.15.8 -- Qt compiled 5.15.8
## rootdir: /tmp/th798/8158726/pandas-mutant/5/pylib/pandas
## configfile: pyproject.toml
## plugins: cov-4.1.0, xdist-3.5.0, anyio-4.2.0, hypothesis-6.98.2, qt-4.3.1, cython-0.2.1
## collected 232715 items / 4159 deselected / 228556 selected                      






## FAILED 4:0 means ImportError when loading tests.
## Successfully installed numpy-1.26.4 pandas-2.2.1+0.gbdc79c146c.dirty python-dateutil-2.9.0.post0 pytz-2024.1 six-1.16.0 tzdata-2024.1
## ImportError while loading conftest '/tmp/th798/8159207/pandas-mutant/143/pylib/pandas/conftest.py'.
## ../pylib/pandas/__init__.py:49: in <module>
##     from pandas.core.api import (
## ../pylib/pandas/core/api.py:1: in <module>
##     from pandas._libs import (
## ../pylib/pandas/_libs/__init__.py:16: in <module>
##     import pandas._libs.pandas_parser  # isort: skip # type: ignore[reportUnusedImport]
## E   ImportError: /tmp/th798/8159207/pandas-mutant/143/pylib/pandas/_libs/pandas_parser.cpython-310-x86_64-linux-gnu.so: undefined symbol: del_rd_source

## FAILED 11:0 means segfault in tests, which is encouraging because tests actually run.
## ../pylib/pandas/tests/extension/decimal/test_decimal.py ssssssssssssssssssssssssssssssssssss....................................x.................................................................................................................................................................................................................................................................................Fatal Python error: Segmentation fault
## Current thread 0x000014b159c5f740 (most recent call first):
##                  File "/tmp/th798/8159319/pandas-mutant/255/pylib/pandas/io/parsers/c_parser_wrapper.py", line
## ...
## /var/spool/slurm/slurmd/job8159319/slurm_script: line 22: 3893095 Segmentation fault      (core dumped) PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas

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
