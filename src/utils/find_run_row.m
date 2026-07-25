function row = find_run_row(runs_description, run_id)
%FIND_RUN_ROW  Row index of a RunID in the Runs-description table.
%
%   row = find_run_row(runs_description, run_id)
%
% Depending on how Runs-description.xlsx is saved, readtable returns the
% RunID column either as numbers or as text. This helper accepts both, so
% the pipeline keeps working after the spreadsheet is edited in Excel.
%
% run_id may be numeric (601) or text ("601" / '601').
%
% Errors if the RunID is absent or appears more than once.

ids = runs_description.RunID;

if isnumeric(run_id)
    run_id_num  = run_id;
    run_id_text = num2str(run_id);
else
    run_id_text = char(run_id);
    run_id_num  = str2double(run_id_text);
end

if isnumeric(ids)
    match = (ids == run_id_num);
else
    % cellstr or string array
    match = strcmp(string(ids), string(run_id_text));
end

row = find(match);

if isempty(row)
    error('find_run_row:notFound', ...
        'RunID %s not found in the Runs-description table.', run_id_text);
elseif numel(row) > 1
    error('find_run_row:duplicate', ...
        'RunID %s appears %d times in the Runs-description table.', ...
        run_id_text, numel(row));
end

end
