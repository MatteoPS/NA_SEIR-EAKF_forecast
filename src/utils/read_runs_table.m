function runs_description = read_runs_table(paths)
%READ_RUNS_TABLE  Read config/Runs-description.xlsx the same way everywhere.
%
%   runs_description = read_runs_table(paths)
%
% Header is row 1, data starts at row 2. RunIDtext is forced to string so
% that zero-padded IDs ("001") survive the import; RunID is left as detected
% (see FIND_RUN_ROW, which copes with it being numeric or text).

opts = detectImportOptions(paths.runs_description);
opts.DataRange = 'A2';
if ismember('RunIDtext', opts.VariableNames)
    opts = setvartype(opts, 'RunIDtext', 'string');
end
runs_description = readtable(paths.runs_description, opts);

end
