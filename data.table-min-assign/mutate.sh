eval "$(/home/th798/mambaforge/bin/conda shell.bash hook)"
conda activate pandas-dev
mutate data.table-min-assign.c --cmd 'gcc data.table-min-assign.c -fsyntax-only -Werror' |tee mutate.out
