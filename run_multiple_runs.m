function run_multiple_runs
% 
mmdd=datestr(datetime('now'), 'mmdd');

opts = detectImportOptions("Runs-description.xlsx");
opts.DataRange = 'A2'; % Start reading from A2
runs_description = readtable("Runs-description.xlsx", opts);
clear opts

% % Get all runs seeded in a location
% iiseries = runs_description.RunID(runs_description.Seed_loc == "GA");

% [1:140]   sim pois
sim_pois = 1:140;

% [601:604] real pois
real_pois = 601:604;

% Combine all values into a single vector
iiseries = [sim_pois real_pois];

% Create arrays for tracking
RunID = iiseries;
nickname = cell(length(iiseries), 1);
runtime = cell(length(iiseries), 1);

% Get nicknames
for k = 1:length(iiseries)
    idx = find(strcmp(runs_description.RunID, num2str(iiseries(k))), 1);
    nickname{k} = runs_description.nickname{idx};
end



% Run the models and track time
startTime = datetime('now');


%{
% regular for
for k = 1:length(iiseries)
    ii = iiseries(k);
    loopStart = datetime('now');

    MODEL_RUN(ii,mmdd)
   
    runSeconds = seconds(datetime('now') - loopStart);
    % Format runtime 
    hours = floor(runSeconds / 3600);
    minutes = floor(mod(runSeconds, 3600) / 60);
    secs = mod(runSeconds, 60);
    runtime{k} = sprintf('%dh %dm %.3fs', hours, minutes, secs);

    fprintf('\nCompleted run %d: %s in: (%s)\n\n', ii, nickname{k}, runtime{k});
end
%}

% Parfor version
thr = 4

if isempty(gcp('nocreate')), parpool(thr); end

runtime = cell(1, length(iiseries)); % Pre-allocation is required for parfor slicing
parfor (k = 1:length(iiseries), thr)
    ii = iiseries(k);
    loopStart = datetime('now');
    
    MODEL_RUN(ii, mmdd)
   
    runSeconds = seconds(datetime('now') - loopStart);
    hours = floor(runSeconds / 3600);
    minutes = floor(mod(runSeconds, 3600) / 60);
    secs = mod(runSeconds, 60);
    
    runtime{k} = sprintf('%dh %dm %.3fs', hours, minutes, secs);
    fprintf('\nCompleted run %d: %s in: (%s)\n', ii, nickname{k}, runtime{k});
end






runtime_table = table(RunID', nickname, runtime);
disp(runtime_table);

totalTime = seconds(datetime('now') - startTime);
hours = floor(totalTime / 3600);
minutes = floor(mod(totalTime, 3600) / 60);
secs = mod(totalTime, 60);
totalTimeStr = sprintf('%dh %dm %.3fs', hours, minutes, secs);

fprintf('\nMODEL_RUN runtime: %s\n', totalTimeStr);

% Save to file (optional)

%%%%%%% RUN 
% make_truth_grouped_files.m 
% make_truth_stats_and_histogram.m
%%%%%%% first 
% then, put the right truth filename in make_forecast_metrics
