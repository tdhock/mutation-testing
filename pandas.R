library(data.table)
pandas.repo <- normalizePath("pandas")
pandas.module <- file.path(pandas.repo, "pandas")
pandas_libs <- file.path(pandas.module,"_libs")
pandas_include <- file.path(pandas_libs,"include")
c.file.vec <- Sys.glob(file.path(pandas_libs,"src","parser","*.c"))
system(paste("find",pandas.module,"-name '*.c' |grep -v vendored|xargs wc -l|sort -n"))
core.dir <- file.path(pandas.module,"core")
system(paste("find",core.dir,"-name '*.py'|xargs wc -l|grep -v '^ *0'|sort -n"),intern=TRUE)
scratch.dir <- "/scratch/th798/mutation-testing"
gcc.flags <- paste0(
  "-fsyntax-only -Werror",
  " -I", pandas_include,
  " -I/home/th798/mambaforge/envs/pandas-dev/include/python3.10")

for(c.file in c.file.vec){
  print(c.file)
  relative.c <- sub(paste0(pandas.repo,"/"), "", c.file)
  out.dir <- file.path(
    scratch.dir,
    relative.c)
  dir.JOBID <- paste0(out.dir, ".JOBID")
  if(!file.exists(dir.JOBID)){
    mutate.out <- paste0(out.dir,".mutate.out")
    (mutate.cmd <- paste(
      'mkdir -p',out.dir,';',
      'cd',out.dir,';',
      'eval "$(/home/th798/mambaforge/bin/conda shell.bash hook)";',
      'conda activate pandas-dev;',
      'mutate',c.file,"--cmd 'gcc",c.file,gcc.flags,"' |tee",mutate.out))
    system(mutate.cmd)
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
options(width=80)
(wide.dt <- dcast(sacct.join, job + file ~ State_blank + ExitCode, length))

dcast(sacct.join, job + file + State_blank + ExitCode ~., list(min, median, max), value.var="megabytes")[order(megabytes_median)]
sacct.join[order(-megabytes)][!is.na(megabytes)][1:100]

log.glob <- "/scratch/th798/mutation-testing/pandas/_libs/src/parser/io.c.logs/*"
system(paste("grep 'short test summary info'",log.glob),intern=TRUE)
system(paste("grep 'failed,'",log.glob),intern=TRUE)

## FAILED 6:0 is "memory problem munmap_chunk(): invalid pointer" or "double free or corruption (fasttop)"
## ../pylib/pandas/tests/extension/decimal/test_decimal.py ssssssssssssssssssssssssssssssssssss....................................x.................................................................................................................................................................................................................................................................................double free or corruption (fasttop)
## Fatal Python error: Aborted
## Current thread 0x000014dd2692a740 (most recent call first):
##   File "/tmp/th798/8165455/pandas-mutant/185/pylib/pandas/io/parsers/readers.py", line 1026 in read_csv
##   File "/tmp/th798/8165455/pandas-mutant/185/pylib/pandas/tests/extension/base/io.py", line 35 in test_EA_types
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/python.py", line 193 in pytest_pyfunc_call
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_callers.py", line 102 in _multicall
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_manager.py", line 119 in _hookexec
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_hooks.py", line 501 in __call__
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/python.py", line 1836 in runtest
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 173 in pytest_runtest_call
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_callers.py", line 102 in _multicall
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_manager.py", line 119 in _hookexec
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_hooks.py", line 501 in __call__
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 266 in <lambda>
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 345 in from_call
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 265 in call_runtest_hook
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 226 in call_and_report
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 133 in runtestprotocol
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/runner.py", line 114 in pytest_runtest_protocol
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_callers.py", line 102 in _multicall
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_manager.py", line 119 in _hookexec
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_hooks.py", line 501 in __call__
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/main.py", line 351 in pytest_runtestloop
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_callers.py", line 102 in _multicall
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_manager.py", line 119 in _hookexec
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_hooks.py", line 501 in __call__
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/main.py", line 326 in _main
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/main.py", line 272 in wrap_session
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/main.py", line 319 in pytest_cmdline_main
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_callers.py", line 102 in _multicall
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_manager.py", line 119 in _hookexec
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pluggy/_hooks.py", line 501 in __call__
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/config/__init__.py", line 174 in main
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/_pytest/config/__init__.py", line 197 in console_main
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pytest/__main__.py", line 5 in <module>
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/runpy.py", line 86 in _run_code
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/runpy.py", line 196 in _run_module_as_main
## Extension modules: numpy.core._multiarray_umath, numpy.core._multiarray_tests, numpy.linalg._umath_linalg, numpy.fft._pocketfft_internal, numpy.random._common, numpy.random.bit_generator, numpy.random._bounded_integers, numpy.random._mt19937, numpy.random.mtrand, numpy.random._philox, numpy.random._pcg64, numpy.random._sfc64, numpy.random._generator, pyarrow.lib, pyarrow._hdfsio, pandas._libs.tslibs.ccalendar, pandas._libs.tslibs.np_datetime, pandas._libs.tslibs.dtypes, pandas._libs.tslibs.base, pandas._libs.tslibs.nattype, pandas._libs.tslibs.timezones, pandas._libs.tslibs.fields, pandas._libs.tslibs.timedeltas, pandas._libs.tslibs.tzconversion, pandas._libs.tslibs.timestamps, pandas._libs.properties, pandas._libs.tslibs.offsets, pandas._libs.tslibs.strptime, pandas._libs.tslibs.parsing, pandas._libs.tslibs.conversion, pandas._libs.tslibs.period, pandas._libs.tslibs.vectorized, pandas._libs.ops_dispatch, pandas._libs.missing, pandas._libs.hashtable, pandas._libs.algos, pandas._libs.interval, pandas._libs.lib, pyarrow._compute, pandas._libs.ops, numexpr.interpreter, bottleneck.move, bottleneck.nonreduce, bottleneck.nonreduce_axis, bottleneck.reduce, pandas._libs.hashing, pandas._libs.arrays, pandas._libs.tslib, pandas._libs.sparse, pandas._libs.internals, pandas._libs.indexing, pandas._libs.index, pandas._libs.writers, pandas._libs.join, pandas._libs.window.aggregations, pandas._libs.window.indexers, pandas._libs.reshape, pandas._libs.groupby, pandas._libs.json, pandas._libs.parsers, pandas._libs.testing, zstandard.backend_c, PyQt5.QtCore, PyQt5.QtGui, PyQt5.QtWidgets, PyQt5.QtTest, scipy._lib._ccallback_c, yaml._yaml, numba.core.typeconv._typeconv, numba._helperlib, numba._dynfunc, numba._dispatcher, numba.core.runtime._nrt_python, numba.np.ufunc._internal, numba.experimental.jitclass._box, lxml._elementpath, lxml.etree, openpyxl.utils.cell, openpyxl.worksheet._reader, openpyxl.worksheet._writer, PIL._imaging, markupsafe._speedups, matplotlib._c_internal_utils, matplotlib._path, kiwisolver._cext, matplotlib._image, tables._comp_lzo, tables._comp_bzip2, tables.utilsextension, tables.hdf5extension, tables.linkextension, tables.lrucacheextension, tables.tableextension, tables.indexesextension, pandas._libs.byteswap, pandas._libs.sas, multidict._multidict, yarl._quoting_c, _brotli, aiohttp._helpers, aiohttp._http_writer, aiohttp._http_parser, aiohttp._websocket, frozenlist._frozenlist, _cffi_backend, fastparquet.cencoding, fastparquet.speedups, pyarrow._orc, pyarrow._fs, pyarrow._hdfs, pyarrow._gcsfs, pyarrow._s3fs, pyreadstat._readstat_parser, pyreadstat._readstat_writer, pyreadstat.pyreadstat, sqlalchemy.cyextension.collections, sqlalchemy.cyextension.immutabledict, sqlalchemy.cyextension.processors, sqlalchemy.cyextension.resultproxy, sqlalchemy.cyextension.util, greenlet._greenlet, psutil._psutil_linux, psutil._psutil_posix, scipy.sparse._sparsetools, _csparsetools, scipy.sparse._csparsetools, scipy.linalg._fblas, scipy.linalg._flapack, scipy.linalg.cython_lapack, scipy.linalg._cythonized_array_utils, scipy.linalg._solve_toeplitz, scipy.linalg._flinalg, scipy.linalg._decomp_lu_cython, scipy.linalg._matfuncs_sqrtm_triu, scipy.linalg.cython_blas, scipy.linalg._matfuncs_expm, scipy.linalg._decomp_update, scipy.sparse.linalg._dsolve._superlu, scipy.sparse.linalg._eigen.arpack._arpack, scipy.sparse.csgraph._tools, scipy.sparse.csgraph._shortest_path, scipy.sparse.csgraph._traversal, scipy.sparse.csgraph._min_spanning_tree, scipy.sparse.csgraph._flow, scipy.sparse.csgraph._matching, scipy.sparse.csgraph._reordering, scipy._lib._uarray._uarray, scipy.special._ufuncs_cxx, scipy.special._ufuncs, scipy.special._specfun, scipy.special._comb, scipy.special._ellip_harm_2, scipy.fftpack.convolve (total: 153)
## /var/spool/slurm/slurmd/job8165455/slurm_script: line 22: 2527512 Aborted                 (core dumped) PYTHONHASHSEED=1 python -m pytest -m 'not slow and not db and not network and not clipboard and not single_cpu' $PYLIB/pandas


## FAILED 2:0 is some pip error as below.
##   [106/106] pandas/util
##   Preparing metadata (pyproject.toml): finished with status 'done'
## ERROR: Exception:
## Traceback (most recent call last):
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/cli/base_command.py", line 180, in exc_logging_wrapper
##     status = run_func(*args)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/cli/req_command.py", line 245, in wrapper
##     return func(self, options, args)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/commands/install.py", line 377, in run
##     requirement_set = resolver.resolve(
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/resolution/resolvelib/resolver.py", line 95, in resolve
##     result = self._result = resolver.resolve(
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_vendor/resolvelib/resolvers.py", line 546, in resolve
##     state = resolution.resolve(requirements, max_rounds=max_rounds)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_vendor/resolvelib/resolvers.py", line 427, in resolve
##     failure_causes = self._attempt_to_pin_criterion(name)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_vendor/resolvelib/resolvers.py", line 239, in _attempt_to_pin_criterion
##     criteria = self._get_updated_criteria(candidate)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_vendor/resolvelib/resolvers.py", line 230, in _get_updated_criteria
##     self._add_to_criteria(criteria, requirement, parent=candidate)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_vendor/resolvelib/resolvers.py", line 173, in _add_to_criteria
##     if not criterion.candidates:
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_vendor/resolvelib/structs.py", line 156, in __bool__
##     return bool(self._sequence)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/resolution/resolvelib/found_candidates.py", line 155, in __bool__
##     return any(self)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/resolution/resolvelib/found_candidates.py", line 143, in <genexpr>
##     return (c for c in iterator if id(c) not in self._incompatible_ids)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/resolution/resolvelib/found_candidates.py", line 44, in _iter_built
##     for version, func in infos:
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/resolution/resolvelib/factory.py", line 297, in iter_index_candidate_infos
##     result = self._finder.find_best_candidate(
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/index/package_finder.py", line 890, in find_best_candidate
##     candidates = self.find_all_candidates(project_name)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/index/package_finder.py", line 831, in find_all_candidates
##     page_candidates = list(page_candidates_it)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/index/sources.py", line 194, in page_candidates
##     yield from self._candidates_from_page(self._link)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/index/package_finder.py", line 795, in process_project_url
##     page_links = list(parse_links(index_response))
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/index/collector.py", line 223, in wrapper_wrapper
##     return list(fn(page))
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/site-packages/pip/_internal/index/collector.py", line 236, in parse_links
##     data = json.loads(page.content)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/json/__init__.py", line 346, in loads
##     return _default_decoder.decode(s)
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/json/decoder.py", line 337, in decode
##     obj, end = self.raw_decode(s, idx=_w(s, 0).end())
##   File "/home/th798/mambaforge/envs/pandas-dev/lib/python3.10/json/decoder.py", line 355, in raw_decode
##     raise JSONDecodeError("Expecting value", s, err.value) from None
## json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)


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

## This could be fixed by changing locale from C to utf-8 or just unset LC_ALL
## >>> codecs.lookup("utf-8")
## <codecs.CodecInfo object for encoding utf-8 at 0x1513a57198a0>

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
