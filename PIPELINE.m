function PIPELINE

% run all (or multiple) runs with MODEL_RUN.m 
% uses parfor, regular for version commented

mmdd=datestr(datetime('now'), 'mmdd');

opts = detectImportOptions("Runs-description.xlsx");
opts.DataRange = 'A2'; % Start reading from A2
runs_description = readtable("Runs-description.xlsx", opts);
clear opts


% Select the SIMULATION IDs form Runs-description.xlsx
% [1:140] 
sim_runs = 1:140;

% Select the REAL INCIDENCE IDs from Runs-description.xlsx
% [601:604]
real_runs = 601:604;

% Combine all values into a single vector
iiseries = [sim_runs real_runs];

% Create arrays for tracking
RunID = iiseries;
nickname = cell(length(iiseries), 1);
runtime = cell(length(iiseries), 1);

% Get nicknames
for k = 1:length(iiseries)
    idx = find(strcmp(runs_description.RunID, num2str(iiseries(k))), 1);
    nickname{k} = runs_description.nickname{idx};
end



%% Run model and forecasts
startTime = datetime('now');



% Parfor version
thr = 4

if isempty(gcp('nocreate')), parpool(thr); end

runtime = cell(1, length(iiseries)); % Pre-allocation is required for parfor slicing
parfor (k = 1:length(iiseries), thr)
    ii = iiseries(k);
    loopStart = datetime('now');
    
    model_forecast_run(ii, mmdd)
   
    runSeconds = seconds(datetime('now') - loopStart);
    hours = floor(runSeconds / 3600);
    minutes = floor(mod(runSeconds, 3600) / 60);
    secs = mod(runSeconds, 60);
    
    runtime{k} = sprintf('%dh %dm %.3fs', hours, minutes, secs);
    fprintf('\nCompleted run %d: %s in: (%s)\n', ii, nickname{k}, runtime{k});
end

%{
% regular for version

for k = 1:length(iiseries)
    ii = iiseries(k);
    loopStart = datetime('now');

    model_forecast_run(ii,mmdd)
   
    runSeconds = seconds(datetime('now') - loopStart);
    % Format runtime 
    hours = floor(runSeconds / 3600);
    minutes = floor(mod(runSeconds, 3600) / 60);
    secs = mod(runSeconds, 60);
    runtime{k} = sprintf('%dh %dm %.3fs', hours, minutes, secs);

    fprintf('\nCompleted run %d: %s in: (%s)\n\n', ii, nickname{k}, runtime{k});
end
%}


runtime_table = table(RunID', nickname, runtime);
disp(runtime_table);

totalTime = seconds(datetime('now') - startTime);
hours = floor(totalTime / 3600);
minutes = floor(mod(totalTime, 3600) / 60);
secs = mod(totalTime, 60);
totalTimeStr = sprintf('%dh %dm %.3fs', hours, minutes, secs);

fprintf('\nMODEL_RUN runtime: %s\n', totalTimeStr);


%% create forecasts metrics

% for each model run in 'Model_Runs/' creates a struct with forcasting metrics
% and saves it to in 'Forecasts/'


make_forecast_metrics
make_forecast_metrics_real

%% create groups of forecast metrics

make_forecast_group
make_forecast_group_real

% create the CSV output file
make_forecasts_groups_relbar_csv_synth.m
make_forecasts_groups_relbar_csv_real.m


% create the barplot figure of the paper with R

% Execute the R scripts for plotting the results
% plot_rel_bars_synth.R
% plot_rel_bars_real_split.R




