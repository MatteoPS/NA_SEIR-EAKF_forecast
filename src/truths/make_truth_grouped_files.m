function make_truth_grouped_files()
%MAKE_TRUTH_GROUPED_FILES  Bundle every synthetic truth into one struct.
%
%   make_truth_grouped_files()
%
% Collects every data/truths/truth_*.mat into a single struct array and saves
% it as data/truths/all_truths_struct.mat, which
% MAKE_TRUTH_STATS_AND_HISTOGRAM then summarises.
%
% Retrieve a field with, e.g.:
%   struct_truth(1).truth_vars.truth_dailyIu_post_rec
%
% See also MAKE_TRUTH, MAKE_TRUTH_STATS_AND_HISTOGRAM.

paths = setup_paths();

truthfileList = dir(fullfile(paths.truths, 'truth_t*.mat'));
truthfileList = truthfileList(~startsWith({truthfileList.name}, '.')); %avoids hidden files
struct_truth= struct('truth_id', {}, 'truth_nick', {}, 'truth_vars', {});

fprintf('Bundling %d truth file(s) from %s\n', numel(truthfileList), paths.truths);

for h = 1:length(truthfileList)
    temp = load(fullfile(truthfileList(h).folder, truthfileList(h).name));
    struct_truth(h).truth_id = temp.truth_id;
    struct_truth(h).truth_nick = temp.truth_nick;
    struct_truth(h).truth_vars = temp;  % all truth srtucture in a field of the main struct
    clearvars temp
end

save(paths.truth_struct, "struct_truth", "-v7.3");
fprintf('Saved %s\n', paths.truth_struct);

end